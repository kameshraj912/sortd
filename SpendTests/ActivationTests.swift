import Testing
import Foundation
import SwiftData
@testable import Spend

/// Overhaul sub-spec 6: the aha moment. "The aha is the first `Transaction`
/// whose `seenIn` contains `.tap` or `.email`. It must not be sample data
/// (`DemoData`) and must not be a legacy Send a Test Tap purchase
/// (`LogPurchaseIntent.legacyTestMerchant`)."
///
/// Adapted to the real names read in `Spend/Models/Transaction.swift` and
/// `Spend/Services/DemoData.swift`:
///
///     enum Activation {
///         enum Source: String { case tap, email }
///         static func detect(_ t: Transaction) -> Source?
///         static func recordIfFirst(_ t: Transaction, defaults: UserDefaults) -> Source?
///         static func shouldAskForNotifications(defaults: UserDefaults) -> Bool
///         static func markNotificationAsked(defaults: UserDefaults)
///     }
///
/// DemoData rows are marked by `note == DemoData.marker` ("Sample purchase"),
/// set on every row `DemoData.load` inserts -- there is no separate
/// `Transaction.isDemo`/`isSample` flag, so `detect` must check
/// `t.note == DemoData.marker`, not a new field.
///
/// The "Send a Test Tap" button (`Spend/Views/Components/TapTestButton.swift`)
/// was removed 25 Sep 2026 (`docs/specs/2026-09-25-apple-pay-page.md`). Its
/// merchant name lives on as `LogPurchaseIntent.legacyTestMerchant` ("Sortd
/// Test"), kept only so purchases already in people's stores stay excluded.
@MainActor
struct ActivationTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func log(_ merchant: String, source: TxnSource, note: String = "") throws -> Transaction {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000), merchant: merchant,
                                 amount: 12.5, currency: "AUD", card: .other, source: source, note: note)
        return try TransactionLogger.log(p, in: context).transaction
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ActivationTests-\(UUID().uuidString)")!
    }

    // MARK: detect

    @Test func manualPurchaseIsNotActivation() throws {
        let t = try log("Woolworths", source: .manual)
        #expect(Activation.detect(t) == nil)
    }

    @Test func tapPurchaseIsTapActivation() throws {
        let t = try log("Starbucks", source: .tap)
        #expect(Activation.detect(t) == .tap)
    }

    @Test func emailPurchaseIsEmailActivation() throws {
        let t = try log("Netflix", source: .email)
        #expect(Activation.detect(t) == .email)
    }

    /// Sample data logged through `.tap` in DemoData's own rows would be
    /// marked with `DemoData.marker`; a demo row must never count as the aha.
    @Test func sampleTapPurchaseIsNotActivation() throws {
        let t = try log("Uber", source: .tap, note: DemoData.marker)
        #expect(Activation.detect(t) == nil)
    }

    /// The Send a Test Tap button proves Sortd's half only; it must not
    /// count as the aha (spec: "milestone, not the aha"). The button is
    /// gone, but old rows under its merchant name must stay excluded.
    @Test func testTapMerchantIsNotActivation() throws {
        let t = try log(LogPurchaseIntent.legacyTestMerchant, source: .tap)
        #expect(Activation.detect(t) == nil)
    }

    // MARK: recordIfFirst -- once only per install

    @Test func recordIfFirstReturnsTheSourceOnceThenNilAfter() throws {
        let d = defaults()
        let first = try log("Starbucks", source: .tap)
        let second = try log("Uber", source: .tap)

        #expect(Activation.recordIfFirst(first, defaults: d) == .tap)
        #expect(Activation.recordIfFirst(second, defaults: d) == nil)
    }

    @Test func recordIfFirstIgnoresNonQualifyingPurchases() throws {
        let d = defaults()
        let manual = try log("Coles", source: .manual)
        #expect(Activation.recordIfFirst(manual, defaults: d) == nil)

        let tap = try log("Starbucks", source: .tap)
        #expect(Activation.recordIfFirst(tap, defaults: d) == .tap)
    }

    // MARK: The single notification ask, after the aha

    @Test func notificationAskIsFalseBeforeAnyActivation() {
        let d = defaults()
        #expect(!Activation.shouldAskForNotifications(defaults: d))
    }

    @Test func notificationAskIsTrueOnceAfterActivationThenFalseOnceDeclined() throws {
        let d = defaults()
        let tap = try log("Starbucks", source: .tap)
        _ = Activation.recordIfFirst(tap, defaults: d)

        #expect(Activation.shouldAskForNotifications(defaults: d))

        Activation.markNotificationAsked(defaults: d)

        #expect(!Activation.shouldAskForNotifications(defaults: d))
    }

    // MARK: The save hook only looks at rows made in this launch

    /// A restore (iCloud or file) keeps each row's original `createdAt`
    /// (Backup.swift), so a restored tap row is older than this launch and
    /// must not count as the aha.
    @Test func aRestoredTapRowDoesNotActivate() throws {
        let d = defaults()
        let launch = Date.now
        let restored = try log("Starbucks", source: .tap)
        restored.createdAt = launch.addingTimeInterval(-3600)
        #expect(Activation.check(inserted: [restored], since: launch, defaults: d) == nil)
        #expect(!Activation.shouldAskForNotifications(defaults: d))
    }

    @Test func anInsertedTapRowCreatedNowActivates() throws {
        let d = defaults()
        let launch = Date.now.addingTimeInterval(-60)
        let tap = try log("Starbucks", source: .tap)
        #expect(Activation.check(inserted: [tap], since: launch, defaults: d) == .tap)
    }

    /// An edit or a delete saves the store with nothing inserted: nothing
    /// to look at, nothing recorded.
    @Test func anUpdateOnlySaveDoesNothing() throws {
        let d = defaults()
        _ = try log("Starbucks", source: .tap)
        #expect(Activation.check(inserted: [], since: .distantPast, defaults: d) == nil)
        #expect(!d.bool(forKey: Activation.seenKey))
    }

    // MARK: Existing installs

    /// An install that finished setup before Activation existed has already
    /// been asked about notifications (the old check-in step) and may hold
    /// tap rows for weeks: it never gets the card or a second ask.
    @Test func anInstallWithSetupFinishedBeforeActivationExistedNeverGetsTheCard() throws {
        let d = defaults()
        d.set(true, forKey: OnboardingView.doneKey)
        Activation.settleExistingInstall(setupDone: d.bool(forKey: OnboardingView.doneKey), defaults: d)

        let tap = try log("Starbucks", source: .tap)
        #expect(Activation.recordIfFirst(tap, defaults: d) == nil)
        #expect(!Activation.shouldAskForNotifications(defaults: d))
    }

    /// A fresh install: settling at first launch (setup not done) and again
    /// at the next launch (setup done by then) leaves the aha open.
    @Test func aFreshInstallStillGetsTheCardAfterSetup() throws {
        let d = defaults()
        Activation.settleExistingInstall(setupDone: false, defaults: d)
        Activation.settleExistingInstall(setupDone: true, defaults: d)

        let tap = try log("Starbucks", source: .tap)
        #expect(Activation.recordIfFirst(tap, defaults: d) == .tap)
        #expect(Activation.shouldAskForNotifications(defaults: d))
    }
}

// Device-only and UI-level cases (a real Apple Pay tap, a Gmail import, "0
// permission requests" from a fake notification centre while only tapping
// Continue, VoiceOver on the aha card, Reduce Motion) belong to `ui-driver`
// and are not written here.
