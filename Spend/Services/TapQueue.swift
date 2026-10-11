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
        /// `TapTrigger` raw value: "n" when Wallet's notification sent it,
        /// "b" a bank app's (its fields are then already read from the
        /// notification). Nil
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

    /// Where the queue may be: the given file alone (a test's), or the app
    /// group file and then `fallbackURL`. A tap is written to the second
    /// when the first can't be written, so both are read back.
    private nonisolated static func locations(_ override: URL?) -> [URL] {
        if let override { return [override] }
        var all: [URL] = []
        for url in [fileURL, fallbackURL] { if let url, !all.contains(url) { all.append(url) } }
        return all
    }

    nonisolated static func read(from url: URL? = nil) -> [Entry] {
        locations(url).flatMap(readFile)
    }

    private nonisolated static func readFile(_ target: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: target) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    /// True when the file now holds `entries`.
    private nonisolated static func write(_ entries: [Entry], to target: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(entries).write(to: target, options: .atomic)
            return true
        } catch {
            ErrorLog.report(error, where: "TapQueue.write")
            return false
        }
    }

    private nonisolated static let lock = NSLock()

    /// Every change to one queue file goes through here: read, change,
    /// write back, all under one lock. A tap and its Wallet notification
    /// can arrive seconds apart, and a replay can be running when either
    /// does; without the lock two of them could read the same list and the
    /// later write would drop the other's tap. Safe to call from any thread.
    /// Returns the file's queue as it now stands, and false when the change
    /// could not be written.
    @discardableResult
    private nonisolated static func update(_ target: URL, _ change: (inout [Entry]) -> Void) -> (entries: [Entry], written: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let before = readFile(target)
        var entries = before
        change(&entries)
        guard entries != before else { return (entries, true) }
        return write(entries, to: target) ? (entries, true) : (before, false)
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
    /// same moment already queued) is a no-op, not a second row. When the
    /// first file can't be written (a full disk, a missing folder), the
    /// next location is tried. False when no file could take it.
    @discardableResult
    nonisolated static func enqueue(merchant: String?, amount: String?, card: String?, date: Date = .now,
                                    trigger: TapTrigger = .tap, url: URL? = nil) -> Bool {
        enqueue(Entry(merchant: merchant, amount: amount, card: card, date: date,
                      trigger: trigger == .tap ? nil : trigger.rawValue),
                into: locations(url))
    }

    /// `enqueue` into the first of `all` that can be written. Tests pass
    /// their own list.
    nonisolated static func enqueue(_ entry: Entry, into all: [URL]) -> Bool {
        if all.contains(where: { readFile($0).contains { $0.key == entry.key } }) { return true }
        for target in all {
            let result = update(target) { entries in
                guard !entries.contains(where: { $0.key == entry.key }) else { return }
                entries.append(entry)
            }
            if result.written { return true }
        }
        return false
    }

    /// Delete All Data: every queued tap goes, from every place the queue
    /// may be, so none comes back at the next launch.
    nonisolated static func clear(url: URL? = nil) {
        for target in locations(url) { update(target) { $0.removeAll() } }
    }

    static let notSavedMessage = "This tap couldn't be saved. Add it in Sortd by hand."

    /// Queues the tap, tells the one-per-queue local notification to fire
    /// (or refresh, if one is already pending), and returns the dialog text
    /// Shortcuts should read out — a success, from its point of view, so the
    /// automation never shows as failed. "Saved for later" only when a file
    /// really holds it; otherwise it says plainly that it was not saved.
    @MainActor
    @discardableResult
    static func saveForLater(merchant: String?, amount: String?, card: String?, date: Date = .now,
                             trigger: TapTrigger = .tap, url: URL? = nil) async -> String {
        let saved = enqueue(merchant: merchant, amount: amount, card: card, date: date, trigger: trigger, url: url)
        await Reminders.notifyTapQueued(saved: saved)
        return saved ? "Saved for later. Sortd will finish it when it next opens." : notSavedMessage
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
        var remaining = 0
        for target in locations(url) {
            remaining += update(target) { $0.removeAll { logged.contains($0.key) } }.entries.count
        }
        if remaining == 0 { Reminders.clearTapQueuedNotice() }
        let result = ReplayResult(replayed: logged.count, stillQueued: remaining)
        if url == nil { UserDefaults.standard.set(result.summary, forKey: lastReplayKey) }
        return result
    }
}
