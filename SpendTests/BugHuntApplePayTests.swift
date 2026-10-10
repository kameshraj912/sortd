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
    @Test(.bug("a till refund is applied twice: once by the tap, once by its Wallet notification"))
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
    @Test(.bug("a Wallet notification for money received is logged as spending"))
    func moneyReceivedIsNotLoggedAsSpending() async throws {
        let ctx = store(), b = book()
        let r = try await notified("Apple Cash", "", "You received $25.00 from John Appleseed", at: 0, ctx: ctx, book: b)
        #expect(r.transaction == nil, "money received is not a purchase, got \(r.message)")
        #expect(try rows(ctx).isEmpty)
    }

    // MARK: - Reading the notification

    /// A shop name with a joining word in it ("on") is cut at that word on
    /// a notification run, so "Cafe on Collins" is saved as "Cafe".
    @Test(.bug("notification shop line is split on connector words even with no amount on it"))
    func aShopNameWithAJoiningWordIsKeptWhole() async throws {
        let ctx = store(), b = book()
        let r = try await notified("NAB Visa Debit", "Cafe on Collins", "A$12.00", at: 0, ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "Cafe on Collins")
    }

    /// A three-letter ISO code at the end of an upper-case shop word, before
    /// a store number ("PANTRY 24" → "TRY 24"), is read as the amount, so a
    /// A$12.50 purchase is saved as 24 Turkish lira at "THE PAN".
    @Test(.bug("WalletTapText.money matches a currency code inside a word (no left word boundary)"))
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
    @Test(.bug("the Apple Pay health check saves a 'Test Card' card"))
    func theHealthCheckDoesNotSaveATestCard() async throws {
        let ctx = store(), b = book()
        _ = try await LogWalletTapIntent.handle(ApplePayHealthCheck.payloadText, in: ctx, book: b, now: now)
        #expect(b.cards.isEmpty, "health check left a card: \(b.cards.map(\.name))")
    }

    // MARK: - Tap queue

    /// When the save fails and the queue file can't be written either
    /// (disk full), the tap is gone but Shortcuts is told it was saved.
    @Test(.bug("TapQueue.write failure is swallowed; saveForLater still says 'Saved for later'"))
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
        #expect(r.message == TapQueue.notSavedMessage)
    }

    // MARK: - Regression guards for the fixes above

    /// P1's guard must not swallow a real second refund: two A$20 refunds
    /// reported by the same trigger are two refunds.
    @Test func twoRefundsFromOneTriggerBothCount() async throws {
        let ctx = store(), b = book()
        try await tap("Coles", "A$45.00", at: -86_400, ctx: ctx, book: b)
        try await tap("Coles", "-A$20.00", at: 0, ctx: ctx, book: b)
        try await tap("Coles", "-A$20.00", at: 60, ctx: ctx, book: b)
        let purchase = try #require(try rows(ctx).first { !$0.refunded })
        #expect(purchase.amount == Decimal(string: "5.00"))
    }

    /// A whole refund reported by both triggers marks one of two same-amount
    /// purchases, not both.
    @Test func aWholeRefundAndItsNotificationRefundOnePurchase() async throws {
        let ctx = store(), b = book()
        try await tap("Coles", "A$20.00", at: -2 * 86_400, ctx: ctx, book: b)
        try await tap("Coles", "A$20.00", at: -86_400, ctx: ctx, book: b)
        try await tap("Coles", "-A$20.00", at: 0, ctx: ctx, book: b)
        try await notified("NAB Visa Debit", "Coles", "Refund A$20.00", at: 3, ctx: ctx, book: b)
        let all = try rows(ctx)
        #expect(all.count == 2)
        #expect(all.filter(\.refunded).count == 1)
    }

    /// The same shop spelled two ways still pairs a tap with its online
    /// notification (the shop check P2/P3 added must not split them).
    @Test func theSameShopSpelledTwoWaysStillPairs() async throws {
        let ctx = store(), b = book()
        try await notified("NAB Visa Debit", "SQ *SEVEN SEEDS CARLTON", "A$15.00", at: 0, ctx: ctx, book: b)
        try await tap("Seven Seeds", "A$15.00", at: 300, ctx: ctx, book: b)
        #expect(try rows(ctx).count == 1)
    }

    /// P4 leaves refunds alone: a refund that says "credited" is still a refund.
    @Test func aCreditedRefundIsStillARefund() async throws {
        let ctx = store(), b = book()
        let r = try await notified("NAB Visa Debit", "Coles", "Refund A$20.00 credited", at: 0,
                                   ctx: ctx, book: b)
        #expect(r.refund)
        #expect(try rows(ctx).allSatisfy(\.refunded))
    }

    /// P5: when the first queue file can't be written, the next one takes the tap.
    @Test func aTapGoesToTheSecondQueueFileWhenTheFirstFails() throws {
        let tmp = FileManager.default.temporaryDirectory
        let bad = tmp.appending(path: "no-such-dir-\(UUID().uuidString)").appending(path: TapQueue.fileName)
        let good = tmp.appending(path: "hunt-queue-\(UUID().uuidString).json")
        let entry = TapQueue.Entry(merchant: "Seven Seeds", amount: "A$5.50", card: "NAB Visa Debit", date: now)
        #expect(TapQueue.enqueue(entry, into: [bad, good]))
        #expect(TapQueue.read(from: good) == [entry])
        #expect(!TapQueue.enqueue(entry, into: [bad]))
    }
}

