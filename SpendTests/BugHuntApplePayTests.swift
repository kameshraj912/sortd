import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt 3 Oct 2026, area onboarding-and-applepay. Each case failed on
/// the code the hunt ran on; fixed on `fix-hunt-b`, they are regression
/// tests now (docs/BugHunt-2026-10-03-fixes-b.md).
/// Every call goes through the real intent path (`LogWalletTapIntent.handle`)
/// with a pinned `now:`, on an in-memory store and its own card book.
@MainActor
struct BugHuntApplePayTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "hunt-applepay-\(UUID().uuidString)")!) }
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

    /// The Notification trigger: Wallet's notification (Title = card,
    /// Subtitle = shop, Body = amount), tap fields blank.
    @discardableResult
    private func notified(_ title: String, _ subtitle: String, _ body: String,
                          at seconds: TimeInterval, ctx: ModelContext, book: CardBook) async throws -> LogPurchaseIntent.Outcome {
        try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                            notificationTitle: title, notificationSubtitle: subtitle, notificationBody: body,
                                            in: ctx, book: book, now: now.addingTimeInterval(seconds))
    }

    // MARK: - One refund, two triggers

    /// A partial refund at the till fires both the tap trigger and Wallet's
    /// refund notification, and each one takes the refund off again, so a
    /// A$20 refund lowers a A$45 purchase to A$5.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a till refund is applied twice: once by the tap, once by its Wallet notification"))
    func aTillRefundAndItsNotificationTakeTheRefundOffOnce() async throws {
        let ctx = store(), b = book()
        try await tap("Coles", "A$45.00", at: -86_400, ctx: ctx, book: b)
        try await tap("Coles", "-A$20.00", at: 0, ctx: ctx, book: b)
        try await notified("NAB Visa Debit", "Coles", "Refund A$20.00", at: 3, ctx: ctx, book: b)
        let purchase = try #require(try rows(ctx).first { !$0.refunded })
        #expect(purchase.amount == Decimal(string: "25.00"), "a A$20 refund on A$45 must leave A$25, not \(purchase.amount)")
    }

    // MARK: - Two purchases of one amount at two shops

    /// An online payment's notification row is taken over by a tap at a
    /// different shop for the same amount minutes later: the DoorDash row is
    /// renamed to the cafe and one purchase is gone.
    @Test(.bug("absorbNotificationRow matches on amount and card only, so a different shop's tap swallows an online payment"))
    func anOnlinePaymentIsNotSwallowedByALaterTapAtAnotherShop() async throws {
        let ctx = store(), b = book()
        try await notified("NAB Visa Debit", "DoorDash", "A$15.00", at: 0, ctx: ctx, book: b)
        try await tap("Seven Seeds", "A$15.00", at: 300, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 2, "two purchases at two shops must be two rows")
        #expect(all.contains { $0.rawMerchant == "DoorDash" })
        #expect(all.contains { $0.rawMerchant == "Seven Seeds" })
    }

    /// A till tap whose own notification never came (blank or missed) takes
    /// in a later online payment of the same amount at another shop.
    @Test(.bug("mergeNotification's tap match ignores the shop, so an online payment folds into an earlier tap"))
    func aLaterOnlinePaymentIsNotFoldedIntoATapAtAnotherShop() async throws {
        let ctx = store(), b = book()
        try await tap("Seven Seeds", "A$15.00", at: 0, ctx: ctx, book: b)
        try await notified("NAB Visa Debit", "DoorDash", "A$15.00", at: 300, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 2, "two purchases at two shops must be two rows")
        #expect(all.contains { $0.rawMerchant == "DoorDash" })
    }

    // MARK: - Wallet notifications that are not spending

    /// Money coming in (Apple Cash "You received $25.00 from …") is logged
    /// as a purchase at the sender's name.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a Wallet notification for money received is logged as spending"))
    func moneyReceivedIsNotLoggedAsSpending() async throws {
        let ctx = store(), b = book()
        let r = try await notified("Apple Cash", "", "You received $25.00 from John Appleseed", at: 0, ctx: ctx, book: b)
        #expect(r.transaction == nil, "money received is not a purchase, got \(r.message)")
        #expect(try rows(ctx).isEmpty)
    }

    // MARK: - Reading the notification

    /// A shop name with a joining word in it ("on") is cut at that word on
    /// a notification run, so "Cafe on Collins" is saved as "Cafe".
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("notification shop line is split on connector words even with no amount on it"))
    func aShopNameWithAJoiningWordIsKeptWhole() async throws {
        let ctx = store(), b = book()
        let r = try await notified("NAB Visa Debit", "Cafe on Collins", "A$12.00", at: 0, ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "Cafe on Collins")
    }

    /// A three-letter ISO code at the end of an upper-case shop word, before
    /// a store number ("PANTRY 24" → "TRY 24"), is read as the amount, so a
    /// A$12.50 purchase is saved as 24 Turkish lira at "THE PAN".
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("WalletTapText.money matches a currency code inside a word (no left word boundary)"))
    func aCurrencyCodeInsideAShopWordIsNotTheAmount() async throws {
        let ctx = store(), b = book()
        let r = try await notified("NAB Visa Debit", "THE PANTRY 24", "A$12.50", at: 0, ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.amount == Decimal(string: "12.50"))
        #expect(t.currencyCode == "AUD")
        #expect(t.rawMerchant == "THE PANTRY 24")
    }

    // MARK: - Check the Shortcut

    /// "Check the Shortcut" sends "Sortd Check A$0.01 Test Card"; its row
    /// is hidden, but the card is saved to the person's card list for good.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("the Apple Pay health check saves a 'Test Card' card"))
    func theHealthCheckDoesNotSaveATestCard() async throws {
        let ctx = store(), b = book()
        _ = try await LogWalletTapIntent.handle(ApplePayHealthCheck.payloadText, in: ctx, book: b, now: now)
        #expect(b.cards.isEmpty, "health check left a card: \(b.cards.map(\.name))")
    }

    // MARK: - Tap queue

    /// When the save fails and the queue file can't be written either
    /// (disk full), the tap is gone but Shortcuts is told it was saved.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("TapQueue.write failure is swallowed; saveForLater still says 'Saved for later'"))
    func aTapThatCouldNotBeQueuedIsNotReportedAsSaved() async throws {
        let ctx = store(), b = book()
        let badURL = FileManager.default.temporaryDirectory
            .appending(path: "no-such-dir-\(UUID().uuidString)")
            .appending(path: TapQueue.fileName)
        let r = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$5.50", card: "NAB Visa Debit",
                                                   in: ctx, book: b, now: now, debugForceSaveFailure: true,
                                                   queueURL: badURL)
        let queued = TapQueue.read(from: badURL)
        #expect(queued.count == 1 || !r.message.hasPrefix("Saved for later"),
                "nothing was queued, yet the run said: \(r.message)")
    }

    // MARK: - Regression guards for the fixes above

    /// The same shop spelled two ways still pairs a tap with its online
    /// notification (the shop check P2/P3 added must not split them).
    @Test func theSameShopSpelledTwoWaysStillPairs() async throws {
        let ctx = store(), b = book()
        try await notified("NAB Visa Debit", "SQ *SEVEN SEEDS CARLTON", "A$15.00", at: 0, ctx: ctx, book: b)
        try await tap("Seven Seeds", "A$15.00", at: 300, ctx: ctx, book: b)
        #expect(try rows(ctx).count == 1)
    }
}
