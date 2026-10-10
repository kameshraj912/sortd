import Foundation

/// "Check the Shortcut" (spec 2026-09-26, failsafe #11): a real run of the
/// user's own automation, not just Sortd's in-app ▶. Opens the Sortd
/// shortcut through Shortcuts' own `run-shortcut` URL scheme with a known
/// payload, then waits to see whether it actually reaches Sortd.
///
/// What really arrives (beta data, 10 Oct 2026): the ready-made shortcut
/// (`scripts/build-apple-pay-shortcut.py`) has no Text step and reads its
/// input as a Wallet transaction, so the text payload below never reaches
/// Sortd. The run lands with every field empty: no amount, shop, card, text
/// or notification part. That still proves the chain (Shortcuts ran the
/// shortcut, and the shortcut reached Sortd), which is all the check needs;
/// `resolve` only looks at when Sortd was last reached. The run event tells
/// such a run apart by time: an empty run within `timeout` of
/// `markStarted` is `health_check`, any other is `empty_run`
/// (`LogWalletTapIntent.runEvent`).
///
/// If a future shortcut does pass the text on, "Sortd Check A$0.01 Test
/// Card" reads as merchant "Sortd Check" (`WalletTapText.parse`). `merchant`
/// is its own excluded test constant, kept apart from
/// `LogPurchaseIntent.legacyTestMerchant` but excluded everywhere the same
/// way: never a real tap, never real spending, never activation.
enum ApplePayHealthCheck {
    static let payloadText = "Sortd Check A$0.01 Test Card"
    static let merchant = "Sortd Check"

    /// The ready-made shortcut's own name, as `ApplePaySetupPanel`'s picture
    /// guide shows it (`WalletSetupGuide`'s "Log Apple Pay in Sortd" token).
    /// If a future guide renames it, this is the one place to change.
    static let shortcutName = "Log Apple Pay in Sortd"

    /// How long to wait before honestly saying nothing arrived.
    static let timeout: TimeInterval = 20

    /// When "Check the Shortcut" was last tapped, in the same defaults the
    /// intent writes its "last reached" time to
    /// (`LogPurchaseIntent.reachDefaults`), so the run it starts can be
    /// named in the run event.
    static let startedAtKey = "healthCheckStartedAt"

    static func markStarted(at now: Date = .now, defaults: UserDefaults = LogPurchaseIntent.reachDefaults) {
        defaults.set(now, forKey: startedAtKey)
    }

    static func lastStartedAt(_ defaults: UserDefaults = LogPurchaseIntent.reachDefaults) -> Date? {
        defaults.object(forKey: startedAtKey) as? Date
    }

    /// Pure: whether a run at `now` falls inside a check started at
    /// `startedAt` (from the tap, up to `timeout` seconds later).
    static func isWithinCheck(startedAt: Date?, now: Date) -> Bool {
        guard let startedAt else { return false }
        let gap = now.timeIntervalSince(startedAt)
        return gap >= 0 && gap <= timeout
    }

    /// `shortcuts://run-shortcut?name=...&input=text&text=...` — this runs
    /// the person's own automation, not Sortd's intent directly, so it
    /// proves the whole chain (Wallet trigger → Shortcuts → Sortd), not just
    /// that Sortd itself works.
    static var runURL: URL? {
        var components = URLComponents(string: "shortcuts://run-shortcut")
        components?.queryItems = [
            URLQueryItem(name: "name", value: shortcutName),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: payloadText),
        ]
        return components?.url
    }

    enum State: Equatable {
        case waiting
        case reached(Date)
        case timedOut
    }

    /// Pure: whether a check started at `startedAt` has been answered by
    /// `now`, given the latest moment Shortcuts reached Sortd at all
    /// (a health-check run counts as "reached" the same way a bare ▶ run
    /// does — see `ApplePayStatus`). No sleeps needed to test this: it's
    /// plain date arithmetic, polled by the view on a timer in production.
    static func resolve(startedAt: Date, lastReachedAt: Date?, now: Date) -> State {
        if let lastReachedAt, lastReachedAt >= startedAt { return .reached(lastReachedAt) }
        if now.timeIntervalSince(startedAt) >= timeout { return .timedOut }
        return .waiting
    }
}
