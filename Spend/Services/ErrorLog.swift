import Foundation
import os
import SwiftData

/// A place to say "this failed" instead of swallowing it with `try?`.
///
/// `report` does two things:
/// 1. Keeps the last 20 failures on the phone (UserDefaults), newest first, for
///    Settings › About › Developer › Recent errors. Each entry is the date, the
///    place in the code, the error's type name and its description cut to 120
///    characters. Never a purchase, a shop name or an amount from the caller.
/// 2. When crash reports are on (`CrashReporting.isOn`), sends one non-fatal to
///    Sentry through the same scrub as a crash. It carries the place and the
///    error TYPE only. Descriptions can contain user text, so they stay here.
///
/// The helpers are pure so tests pin the cap, the order and the trimming.
enum ErrorLog {
    nonisolated struct Entry: Codable, Equatable, Sendable {
        var date: Date
        var place: String
        var type: String
        var message: String
    }

    nonisolated static let capacity = 20
    nonisolated static let messageLimit = 120
    nonisolated static let key = "errorLog.recent"

    private nonisolated static let lock = NSLock()
    private nonisolated static let logger = Logger(subsystem: "com.kameshraj.sortd", category: "errors")

    // MARK: - Pure helpers

    /// At most `limit` characters; longer text ends in an ellipsis inside the limit.
    nonisolated static func trimmed(_ text: String, to limit: Int = messageLimit) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(max(limit - 1, 0))) + "…"
    }

    nonisolated static func entry(for error: Error, where place: String, at date: Date) -> Entry {
        Entry(date: date,
              place: trimmed(place, to: 60),
              type: String(describing: Swift.type(of: error)),
              message: trimmed(error.localizedDescription))
    }

    /// New entry first, list cut to `capacity`.
    nonisolated static func adding(_ entry: Entry, to entries: [Entry]) -> [Entry] {
        Array(([entry] + entries).prefix(capacity))
    }

    // MARK: - Storage

    nonisolated static func recent(defaults: UserDefaults = .standard) -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    nonisolated static func clear(defaults: UserDefaults = .standard) {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }

    /// Records the failure. Safe to call from any thread.
    nonisolated static func report(_ error: Error, where place: String,
                                   defaults: UserDefaults = .standard, now: Date = .now) {
        let item = entry(for: error, where: place, at: now)
        lock.lock()
        let updated = adding(item, to: recent(defaults: defaults))
        if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: key) }
        lock.unlock()
        logger.error("error logged at \(item.place, privacy: .public): \(item.type, privacy: .public)")
        if defaults === UserDefaults.standard {
            let type = item.type
            let place = item.place
            Task { @MainActor in
                if CrashReporting.isOn { CrashReporting.captureNonFatal(where: place, errorType: type) }
            }
        }
    }
}

extension ModelContext {
    /// `try? save()` that tells someone. Returns false when the save failed so a
    /// screen can show `.saveFailedAlert`. Same behaviour otherwise.
    @discardableResult
    nonisolated func saveReporting(where place: String) -> Bool {
        do {
            try save()
            return true
        } catch {
            ErrorLog.report(error, where: place)
            return false
        }
    }
}
