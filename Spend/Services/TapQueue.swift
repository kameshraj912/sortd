import Foundation
import SwiftData

/// A tap Sortd could not save the moment it arrived — the store failed to
/// open, or the save itself threw (disk full, corrupt file, failed
/// migration: failure #8 in the "Apple Pay logging — failsafes" spec,
/// 2026-09-26). Never lost: the raw fields are written to a small file in
/// the app group container instead, then replayed through
/// `LogPurchaseIntent.handle` (which itself goes through
/// `TransactionLogger.log`) the next time Sortd opens, or comes back to the
/// foreground.
enum TapQueue {
    /// Everything an intent had for one tap, so a replay reproduces exactly
    /// what would have logged at the time — including `date`, so "last tap
    /// received" reads the original moment, not when Sortd got around to it.
    nonisolated struct Entry: Codable, Equatable, Sendable {
        var merchant: String?
        var amount: String?
        var card: String?
        var date: Date
        /// `TapTrigger` raw value: "n" when Wallet's notification sent it
        /// (its fields are then already read from the notification). Nil
        /// means the tap trigger, as every entry before 2 Oct 2026.
        var trigger: String? = nil

        /// Dedupe key: the exact text and time already queued, so a crash
        /// mid-append (or the same failed run reaching Sortd twice) never
        /// queues — or later logs — the same tap twice.
        var key: String { [merchant ?? "", amount ?? "", card ?? "", date.timeIntervalSince1970.description].joined(separator: "|") }
    }

    nonisolated static let fileName = "tap-queue.json"

    /// The app group file when the entitlement is present. A free developer
    /// account has no App Group, so `fallbackURL` keeps the queue working
    /// (just not shared with the widget process, which never reads it).
    nonisolated static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSummary.appGroup)?
            .appending(path: fileName)
    }

    private nonisolated static var fallbackURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true).appending(path: fileName)
    }

    private nonisolated static func resolve(_ override: URL?) -> URL? { override ?? fileURL ?? fallbackURL }

    nonisolated static func read(from url: URL? = nil) -> [Entry] {
        guard let target = resolve(url), let data = try? Data(contentsOf: target) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    private nonisolated static func write(_ entries: [Entry], to url: URL? = nil) {
        guard let target = resolve(url) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(entries).write(to: target, options: .atomic)
        } catch {
            ErrorLog.report(error, where: "TapQueue.write")
        }
    }

    private nonisolated static let lock = NSLock()

    /// Every change to the queue goes through here: read, change, write
    /// back, all under one lock. A tap and its Wallet notification can
    /// arrive seconds apart, and a replay can be running when either does;
    /// without the lock two of them could read the same list and the later
    /// write would drop the other's tap. Safe to call from any thread.
    /// Returns the queue as it now stands.
    @discardableResult
    private nonisolated static func update(_ url: URL?, _ change: (inout [Entry]) -> Void) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        let before = read(from: url)
        var entries = before
        change(&entries)
        if entries != before { write(entries, to: url) }
        return entries
    }

    /// How many taps are waiting on the next replay (diagnostics).
    static var count: Int { read().count }

    private static let lastReplayKey = "tapQueueLastReplay"

    /// "Replayed 2 queued taps", for the hidden developer sheet. Empty
    /// before the first replay ever runs.
    static var lastReplaySummary: String {
        UserDefaults.standard.string(forKey: lastReplayKey) ?? "Never run"
    }

    /// Appends one tap. A duplicate (the exact same fields at the exact
    /// same moment already queued) is a no-op, not a second row.
    @discardableResult
    nonisolated static func enqueue(merchant: String?, amount: String?, card: String?, date: Date = .now,
                                    trigger: TapTrigger = .tap, url: URL? = nil) -> [Entry] {
        let entry = Entry(merchant: merchant, amount: amount, card: card, date: date,
                          trigger: trigger == .tap ? nil : trigger.rawValue)
        return update(url) { entries in
            guard !entries.contains(where: { $0.key == entry.key }) else { return }
            entries.append(entry)
        }
    }

    /// Queues the tap, tells the one-per-queue local notification to fire
    /// (or refresh, if one is already pending), and returns the dialog text
    /// Shortcuts should read out — a success, from its point of view, so the
    /// automation never shows as failed.
    @MainActor
    @discardableResult
    static func saveForLater(merchant: String?, amount: String?, card: String?, date: Date = .now,
                             trigger: TapTrigger = .tap, url: URL? = nil) async -> String {
        enqueue(merchant: merchant, amount: amount, card: card, date: date, trigger: trigger, url: url)
        await Reminders.notifyTapQueued()
        return "Saved for later. Sortd will finish it when it next opens."
    }

    struct ReplayResult: Equatable {
        var replayed: Int
        var stillQueued: Int

        var summary: String {
            if replayed == 0, stillQueued == 0 { return "Nothing queued" }
            if stillQueued == 0 { return "Replayed \(replayed) queued tap\(replayed == 1 ? "" : "s")" }
            return "Replayed \(replayed), \(stillQueued) still waiting"
        }
    }

    /// Replays every queued tap through the normal logging path and takes
    /// each one that lands out of the queue. One that fails again (the
    /// store is still unavailable) stays queued for the next try — it is
    /// never dropped, and never queued twice: `LogPurchaseIntent.handle`'s
    /// failure path queues it again into this same file, where `enqueue`
    /// sees the same key and does nothing.
    ///
    /// Only the taps this replay logged are removed, at the end, under the
    /// lock. The list read at the start is never written back: that would
    /// wipe a tap queued while the replay was waiting on a save.
    ///
    /// "Last replay" in the developer menu is about the real queue, so a
    /// replay of any other file (`url`, tests) leaves it alone.
    @MainActor
    @discardableResult
    static func replay(in context: ModelContext, book: CardBook = .shared, url: URL? = nil,
                       debugForceSaveFailure: Bool = false) async -> ReplayResult {
        let entries = read(from: url)
        guard !entries.isEmpty else {
            let result = ReplayResult(replayed: 0, stillQueued: 0)
            if url == nil { UserDefaults.standard.set(result.summary, forKey: lastReplayKey) }
            return result
        }
        var logged: Set<String> = []
        for entry in entries {
            let outcome = try? await LogPurchaseIntent.handle(merchant: entry.merchant, amount: entry.amount, card: entry.card,
                                                              in: context, book: book, now: entry.date,
                                                              debugForceSaveFailure: debugForceSaveFailure,
                                                              trigger: entry.trigger.flatMap(TapTrigger.init(rawValue:)) ?? .tap,
                                                              queueURL: url)
            if let outcome, !outcome.saveFailed { logged.insert(entry.key) }
        }
        let remaining = update(url) { $0.removeAll { logged.contains($0.key) } }
        if remaining.isEmpty { Reminders.clearTapQueuedNotice() }
        let result = ReplayResult(replayed: logged.count, stillQueued: remaining.count)
        if url == nil { UserDefaults.standard.set(result.summary, forKey: lastReplayKey) }
        return result
    }
}
