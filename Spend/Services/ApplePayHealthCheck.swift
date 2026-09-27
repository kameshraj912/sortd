import Foundation

/// "Check the Shortcut" (spec 2026-09-26, failsafe #11): a real run of the
/// user's own automation, not just Sortd's in-app ▶. Opens the Sortd
/// shortcut through Shortcuts' own `run-shortcut` URL scheme with a known
/// payload, then waits to see whether it actually reaches Sortd.
///
/// The payload is text, exactly like the by-hand Transaction route already
/// sends (`WalletTapText.parse`): "Sortd Check A$0.01 Test Card" reads as
/// merchant "Sortd Check", amount A$0.01, card "Test Card". `merchant` is
/// its own excluded test constant — kept separate from
/// `LogPurchaseIntent.legacyTestMerchant` (the removed test button's own
/// marker) but excluded everywhere the same way: never a real tap, never
/// real spending, never activation.
enum ApplePayHealthCheck {
    static let payloadText = "Sortd Check A$0.01 Test Card"
    static let merchant = "Sortd Check"

    /// The ready-made shortcut's own name, as `ApplePaySetupPanel`'s picture
    /// guide shows it (`WalletSetupGuide`'s "Log Apple Pay in Sortd" token).
    /// If a future guide renames it, this is the one place to change.
    static let shortcutName = "Log Apple Pay in Sortd"

    /// How long to wait before honestly saying nothing arrived.
    static let timeout: TimeInterval = 20

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
