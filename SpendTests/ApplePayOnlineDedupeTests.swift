import Testing
import Foundation
import SwiftData
@testable import Spend

/// One purchase, two triggers (2 Oct 2026). At a till the Wallet tap trigger
/// ("t") and the Notification trigger ("n") both fire; online only "n" does.
/// `Transaction.tapOrigins` records which of the two a row has seen. Every
/// call pins `now:`.
@MainActor
struct ApplePayOnlineDedupeTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "online-dedupe-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func rows(_ ctx: ModelContext) throws -> [Transaction] {
        try ctx.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)]))
    }

    /// The Wallet tap trigger: Amount, Merchant and Card straight from the tap.
    @discardableResult
    private func tap(_ merchant: String, _ amount: String, card: String = "NAB Visa Debit",
                     at seconds: TimeInterval, ctx: ModelContext, book: CardBook) async throws -> LogPurchaseIntent.Outcome {
        try await LogWalletTapIntent.handle(nil, amount: amount, merchant: merchant, card: card,
                                            in: ctx, book: book, now: now.addingTimeInterval(seconds))
    }

    /// The Notification trigger: Wallet's notification, tap fields blank.
    @discardableResult
    private func notified(_ shop: String, _ amount: String, card: String = "NAB Visa Debit",
                          at seconds: TimeInterval, ctx: ModelContext, book: CardBook) async throws -> LogPurchaseIntent.Outcome {
        try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                            notificationTitle: card, notificationSubtitle: shop, notificationBody: amount,
                                            in: ctx, book: book, now: now.addingTimeInterval(seconds))
    }

    // MARK: - One purchase at a till

    @Test func tapThenNotificationIsOneRow() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        let n = try await notified("Seven Seeds", "A$5.50", at: 4, ctx: ctx, book: b)
        #expect(n.merged)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "tn")
        #expect(all.first?.rawMerchant == "Seven Seeds")
    }

    /// The notification lands first; the tap absorbs it, and the tap's shop
    /// and card win.
    @Test func notificationThenTapIsOneRowAndTheTapWins() async throws {
        let ctx = store(), b = book()
        try await notified("SQ *SEVEN SEEDS", "A$5.50", card: "", at: 0, ctx: ctx, book: b)
        let t = try await tap("Seven Seeds", "A$5.50", at: 3, ctx: ctx, book: b)
        #expect(t.merged)
        let all = try rows(ctx)
        #expect(all.count == 1)
        let row = try #require(all.first)
        #expect(row.tapOrigins == "tn")
        #expect(row.rawMerchant == "Seven Seeds")
        #expect(b.info(row.card)?.name == "NAB Visa Debit")
        #expect(!row.needsCheck)
    }

    /// A different spelling of the shop on the notification still merges on
    /// amount, card and time.
    @Test func aDifferentShopSpellingStillMerges() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        try await notified("SQ *SEVEN SEEDS CARLTON", "A$5.50", at: 6, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.rawMerchant == "Seven Seeds")
    }

    /// A row logged before this build has no `tapOrigins`; it is a tap row.
    @Test func anOldTapRowWithNoOriginsTakesTheNotification() async throws {
        let ctx = store(), b = book()
        let old = try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        old.transaction?.tapOrigins = nil
        try ctx.save()
        try await notified("Seven Seeds", "A$5.50", at: 5, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "tn")
    }

    // MARK: - Two real coffees two minutes apart, both triggers each

    enum Step: String, Sendable { case t1, n1, t2, n2 }

    static let plausibleOrders: [[Step]] = [
        [.t1, .n1, .t2, .n2],
        [.n1, .t1, .n2, .t2],
        [.t1, .n1, .n2, .t2],
        [.n1, .t1, .t2, .n2],
        [.t1, .t2, .n1, .n2],
        [.n1, .n2, .t1, .t2],
    ]

    @Test(arguments: plausibleOrders)
    func twoCoffeesTwoMinutesApartAreTwoRows(order: [Step]) async throws {
        let ctx = store(), b = book()
        // The second coffee is paid 2 minutes after the first. Each event
        // arrives a couple of seconds after the one before it.
        let base: [Step: TimeInterval] = [.t1: 0, .n1: 0, .t2: 120, .n2: 120]
        for (i, step) in order.enumerated() {
            let at = base[step]! + TimeInterval(i * 2)
            switch step {
            case .t1, .t2: try await tap("Seven Seeds", "A$5.50", at: at, ctx: ctx, book: b)
            case .n1, .n2: try await notified("Seven Seeds", "A$5.50", at: at, ctx: ctx, book: b)
            }
        }
        let all = try rows(ctx)
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.tapOrigins == "tn" })
        #expect(all.allSatisfy { !$0.needsCheck })
    }

    // MARK: - Online purchases

    @Test func anOnlinePurchaseIsOneNotificationRow() async throws {
        let ctx = store(), b = book()
        let r = try await notified("DoorDash", "A$23.40", at: 0, ctx: ctx, book: b)
        #expect(!r.merged)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "n")
        #expect(all.first?.source == .tap)
    }

    @Test func twoOnlinePurchasesOfOneAmountAtTwoShopsAreTwoRows() async throws {
        let ctx = store(), b = book()
        try await notified("DoorDash", "A$15.00", at: 0, ctx: ctx, book: b)
        try await notified("Uber Eats", "A$15.00", at: 30, ctx: ctx, book: b)
        #expect(try rows(ctx).count == 2)
    }

    @Test func twoOnlinePurchasesAtOneShopMoreThanAMinuteApartAreTwoRows() async throws {
        let ctx = store(), b = book()
        try await notified("DoorDash", "A$15.00", at: 0, ctx: ctx, book: b)
        try await notified("DoorDash", "A$15.00", at: 90, ctx: ctx, book: b)
        #expect(try rows(ctx).count == 2)
    }

    /// The same notification twice within a minute is one purchase.
    @Test func theSameOnlinePurchaseNotifiedTwiceWithinAMinuteIsOneRow() async throws {
        let ctx = store(), b = book()
        try await notified("DoorDash", "A$15.00", at: 0, ctx: ctx, book: b)
        let second = try await notified("DoorDash", "A$15.00", at: 30, ctx: ctx, book: b)
        #expect(second.merged)
        #expect(try rows(ctx).count == 1)
    }

    /// A tap and its notification, then Wallet notifies a second time.
    @Test func aRepeatNotificationForATillPurchaseIsStillOneRow() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        try await notified("Seven Seeds", "A$5.50", at: 3, ctx: ctx, book: b)
        try await notified("Seven Seeds", "A$5.50", at: 20, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "tn")
    }

    // MARK: - The 10-minute window

    @Test func aNotificationNineMinutesAfterItsTapMerges() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        try await notified("Seven Seeds", "A$5.50", at: 9 * 60, ctx: ctx, book: b)
        #expect(try rows(ctx).count == 1)
    }

    @Test func aNotificationElevenMinutesAfterItsTapIsItsOwnRow() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        try await notified("Seven Seeds", "A$5.50", at: 11 * 60, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 2)
        #expect(all.map(\.tapOrigins) == ["t", "n"])
    }

    @Test func aTapNineMinutesAfterANotificationMerges() async throws {
        let ctx = store(), b = book()
        try await notified("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        try await tap("Seven Seeds", "A$5.50", at: 9 * 60, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "tn")
    }

    // MARK: - Cards

    /// The notification does not name the card: it still merges, and the
    /// row keeps the tap's card.
    @Test func aNotificationWithNoCardMergesIntoTheTap() async throws {
        let ctx = store(), b = book()
        let t = try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        let card = try #require(t.transaction?.card)
        try await notified("Seven Seeds", "A$5.50", card: "", at: 5, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.card == card)
        #expect(b.cards.count == 1)
    }

    /// Two different known cards are two purchases.
    @Test func aDifferentKnownCardDoesNotMerge() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", card: "NAB Visa Debit", at: 0, ctx: ctx, book: b)
        try await tap("Coles", "A$1.00", card: "CommBank Debit", at: -3600, ctx: ctx, book: b)
        try await notified("Seven Seeds", "A$5.50", card: "CommBank Debit", at: 5, ctx: ctx, book: b)
        #expect(try rows(ctx).count == 3)
    }

    /// The tap had no card; the notification fills it in.
    @Test func theNotificationFillsAMissingCard() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", card: "", at: 0, ctx: ctx, book: b)
        try await notified("Seven Seeds", "A$5.50", card: "NAB Visa Debit", at: 5, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(b.info(all[0].card)?.name == "NAB Visa Debit")
    }

    // MARK: - Filling blanks

    /// The tap had no shop; the notification fills it in and the
    /// needs-a-check tag goes.
    @Test func theNotificationFillsAMissingShop() async throws {
        let ctx = store(), b = book()
        let t = try await tap("", "A$5.50", at: 0, ctx: ctx, book: b)
        #expect(t.transaction?.needsCheck == true)
        try await notified("Seven Seeds", "A$5.50", at: 5, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all[0].rawMerchant == "Seven Seeds")
        #expect(!all[0].needsCheck)
        #expect(Activation.detect(all[0]) == .tap)
        #expect(ApplePayStatus.resolve(lastReachedAt: now, taps: all, now: now)
                == .tapLogged(date: all[0].date, merchant: all[0].merchant, amount: all[0].amount, currency: "AUD"))
    }

    /// The tap had no amount; the notification brings it.
    @Test func theNotificationFillsAMissingAmount() async throws {
        let ctx = store(), b = book()
        let t = try await tap("Seven Seeds", "", at: 0, ctx: ctx, book: b)
        #expect(t.transaction?.needsCheck == true)
        try await notified("Seven Seeds", "A$5.50", at: 8, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all[0].amount == Decimal(string: "5.50"))
        #expect(!all[0].needsCheck)
        #expect(all[0].tapOrigins == "tn")
    }

    /// The notification had no shop ("Unknown merchant", flagged); the tap
    /// brings the shop and the flag goes.
    @Test func theTapFillsANotificationRowWithNoShop() async throws {
        let ctx = store(), b = book()
        let n = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                                    notificationTitle: "NAB Visa Debit", notificationSubtitle: "",
                                                    notificationBody: "A$5.50", in: ctx, book: b, now: now)
        #expect(n.transaction?.needsCheck == true)
        try await tap("Seven Seeds", "A$5.50", at: 4, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all[0].rawMerchant == "Seven Seeds")
        #expect(!all[0].needsCheck)
    }

    // MARK: - Things that must not merge

    /// A different amount is a different purchase, even seconds apart.
    @Test func aDifferentAmountNeverMerges() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        try await notified("Seven Seeds", "A$6.00", at: 5, ctx: ctx, book: b)
        #expect(try rows(ctx).count == 2)
    }

    /// Two taps two minutes apart with no notifications stay two rows,
    /// exactly as before this change.
    @Test func twoTapsAloneKeepTodaysRules() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$5.50", at: 0, ctx: ctx, book: b)
        try await tap("Seven Seeds", "A$5.50", at: 120, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.tapOrigins == "t" })
    }
}
