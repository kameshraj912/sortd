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
    struct Entry: Codable, Equatable, Sendable {
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

    static let fileName = "tap-queue.json"

    /// The app group file when the entitlement is present. A free developer
    /// account has no App Group, so `fallbackURL` keeps the queue working
    /// (just not shared with the widget process, which never reads it).
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSummary.appGroup)?
            .appending(path: fileName)
    }

    private static var fallbackURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true).appending(path: fileName)
    }

    private static func resolve(_ override: URL?) -> URL? { override ?? fileURL ?? fallbackURL }

    static func read(from url: URL? = nil) -> [Entry] {
        guard let target = resolve(url), let data = try? Data(contentsOf: target) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    private static func write(_ entries: [Entry], to url: URL? = nil) {
        guard let target = resolve(url) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(entries).write(to: target, options: .atomic)
        } catch {
            ErrorLog.report(error, where: "TapQueue.write")
        }
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
    static func enqueue(merchant: String?, amount: String?, card: String?, date: Date = .now,
                        trigger: TapTrigger = .tap, url: URL? = nil) -> [Entry] {
        var entries = read(from: url)
        let entry = Entry(merchant: merchant, amount: amount, card: card, date: date,
                          trigger: trigger == .tap ? nil : trigger.rawValue)
        guard !entries.contains(where: { $0.key == entry.key }) else { return entries }
        entries.append(entry)
        write(entries, to: url)
        return entries
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

    /// Replays every queued tap through the normal logging path and clears
    /// the queue as each one lands. One that fails again (the store is
    /// still unavailable) stays queued for the next try — it is never
    /// dropped, and it is never re-queued a second time by the replay
    /// itself: `LogPurchaseIntent.handle`'s own failure path only queues
    /// fresh intent calls, not a replay's own retries (see its `saveFailed`
    /// flag).
    @MainActor
    @discardableResult
    static func replay(in context: ModelContext, book: CardBook = .shared, url: URL? = nil,
                       debugForceSaveFailure: Bool = false) async -> ReplayResult {
        let entries = read(from: url)
        guard !entries.isEmpty else {
            let result = ReplayResult(replayed: 0, stillQueued: 0)
            UserDefaults.standard.set(result.summary, forKey: lastReplayKey)
            return result
        }
        var remaining: [Entry] = []
        var replayed = 0
        for entry in entries {
            let outcome = try? await LogPurchaseIntent.handle(merchant: entry.merchant, amount: entry.amount, card: entry.card,
                                                              in: context, book: book, now: entry.date,
                                                              debugForceSaveFailure: debugForceSaveFailure,
                                                              trigger: entry.trigger.flatMap(TapTrigger.init(rawValue:)) ?? .tap)
            if let outcome, !outcome.saveFailed {
                replayed += 1
            } else {
                remaining.append(entry)
            }
        }
        write(remaining, to: url)
        if remaining.isEmpty { Reminders.clearTapQueuedNotice() }
        let result = ReplayResult(replayed: replayed, stillQueued: remaining.count)
        UserDefaults.standard.set(result.summary, forKey: lastReplayKey)
        return result
    }
}
