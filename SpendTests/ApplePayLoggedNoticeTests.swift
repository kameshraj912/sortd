import Testing
import Foundation
import SwiftData
@testable import Spend

/// Sortd's own "Logged" notification (2 Oct 2026), which replaces the
/// Shortcuts dialog now that the shortcut runs with "Show When Run" off.
/// The decision is pure (`LoggedNotice.saved` + `LoggedNotice.content`);
/// runs go through the real intent path with a pinned `now:`.
@MainActor
struct ApplePayLoggedNoticeTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "notice-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func notice(_ outcome: LogPurchaseIntent.Outcome) -> LoggedNotice.Content? {
        LoggedNotice.content(for: LoggedNotice.saved(from: outcome), settingOn: true, authorized: true)
    }

    // MARK: - The words

    @Test func aLoggedPurchaseSaysTheAmountAndShop() async throws {
        let ctx = store()
        let r = try await LogWalletTapIntent.handle(nil, amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                                    in: ctx, book: book(), now: now)
        let t = try #require(r.transaction)
        let content = try #require(notice(r))
        #expect(content.title == "Logged")
        #expect(content.body == "\(Money.format(Decimal(string: "5.50")!, "AUD")) at Seven Seeds")
        #expect(content.id == "logged-\(t.id.uuidString)")
    }

    @Test func aRowWithNoShopNeedsACheck() throws {
        let id = UUID()
        let content = try #require(LoggedNotice.content(for: .needsCheck(id: id, missingShop: true, missingAmount: false),
                                                        settingOn: true, authorized: true))
        #expect(content.title == "Needs a check")
        #expect(content.body == "A purchase came in without a shop. Tap to fix.")
        #expect(content.id == "logged-\(id.uuidString)")
    }

    @Test func aRowWithNoAmountSaysSo() throws {
        let content = try #require(LoggedNotice.content(for: .needsCheck(id: UUID(), missingShop: false, missingAmount: true),
                                                        settingOn: true, authorized: true))
        #expect(content.body == "A purchase came in without an amount. Tap to fix.")
    }

    /// A notification with an amount and a card but no shop is saved as a
    /// needs-a-check row, and the notice says so.
    @Test func aNotificationWithNoShopNeedsACheck() async throws {
        let r = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                                    notificationTitle: "NAB Visa Debit", notificationSubtitle: "",
                                                    notificationBody: "A$23.40", in: store(), book: book(), now: now)
        #expect(r.transaction != nil)
        #expect(notice(r)?.title == "Needs a check")
        #expect(notice(r)?.body == "A purchase came in without a shop. Tap to fix.")
    }

    // MARK: - Setting and permission

    @Test func nothingWhenTheSettingIsOffOrNotAllowed() {
        let saved = LoggedNotice.Saved.purchase(id: UUID(), amount: 5.5, currency: "AUD", merchant: "Seven Seeds")
        #expect(LoggedNotice.content(for: saved, settingOn: true, authorized: true) != nil)
        #expect(LoggedNotice.content(for: saved, settingOn: false, authorized: true) == nil)
        #expect(LoggedNotice.content(for: saved, settingOn: true, authorized: false) == nil)
        #expect(LoggedNotice.content(for: nil, settingOn: true, authorized: true) == nil)
    }

    @Test func theSettingIsOnByDefault() {
        let defaults = UserDefaults(suiteName: "notice-setting-\(UUID().uuidString)")!
        #expect(LoggedNotice.isOn(defaults))
        defaults.set(false, forKey: LoggedNotice.enabledKey)
        #expect(!LoggedNotice.isOn(defaults))
    }

    @Test func tappingItOpensActivity() {
        #expect(LoggedNotice.url == "sortd://activity")
    }

    // MARK: - One purchase, one notice

    /// The tap and Wallet's notification for one purchase merge into one
    /// row: both notices carry its identifier, so the second replaces the first.
    @Test func aMergeKeepsTheSameIdentifier() async throws {
        let ctx = store(), b = book()
        let tap = try await LogWalletTapIntent.handle(nil, amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                                      in: ctx, book: b, now: now)
        let note = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                                       notificationTitle: "NAB Visa Debit", notificationSubtitle: "Seven Seeds",
                                                       notificationBody: "A$5.50", in: ctx, book: b, now: now.addingTimeInterval(4))
        #expect(note.merged)
        let first = try #require(notice(tap)), second = try #require(notice(note))
        #expect(first.id == second.id)
        #expect(second.title == "Logged")
    }

    // MARK: - A ▶ test run (5 Oct 2026)

    /// "Show When Run" is off, so without this a ▶ run looked like nothing happened.
    @Test func aPlayButtonRunBeforeAnyTapSaysConnected() async throws {
        let r = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "", in: store(), book: book(), now: now)
        #expect(r.transaction == nil)
        let content = try #require(notice(r))
        #expect(content.title == "Shortcut connected")
        #expect(content.body == "The shortcut reached Sortd, but no payment came with it. Pay with Apple Pay in a shop to log one.")
        #expect(LoggedNotice.link(for: .reached) == "sortd://home")
    }

    /// Once a real tap has been logged, a blank run (a ▶ run, or a blank
    /// companion of a real purchase) stays silent.
    @Test func aPlayButtonRunAfterARealTapSaysNothing() async throws {
        let ctx = store(), b = book()
        _ = try await LogWalletTapIntent.handle(nil, amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                                in: ctx, book: b, now: now)
        let r = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "", in: ctx, book: b,
                                                    now: now.addingTimeInterval(600))
        #expect(r.transaction == nil)
        #expect(notice(r) == nil)
    }

    @Test func theConnectedNoticeFollowsTheSettingAndPermission() {
        #expect(LoggedNotice.content(for: .reached, settingOn: false, authorized: true) == nil)
        #expect(LoggedNotice.content(for: .reached, settingOn: true, authorized: false) == nil)
    }

    // MARK: - Nothing posted

    @Test func nothingForADeclinedPayment() async throws {
        let r = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                                    notificationTitle: "Payment declined", notificationSubtitle: "DoorDash",
                                                    notificationBody: "A$23.40", in: store(), book: book(), now: now)
        #expect(notice(r) == nil)
    }

    @Test func nothingForANotificationWithNoAmount() async throws {
        let r = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                                    notificationTitle: "Qantas", notificationSubtitle: "Boarding pass",
                                                    notificationBody: "Your flight QF1 boards at 10:40", in: store(),
                                                    book: book(), now: now)
        #expect(notice(r) == nil)
    }

    @Test func nothingForARefund() async throws {
        let r = try await LogWalletTapIntent.handle(nil, amount: "-A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                                    in: store(), book: book(), now: now)
        #expect(r.refund)
        #expect(notice(r) == nil)
    }

    /// Built by hand, not through `handle`: a forced save failure queues to
    /// the real tap-queue file, which other suites share.
    @Test func nothingWhenTheSaveFailedOrForATestRow() {
        let t = Transaction(date: now, merchant: "Seven Seeds", amount: 5.5, currencyCode: "AUD", card: .other,
                            category: .eatingOut, source: .tap)
        #expect(notice(.init(message: "", transaction: t, merged: false)) != nil)
        #expect(notice(.init(message: "", transaction: t, merged: false, saveFailed: true)) == nil)
        let test = Transaction(date: now, merchant: LogPurchaseIntent.legacyTestMerchant, amount: 1, currencyCode: "AUD",
                               card: .other, category: .other, source: .tap)
        #expect(notice(.init(message: "", transaction: test, merged: false)) == nil)
    }
}
