import Testing
import Foundation
import SwiftData
@testable import Spend

/// The Apple Pay Logging page's status (spec 2026-09-25, option A): every
/// state comes from a real event, so it can't lie. `resolve` and
/// `settleTestTap` are pure apart from `UserDefaults`, so they're tested
/// directly, with no ModelContext needed for `resolve` (a `Transaction` can
/// be built and read without ever being inserted anywhere).
struct ApplePayStatusTests {
    private let reached = Date(timeIntervalSince1970: 1_790_000_000) // 10:53:20 UTC
    private let tapped = Date(timeIntervalSince1970: 1_790_010_000)  // later

    private func tap(_ merchant: String, amount: Decimal = Decimal(string: "4.50")!, currency: String = "AUD",
                     at date: Date, note: String = "") -> Transaction {
        Transaction(date: date, merchant: merchant, amount: amount, currencyCode: currency,
                   card: .other, category: .eatingOut, source: .tap, note: note)
    }

    // MARK: resolve

    @Test func nothingAtAllIsNotConnected() {
        #expect(ApplePayStatus.resolve(lastReachedAt: nil, taps: []) == .notConnected)
    }

    @Test func aBareRunIsShortcutReached() {
        #expect(ApplePayStatus.resolve(lastReachedAt: reached, taps: []) == .shortcutReached(reached))
    }

    @Test func aRealTapIsTapLogged() {
        let t = tap("Seven Seeds", amount: Decimal(string: "4.50")!, at: tapped)
        let status = ApplePayStatus.resolve(lastReachedAt: reached, taps: [t])
        #expect(status == .tapLogged(date: tapped, merchant: "Seven Seeds", amount: Decimal(string: "4.50")!, currency: "AUD"))
    }

    /// A restored backup: the tap is in the store but the flag never got set
    /// on this install. The tap alone is enough.
    @Test func aRealTapCountsWithNoReachedFlag() {
        let t = tap("Seven Seeds", at: tapped)
        let status = ApplePayStatus.resolve(lastReachedAt: nil, taps: [t])
        #expect(status == .tapLogged(date: tapped, merchant: "Seven Seeds", amount: Decimal(string: "4.50")!, currency: "AUD"))
    }

    /// `DemoData.load` only ever inserts with `source: .manual`, so an
    /// untouched sample row never has `.tap` in `seenIn`.
    @Test func untouchedDemoRowsAreNotConnected() {
        let t = Transaction(date: tapped, merchant: "Uber", amount: Decimal(string: "4.50")!, currencyCode: "AUD",
                            card: .other, category: .eatingOut, source: .manual, note: DemoData.marker)
        #expect(ApplePayStatus.resolve(lastReachedAt: nil, taps: [t]) == .notConnected)
    }

    /// Router feel check, 26 Sep 2026: a real refund tap deduped onto a
    /// same-day, same-amount demo row (`TransactionLogger.merge` adds `.tap`
    /// to `seenIn` but never clears `note`). It's a real event and must
    /// count, even though the note still says "Sample purchase".
    @Test func aRealTapMergedIntoADemoRowStillCounts() {
        let t = tap("Uniqlo", amount: Decimal(string: "59.90")!, at: tapped, note: DemoData.marker)
        let status = ApplePayStatus.resolve(lastReachedAt: nil, taps: [t])
        #expect(status == .tapLogged(date: tapped, merchant: "Uniqlo", amount: Decimal(string: "59.90")!, currency: "AUD"))
    }

    /// A received tap with a shop and an amount beats "reached", even when
    /// the flag was set at (or after) the same moment: the tap is the more
    /// specific, more real event.
    @Test func aReceivedTapWithShopAndAmountBeatsReached() {
        let t = tap("Uniqlo", amount: Decimal(string: "59.90")!, at: tapped)
        let status = ApplePayStatus.resolve(lastReachedAt: tapped, taps: [t])
        #expect(status == .tapLogged(date: tapped, merchant: "Uniqlo", amount: Decimal(string: "59.90")!, currency: "AUD"))
    }

    @Test func onlyLegacyTestTapsAreNotConnected() {
        let t = tap(LogPurchaseIntent.legacyTestMerchant, at: tapped)
        #expect(ApplePayStatus.resolve(lastReachedAt: nil, taps: [t]) == .notConnected)
    }

    @Test func twoTapsPickTheLaterOne() {
        let earlier = tap("Coles", at: reached)
        let later = tap("Woolworths", at: tapped)
        let status = ApplePayStatus.resolve(lastReachedAt: nil, taps: [earlier, later])
        #expect(status == .tapLogged(date: tapped, merchant: "Woolworths", amount: Decimal(string: "4.50")!, currency: "AUD"))
    }

    @Test func aTapMergedWithAnEmailStillCounts() {
        let t = tap("Netflix", at: tapped)
        t.markSeen(in: .email)
        #expect(t.seenIn.contains(.tap) && t.seenIn.contains(.email))
        let status = ApplePayStatus.resolve(lastReachedAt: nil, taps: [t])
        #expect(status == .tapLogged(date: tapped, merchant: "Netflix", amount: Decimal(string: "4.50")!, currency: "AUD"))
    }

