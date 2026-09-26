import Foundation

/// "No Apple Pay taps for two weeks. Still paying with your phone? Check the
/// automation." Apple's own side fails silently more than once (spec
/// 2026-09-26, failure modes #1/#3): a stuck "Ask Before Running"
/// automation, or its transaction-timeout bug. Sortd can't see the
/// automation itself, only that nothing has arrived — so once logging was
/// ever set up and 14 days pass with nothing, say so once, then stay quiet
/// until another 14 days of nothing pass again.
enum ApplePayNudge {
    static let interval: TimeInterval = 14 * 24 * 3600
    static let lastShownKey = "applePayNudgeLastShown"

    /// Whether the quiet line (setup page) or Home card should show right
    /// now.
    /// - `setupEverReached`: Apple Pay logging was set up at all — a real
    ///   tap or a bare ▶/health-check run has ever reached Sortd
    ///   (`ApplePayStatus.isConnected` at some point, tracked by
    ///   `LogPurchaseIntent.shortcutHasReachedApp`).
    /// - `lastActivityAt`: the most recent moment Shortcuts reached Sortd at
    ///   all (`LogPurchaseIntent.lastTapReceivedAt`).
    /// - `lastShownAt`: when the nudge last showed (`lastShownKey`).
    static func shouldShow(setupEverReached: Bool, lastActivityAt: Date?, lastShownAt: Date?, now: Date = .now) -> Bool {
        guard setupEverReached, let lastActivityAt else { return false }
        guard now.timeIntervalSince(lastActivityAt) >= interval else { return false }
        // Never shown before for this silent stretch: due now. Shown
        // before: due again only once another full interval has passed
        // *since it last showed* — measured from `lastShownAt`, not from
        // `lastActivityAt` (which never moves while nothing arrives), so
        // dismissing it doesn't bring it right back the next day, and it
        // still repeats roughly every 14 days while the silence continues.
        guard let lastShownAt else { return true }
        return now.timeIntervalSince(lastShownAt) >= interval
    }

    @discardableResult
    static func markShown(now: Date = .now, defaults: UserDefaults = .standard) -> Date {
        defaults.set(now, forKey: lastShownKey)
        return now
    }

    static func lastShown(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastShownKey) as? Date
    }

    static let line = "No Apple Pay taps for two weeks. Still paying with your phone? Check the automation."
}
