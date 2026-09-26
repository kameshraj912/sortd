import Foundation

/// What the Apple Pay Logging page can honestly say. Every state comes from
/// a real event — the Shortcut reaching the app (a real ▶ run or a real
/// tap), or a real shop tap being logged. The app never sets "reached" on
/// its own; only a run through the Shortcut does (spec 2026-09-25).
enum ApplePayStatus: Equatable {
    /// The Shortcut has never reached Sortd.
    case notConnected
    /// The Shortcut ran and reached the app (a ▶ test run counts), but no
    /// shop tap has landed yet.
    case shortcutReached(Date)
    /// A real shop tap was logged.
    case tapLogged(date: Date, merchant: String, amount: Decimal, currency: String)

    /// Where "Learn more" on the timeout line goes.
    static let learnMoreURL = URL(string: "https://sortd.page/support#apple-pay")!

    /// Every taps' worth of `transactions` that counts as a real shop tap:
    /// `seenIn` has `.tap` (a tap merged with an email still counts), and it
    /// is not the removed "Send a Test Tap" button's rows (old installs may
    /// still have some; they stay excluded, not deleted).
    ///
    /// No `note != DemoData.marker` check: `DemoData.load` only ever inserts
    /// with `source: .manual`, so a sample row never has `.tap` in `seenIn`
    /// on its own. If one does, a real Wallet tap deduped onto it — the note
    /// stays "Sample purchase" (`TransactionLogger.merge` doesn't touch it),
    /// but the tap is genuine and must count (found in a router feel check:
    /// a real refund tap merged onto a same-day, same-amount demo row read
    /// as "not connected" because of this check).
    static func realTaps(in transactions: [Transaction]) -> [Transaction] {
        transactions.filter { t in
            t.seenIn.contains(.tap)
                && t.merchant != LogPurchaseIntent.legacyTestMerchant
                && t.rawMerchant != LogPurchaseIntent.legacyTestMerchant
                && t.merchant != ApplePayHealthCheck.merchant
                && t.rawMerchant != ApplePayHealthCheck.merchant
        }
    }

    /// True once any real shop tap has been seen.
    static func hasRealTap(in transactions: [Transaction]) -> Bool {
        !realTaps(in: transactions).isEmpty
    }

    /// How many taps landed with too little to log cleanly — a blank
    /// amount, a blank shop, or a card with neither (spec 2026-09-26,
    /// failsafes #2/#10) — and still need a look. Excludes the legacy test
    /// button's rows and the "Check the Shortcut" health check's own rows:
    /// neither is a real tap, and DemoData's untouched sample rows never
    /// carry a real tap's note in the first place.
    static func needsCheckCount(in transactions: [Transaction]) -> Int {
        transactions.count { t in
            t.needsCheck
                && t.note != DemoData.marker
                && t.merchant != LogPurchaseIntent.legacyTestMerchant && t.rawMerchant != LogPurchaseIntent.legacyTestMerchant
                && t.merchant != ApplePayHealthCheck.merchant && t.rawMerchant != ApplePayHealthCheck.merchant
        }
    }

    /// "1 tap needs a check" / "3 taps need a check", or nil when there's
    /// nothing to flag. A separate line from the status card's own headline,
    /// which stays about the connection, not about individual rows.
    static func needsCheckLine(count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 tap needs a check" : "\(count) taps need a check"
    }

    /// `lastReachedAt` is `LogPurchaseIntent.lastTapAtKey`: when Shortcuts
    /// last reached the app at all, including an empty ▶ run. `taps` is
    /// every transaction seen so far — only the real ones (see `realTaps`)
    /// can move the status past "reached".
    static func resolve(lastReachedAt: Date?, taps: [Transaction], now: Date = .now) -> ApplePayStatus {
        if let latest = realTaps(in: taps).max(by: { $0.date < $1.date }) {
            return .tapLogged(date: latest.date, merchant: latest.merchant,
                              amount: latest.amount, currency: latest.currencyCode)
        }
        if let lastReachedAt { return .shortcutReached(lastReachedAt) }
        return .notConnected
    }

    /// One-time launch fix. Some early installs' "reached" flag was set only
    /// by the removed test-tap button, never by a real run through the
    /// Shortcut — so it lied. If the last raw tap Shortcuts sent named the
    /// test merchant, and no real tap has ever landed, clear the flag. A
    /// real ▶ run or shop tap sets it again; nothing else is touched.
    @discardableResult
    static func settleTestTap(hasRealTap: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard !hasRealTap, defaults.object(forKey: LogPurchaseIntent.lastTapAtKey) != nil else { return false }
        let raw = defaults.string(forKey: LogPurchaseIntent.lastTapKey) ?? ""
        guard raw.contains("merchant \u{201C}\(LogPurchaseIntent.legacyTestMerchant)\u{201D}") else { return false }
        defaults.removeObject(forKey: LogPurchaseIntent.lastTapAtKey)
        return true
    }
}

extension ApplePayStatus {
    /// Whether the status card should show as "good" (the green background,
    /// the settled symbol).
    var isConnected: Bool {
        switch self {
        case .notConnected: false
        case .shortcutReached, .tapLogged: true
        }
    }

    var symbol: String {
        switch self {
        case .notConnected: "wave.3.right"
        case .shortcutReached: "link"
        case .tapLogged: "checkmark"
        }
    }

    private static func when(_ date: Date) -> String {
        let cal = Calendar.current
        let day = cal.isDateInToday(date) ? "Today"
            : cal.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(day) \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// The status card's headline.
    var title: String {
        switch self {
        case .notConnected: "Not connected yet"
        case .shortcutReached(let date): "Shortcut reached Sortd · \(Self.when(date))"
        case .tapLogged(let date, _, _, _): "Last tap logged · \(Self.when(date))"
        }
    }

    /// The status card's second line.
    var detail: String {
        switch self {
        case .notConnected: "Get the Shortcut, then turn it on for your cards."
        case .shortcutReached: "Now pay in a shop. The tap shows up here."
        case .tapLogged(_, let merchant, let amount, let currency): "\(Money.format(amount, currency)) at \(merchant)"
        }
    }

    /// One VoiceOver element for the whole card. `tapLogged` speaks the shop
    /// and the amount in full, not the eye-only short form.
    var accessibilityLabel: String {
        switch self {
        case .notConnected, .shortcutReached:
            "\(title). \(detail)"
        case .tapLogged(_, let merchant, let amount, let currency):
            "Last tap logged. \(Money.spoken(amount, currency)) at \(merchant)"
        }
    }
}