    // MARK: settleTestTap

    private func rawText(_ merchant: String, at date: Date = .now) -> String {
        "\(date.formatted(date: .abbreviated, time: .standard)): amount “A$4.50” · merchant “\(merchant)” · card “NAB Visa Debit”"
    }

    private func settleDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ApplePayStatusTests-\(UUID().uuidString)")!
    }

    @Test func testTapRawTextWithNoRealTapClearsReached() {
        let d = settleDefaults()
        d.set(rawText(LogPurchaseIntent.legacyTestMerchant), forKey: LogPurchaseIntent.lastTapKey)
        d.set(Date.now, forKey: LogPurchaseIntent.lastTapAtKey)
        let cleared = ApplePayStatus.settleTestTap(hasRealTap: false, defaults: d)
        #expect(cleared)
        #expect(d.object(forKey: LogPurchaseIntent.lastTapAtKey) == nil)
    }

    @Test func runningTwiceMakesNoFurtherChange() {
        let d = settleDefaults()
        d.set(rawText(LogPurchaseIntent.legacyTestMerchant), forKey: LogPurchaseIntent.lastTapKey)
        d.set(Date.now, forKey: LogPurchaseIntent.lastTapAtKey)
        #expect(ApplePayStatus.settleTestTap(hasRealTap: false, defaults: d))
        #expect(!ApplePayStatus.settleTestTap(hasRealTap: false, defaults: d), "the second run has nothing left to clear")
        #expect(d.object(forKey: LogPurchaseIntent.lastTapAtKey) == nil)
    }

    @Test func aRealTapKeepsReachedEvenWithATestRawText() {
        let d = settleDefaults()
        d.set(rawText(LogPurchaseIntent.legacyTestMerchant), forKey: LogPurchaseIntent.lastTapKey)
        d.set(Date.now, forKey: LogPurchaseIntent.lastTapAtKey)
        #expect(!ApplePayStatus.settleTestTap(hasRealTap: true, defaults: d))
        #expect(d.object(forKey: LogPurchaseIntent.lastTapAtKey) != nil)
    }

    @Test func aNormalRawTextIsNeverCleared() {
        let d = settleDefaults()
        d.set(rawText("Seven Seeds"), forKey: LogPurchaseIntent.lastTapKey)
        d.set(Date.now, forKey: LogPurchaseIntent.lastTapAtKey)
        #expect(!ApplePayStatus.settleTestTap(hasRealTap: false, defaults: d))
        #expect(d.object(forKey: LogPurchaseIntent.lastTapAtKey) != nil)
    }

    // MARK: accessibility and the Learn more URL

    @Test func learnMoreURLIsTheSupportPage() {
        #expect(ApplePayStatus.learnMoreURL.absoluteString == "https://sortd.page/support#apple-pay")
    }

    @Test func tapLoggedAccessibilityLabelHasTheShopAndTheSpokenAmount() {
        let status = ApplePayStatus.tapLogged(date: tapped, merchant: "Seven Seeds", amount: Decimal(string: "4.50")!, currency: "AUD")
        let label = status.accessibilityLabel
        #expect(label.contains("Seven Seeds"))
        #expect(label.contains(Money.spoken(Decimal(string: "4.50")!, "AUD")))
    }

    @Test func notConnectedAndShortcutReachedHaveNonEmptyLabels() {
        #expect(!ApplePayStatus.notConnected.accessibilityLabel.isEmpty)
        #expect(!ApplePayStatus.shortcutReached(reached).accessibilityLabel.isEmpty)
    }
}

/// `LogWalletTapIntent.handle` feeding `ApplePayStatus`, end to end.
@MainActor
struct ApplePayStatusIntentTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "status-intent-\(UUID().uuidString)")!) }

    /// A ▶ run in Shortcuts: nothing saved, but "reached" is now real.
    @Test func aBareRunGivesShortcutReachedNotTapLogged() async throws {
        let ctx = try store()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let r = try await LogWalletTapIntent.handle(nil, in: ctx, book: book(), now: now)
        #expect(r.transaction == nil)
        let status = ApplePayStatus.resolve(lastReachedAt: now, taps: try ctx.fetch(FetchDescriptor<Transaction>()))
        #expect(status == .shortcutReached(now))
    }

    /// The Wallet automation's own text layout logs a real tap.
    @Test func walletTextGivesTapLogged() async throws {
        let ctx = try store()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let r = try await LogWalletTapIntent.handle("Seven Seeds A$4.50 NAB Visa Debit", in: ctx, book: book(), now: now)
        let t = try #require(r.transaction)
        let status = ApplePayStatus.resolve(lastReachedAt: now, taps: try ctx.fetch(FetchDescriptor<Transaction>()))
        #expect(status == .tapLogged(date: t.date, merchant: "Seven Seeds", amount: Decimal(string: "4.50")!, currency: "AUD"))
    }
}