// MARK: - Bug hunt 8 Oct 2026 (onboarding-and-applepay)

/// Bug hunt 8 Oct 2026, area onboarding-and-applepay. Each case fails on
/// `hunt-20261008` and documents an unfixed bug; fixing one means removing
/// its known-bug traits. Same shape as above: the real intent path
/// (`LogWalletTapIntent.handle`), a pinned `now:`, an in-memory store and
/// a card book of its own.
@MainActor
struct BugHuntApplePayHunt1008Tests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "hunt1008-applepay-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 86_400

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

    /// The Notification trigger: Title, Subtitle, Body, tap fields blank.
    @discardableResult
    private func notified(_ title: String, _ subtitle: String, _ body: String, app: String? = nil,
                          at seconds: TimeInterval, ctx: ModelContext, book: CardBook) async throws -> LogPurchaseIntent.Outcome {
        try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                            notificationTitle: title, notificationSubtitle: subtitle, notificationBody: body,
                                            notificationApp: app, in: ctx, book: book, now: now.addingTimeInterval(seconds))
    }

    // MARK: - H1 A shop that starts with a number is dropped as a date

    /// Wallet's shop line "7-ELEVEN 2034" (a chain with its store number,
    /// as Wallet shows unknown merchants) matches `WalletTapText.looksLikeDate`'s
    /// day-month-year shape and is thrown away, so an in-app payment at
    /// 7-Eleven, 99 Ranch or 5 Guys is saved with no shop ("needs a check").
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("looksLikeDate reads a number-word-number shop line (7-ELEVEN 2034) as a date"),
          arguments: ["7-ELEVEN 2034", "99 Ranch 1234", "5 Guys 10"])
    func aShopLineThatStartsWithANumberIsNotADate(shop: String) async throws {
        let ctx = store(), b = book()
        let r = try await notified("NAB Visa Debit", shop, "A$12.50", at: 0, ctx: ctx, book: b)
        let t = try #require(r.transaction, "\(r.message)")
        #expect(t.rawMerchant == shop, "the shop was dropped: saved as \(t.rawMerchant)")
        #expect(!t.needsCheck)
        #expect(t.amount == Decimal(string: "12.50"))
    }

    // MARK: - H2 A refund notice more than a week after the till refund

    /// A till refund is taken off by the tap; the bank's refund notice
    /// arrives 8 days later (refunds post in 5 to 10 business days).
    /// `sameRefund` only looks back `notificationRefundWindow` (7 days), so
    /// the notice is read as a new refund and `Refunds.markRefundedPurchase`
    /// takes the next same-amount purchase at that shop off: a re-purchase
    /// that was never refunded drops out of the total.
    @Test(.bug("a bank refund notice 8 days after the till refund refunds a second, unrefunded purchase"))
    func aRefundNoticeEightDaysLateDoesNotRefundTheRepurchase() async throws {
        let ctx = store(), b = book()
        try await tap("Coles", "A$45.00", at: 0, ctx: ctx, book: b)
        try await tap("Coles", "-A$45.00", at: day, ctx: ctx, book: b)             // the till refund
        let again = try await tap("Coles", "A$45.00", at: 2 * day, ctx: ctx, book: b)
        let second = try #require(again.transaction)
        #expect(!again.merged)
        try await notified("CommBank", "", "Refund of A$45.00 from COLES.", at: 9 * day, ctx: ctx, book: b)
        #expect(!second.refunded, "the bank's late report of the first refund took the re-purchase off")
        #expect(try rows(ctx).filter { !$0.refunded }.count == 1)
    }

    // MARK: - H3 The health check counts as the first auto-logged purchase

    /// "Check the Shortcut" logs a A$0.01 "Sortd Check" row through
    /// `LogPurchaseIntent.handle`, which then fires the once-per-install
    /// `activation_first_auto_purchase` event (`countsAsActivation` only
    /// excludes the legacy "Sortd Test" merchant) and `apple_pay_tap_logged`
    /// (`LogWalletTapIntent.handle`, same check). The person's real first
    /// purchase is then never counted as the activation.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("countsAsActivation treats the health check's 'Sortd Check' row as a real first purchase"))
    func theHealthCheckIsNotTheFirstAutoLoggedPurchase() {
        #expect(!LogPurchaseIntent.countsAsActivation(added: true, merchant: ApplePayHealthCheck.merchant))
    }

    // MARK: - H4 A budget typed after an offline currency change

    /// Home currency changed from AUD to SGD while offline: the A$1,000
    /// budget is left as is (to convert next time), but the budget screen
    /// now shows it as S$1,000 and the person types S$1,200. Back online,
    /// `ensureConverted` still thinks the budget is in AUD and converts the
    /// 1,200 to S$1,320.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a budget edited between an offline currency change and the retry is converted as the old currency"))
    func aBudgetTypedAfterAnOfflineCurrencyChangeIsNotConvertedLater() async throws {
        let ctx = store()
        let d = UserDefaults(suiteName: "hunt1008-fx-\(UUID().uuidString)")!
        d.set("AUD", forKey: FXService.convertedKey)
        d.set("AUD", forKey: Money.homeKey)
        d.set(1000.0, forKey: FXService.budgetKey)

        await FXService.rebase(to: "SGD", in: ctx, defaults: d, rate: { _, _ in throw URLError(.notConnectedToInternet) })
        #expect(d.string(forKey: Money.homeKey) == "SGD")
        #expect(d.double(forKey: FXService.budgetKey) == 1000)
        // The budget step (Run Setup Again) or Settings › Budget shows "S$1,000"; the person types 1200.
        d.set(1200.0, forKey: FXService.budgetKey)

        await FXService.ensureConverted(in: ctx, defaults: d, rate: { _, _ in 1.1 })
        #expect(d.double(forKey: FXService.budgetKey) == 1200,
                "a budget typed in SGD was converted as if it were AUD: \(d.double(forKey: FXService.budgetKey))")
    }

    // MARK: - H5 An unknown card with no card word becomes the shop

    /// Wallet's notification is Title = card, Subtitle = shop, Body = amount.
    /// A card the person has not added, named without a card word or digits
    /// ("Monzo", "Wise", "Up", "Revolut"), is not recognised as a card, so
    /// the parser takes the first leftover line, the title, as the shop:
    /// a £4.50 coffee at Pret is saved at "Monzo".
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a notification title naming an unknown card with no card word is saved as the shop"))
    func anUnknownCardTitleIsNotTheShop() async throws {
        let ctx = store(), b = book()
        b.upsert(CardInfo(name: "NAB Visa Debit", shortName: "NAB", bank: "NAB", walletWords: ["nab"]))
        let r = try await notified("Monzo", "Pret A Manger", "£4.50", at: 0, ctx: ctx, book: b)
        let t = try #require(r.transaction, "\(r.message)")
        #expect(t.rawMerchant == "Pret A Manger", "saved at \(t.rawMerchant)")
        #expect(t.amount == Decimal(string: "4.50"))
        #expect(t.currencyCode == "GBP")
    }
}
