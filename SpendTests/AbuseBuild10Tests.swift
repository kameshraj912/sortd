import Testing
import Foundation
import SwiftData
@testable import Spend

/// Abuse pass on what changed since build 9 (25fcd79..65135a8, 8 Oct 2026):
/// the bank-app notification reader (`BankNotice`), three-way merges and
/// refunds (`mergeNotification`, `absorbNotificationRow`, `sameRefund`), the
/// category cap nudge (`CategoryNudge`) and the `apple_pay_run` event.
/// Every run goes through `LogWalletTapIntent.handle` (or
/// `LogPurchaseIntent.handle` for the hand-built route) with a pinned `now:`.
///
/// Tests tagged `.knownBug` fail today and run only with
/// `scripts/test.sh --known-bugs`. The untagged ones are attacks that held up.
@MainActor
struct AbuseBuild10Tests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "b10-\(UUID().uuidString)")!) }
    private func suite() -> UserDefaults { UserDefaults(suiteName: "b10-nudge-\(UUID().uuidString)")! }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let minute: TimeInterval = 60

    private func rows(_ ctx: ModelContext) throws -> [Transaction] {
        try ctx.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)]))
    }

    // MARK: - The three triggers

    /// A till tap: the four tap fields.
    @discardableResult
    private func tap(_ amount: String, _ shop: String, ctx: ModelContext, book b: CardBook, at date: Date) async throws
        -> LogPurchaseIntent.Outcome {
        try await LogWalletTapIntent.handle(nil, amount: amount, merchant: shop, card: "NAB Visa Debit",
                                            in: ctx, book: b, now: date)
    }

    /// Wallet's notification (Notification › App is Wallet).
    @discardableResult
    private func wallet(_ title: String, _ subtitle: String?, _ body: String, app: String = "Wallet",
                        ctx: ModelContext, book b: CardBook, at date: Date) async throws -> LogPurchaseIntent.Outcome {
        try await LogWalletTapIntent.handle(nil, notificationTitle: title, notificationSubtitle: subtitle,
                                            notificationBody: body, notificationApp: app, in: ctx, book: b, now: date)
    }

    /// A bank app's own notification (Notification › App is the bank's).
    @discardableResult
    private func bank(_ body: String, ctx: ModelContext, book b: CardBook, at date: Date) async throws
        -> LogPurchaseIntent.Outcome {
        try await LogWalletTapIntent.handle(nil, notificationTitle: "CommBank", notificationBody: body,
                                            notificationApp: "CommBank", in: ctx, book: b, now: date)
    }

    /// One amount as each app would carry it: Wallet's short lines for a
    /// blank app or Wallet, a bank's sentence for CommBank.
    private func notifyAmount(_ amount: String, app: String, ctx: ModelContext, book b: CardBook) async throws
        -> LogPurchaseIntent.Outcome {
        if app == "CommBank" {
            return try await bank("You spent \(amount) at COLES with your card ending 4821.", ctx: ctx, book: b, at: now)
        }
        return try await wallet("NAB Visa Debit", "Coles", amount, app: app, ctx: ctx, book: b, at: now)
    }

    static let apps = ["", "Wallet", "CommBank"]

    // MARK: - A1-A4 Money in a notification

    /// Indian lakh grouping: Wallet's and a bank's notification both read
    /// "₹1,23,456.00" as ₹1.23 and "Rs. 1,50,000" as ₹1.50. The tap's own
    /// Amount field reads them right.
    ///
    /// Fixed 10 Oct 2026, was: `WalletTapText.money` (Spend/Intents/LogWalletTapIntent.swift:667) only knows groups of
    /// three, so it stops after "1" and takes ",23" as the cents.
    @Test(.bug(id: "b10-A1", "lakh-grouped rupees in a notification are read as ₹1.23"),
          arguments: apps)
    func lakhRupeesInANotificationAreReadWhole(app: String) async throws {
        for (text, expected) in [("₹1,23,456.00", "123456"), ("Rs. 1,50,000", "150000")] {
            let ctx = store()
            let r = try await notifyAmount(text, app: app, ctx: ctx, book: book())
            let t = try #require(r.transaction, "\(text) app '\(app)': \(r.message)")
            #expect(t.amount == Decimal(string: expected), "\(text) app '\(app)' saved \(t.amount)")
            #expect(t.currencyCode == "INR")
        }
    }

    /// A French or German phone writes the euro sign after the amount, and
    /// French groups thousands with a space ("12 345,67 €", U+202F or a plain
    /// space). In a notification that is saved as A$345.67: the wrong amount
    /// and the wrong currency. (The U+202F tap-field case is hunt-money-03;
    /// this is the notification reader, and the plain space too.)
    ///
    /// Fixed 10 Oct 2026, was: `WalletTapText.money` (Spend/Intents/LogWalletTapIntent.swift:668-674): no pattern takes a
    /// trailing "€", and the cents pattern restarts after the space.
    @Test(.bug(id: "b10-A2", "space-grouped euros with a trailing € are read as the last group in the card's currency"),
          arguments: apps)
    func spaceGroupedEurosInANotificationAreReadWhole(app: String) async throws {
        for (text, expected) in [("12\u{202F}345,67\u{00A0}€", "12345.67"), ("1 234,50 €", "1234.50")] {
            let ctx = store()
            let r = try await notifyAmount(text, app: app, ctx: ctx, book: book())
            let t = try #require(r.transaction, "\(text) app '\(app)': \(r.message)")
            #expect(t.amount == Decimal(string: expected), "\(text.debugDescription) app '\(app)' saved \(t.amount)")
            #expect(t.currencyCode == "EUR", "\(text.debugDescription) app '\(app)' saved in \(t.currencyCode)")
        }
    }

    /// "12,50 €" in a notification keeps the amount but drops the euro: it
    /// is saved as A$12.50 (the card's currency). The tap field gets EUR.
    ///
    /// Fixed 10 Oct 2026, was: `WalletTapText.money` (Spend/Intents/LogWalletTapIntent.swift:673) returns only "12,50", so
    /// `AmountParser` never sees the "€".
    @Test(.bug(id: "b10-A3", "a trailing € in a notification is dropped, so euros are saved as the card's currency"),
          arguments: apps)
    func aTrailingEuroSignInANotificationIsKept(app: String) async throws {
        let r = try await notifyAmount("12,50 €", app: app, ctx: store(), book: book())
        let t = try #require(r.transaction, "\(r.message)")
        #expect(t.amount == Decimal(string: "12.50"))
        #expect(t.currencyCode == "EUR", "saved in \(t.currencyCode)")
    }

    /// Dot-grouped thousands with no leading sign ("1.234,50 €", "Rp150.000")
    /// find no amount at all in a notification, so the purchase is lost
    /// ("no amount" / "not a purchase"). The tap field reads both.
    ///
    /// Fixed 10 Oct 2026, was: `WalletTapText.money` (Spend/Intents/LogWalletTapIntent.swift:663-674): "Rp" is not a
    /// marker and the cents-only pattern needs no digit before the dot.
    @Test(.bug(id: "b10-A4", "dot-grouped amounts with no leading sign are missed in a notification"),
          arguments: apps)
    func dotGroupedAmountsInANotificationAreNotMissed(app: String) async throws {
        for (text, expected, currency) in [("1.234,50 €", "1234.50", "EUR"), ("Rp150.000", "150000", "IDR")] {
            let r = try await notifyAmount(text, app: app, ctx: store(), book: book())
            let t = try #require(r.transaction, "\(text) app '\(app)': \(r.message)")
            #expect(t.amount == Decimal(string: expected))
            #expect(t.currencyCode == currency)
        }
    }

    // MARK: - A5-A8 Refunds

    /// Brief's case: a purchase, a till refund (tap), the same item bought
    /// again, then the bank's refund notice 11 minutes after the till
    /// refund. The bank's notice is the same refund, so the new purchase
    /// must still count. Today it is marked refunded and drops out of totals.
    ///
    /// Fixed 8 Oct 2026, was: `LogPurchaseIntent.sameRefund` (Spend/Intents/LogPurchaseIntent.swift:546) only looks
    /// `triggerPairWindow` (10 min) back; a bank's refund notice comes later, and
    /// `Refunds.markRefundedPurchase` then takes the next matching purchase.
    @Test(.bug(id: "b10-A5", "a bank's refund notice more than 10 min after the till refund refunds a second purchase"))
    func aLateBankRefundDoesNotRefundTheRepurchase() async throws {
        let ctx = store(), b = book()
        try await tap("A$20.00", "Uniqlo", ctx: ctx, book: b, at: now)
        try await tap("-A$20.00", "Uniqlo", ctx: ctx, book: b, at: now + 5 * minute)
        let again = try await tap("A$20.00", "Uniqlo", ctx: ctx, book: b, at: now + 15 * minute + 1)
        let second = try #require(again.transaction)
        #expect(!again.merged)
        try await bank("Refund of $20.00 from UNIQLO on your card ending 4821", ctx: ctx, book: b, at: now + 16 * minute)
        #expect(!second.refunded, "the re-purchase was refunded by the bank's report of the first refund")
        #expect(try rows(ctx).filter { !$0.refunded }.count == 1)
    }

    /// The everyday version: a coffee yesterday and one today at one shop;
    /// today's is refunded at the till; the bank's refund notice comes 30
    /// minutes later and takes yesterday's coffee off too.
    ///
    /// Fixed 8 Oct 2026, was: same as b10-A5, `sameRefund` (Spend/Intents/LogPurchaseIntent.swift:546).
    @Test(.bug(id: "b10-A6", "a late bank refund notice takes off yesterday's purchase as well"))
    func aLateBankRefundLeavesYesterdaysCoffee() async throws {
        let ctx = store(), b = book()
        let yesterday = try #require(try await tap("A$5.50", "Seven Seeds", ctx: ctx, book: b, at: now - 86_400).transaction)
        try await tap("A$5.50", "Seven Seeds", ctx: ctx, book: b, at: now)
        try await tap("-A$5.50", "Seven Seeds", ctx: ctx, book: b, at: now + minute)
        try await bank("Refund of $5.50 from SEVEN SEEDS on your card ending 4821", ctx: ctx, book: b, at: now + 31 * minute)
        #expect(!yesterday.refunded, "yesterday's coffee was refunded by today's refund")
        #expect(try rows(ctx).filter(\.refunded).count == 1)
    }

    /// A partial refund (A$10 off A$59.90) reported by the tap, Wallet and,
    /// 11+ minutes later, the bank comes off twice: A$39.90 is left.
    ///
    /// Fixed 8 Oct 2026, was: same window, `sameRefund` (Spend/Intents/LogPurchaseIntent.swift:546), then
    /// `Refunds.markPartiallyRefunded` lowers the row again.
    @Test(.bug(id: "b10-A7", "a partial refund reported late by the bank is taken off twice"))
    func aPartialRefundReportedThreeTimesComesOffOnce() async throws {
        let ctx = store(), b = book()
        let row = try #require(try await tap("A$59.90", "Uniqlo", ctx: ctx, book: b, at: now).transaction)
        try await tap("-A$10.00", "Uniqlo", ctx: ctx, book: b, at: now + 5 * minute)
        try await wallet("NAB Visa Debit", "Uniqlo", "Refund · -A$10.00", ctx: ctx, book: b, at: now + 5 * minute + 30)
        try await bank("Refund of $10.00 from UNIQLO on your card ending 4821", ctx: ctx, book: b,
                       at: now + 5 * minute + 700)
        #expect(row.amount == Decimal(string: "49.90"), "left \(row.amount) after one A$10 refund")
    }

    /// An exchange at the till: refund A$20, buy the same thing again a
    /// minute later. The new purchase merges into the refunded row and is
    /// lost (the row stays refunded). Same root as abuse-28, reached here
    /// through the tap route.
    ///
    /// Fixed 10 Oct 2026, was: `TransactionLogger.log`/`Deduper` (Spend/Services/Deduper.swift) merge into a refunded row;
    /// `mergeTapCompanion` (Spend/Intents/LogPurchaseIntent.swift:404) only excludes taps within 3 minutes.
    @Test(.bug(id: "b10-A8", "a re-purchase right after a till refund merges into the refunded row"))
    func aRepurchaseAfterATillRefundIsCounted() async throws {
        let ctx = store(), b = book()
        try await tap("A$20.00", "Uniqlo", ctx: ctx, book: b, at: now)
        try await tap("-A$20.00", "Uniqlo", ctx: ctx, book: b, at: now + 5 * minute)
        let again = try await tap("A$20.00", "Uniqlo", ctx: ctx, book: b, at: now + 6 * minute)
        let t = try #require(again.transaction)
        #expect(!t.refunded, "the new purchase was folded into the refunded one: \(again.message)")
        #expect(try rows(ctx).filter { !$0.refunded }.count == 1)
    }

    // MARK: - A9-A10 Bank sentences

    /// "refund" anywhere in a bank's purchase makes it a refund: a footer
    /// ("Not you? … request a refund") takes yesterday's A$23.40 DoorDash
    /// off and logs nothing; a shop called "Refund Centre" becomes a refund.
    ///
    /// Fixed 8 Oct 2026, was: `BankNotice.read` (Spend/Services/BankNotice.swift:251) sets `refund` from
    /// `refundPattern` anywhere in the text, even after a spend word.
    @Test(.bug(id: "b10-A9", "the word refund anywhere in a bank's purchase sentence turns it into a refund"))
    func aSpendSentenceWithRefundInItIsAPurchase() async throws {
        let ctx = store(), b = book()
        let yesterday = try #require(try await tap("A$23.40", "DoorDash", ctx: ctx, book: b, at: now - 86_400).transaction)
        let r = try await bank("You spent $23.40 at DOORDASH. Not you? Tap to dispute or request a refund.",
                               ctx: ctx, book: b, at: now)
        #expect(!r.refund, "\(r.message)")
        #expect(!yesterday.refunded, "yesterday's purchase was refunded by a purchase notice")

        let shop = try await bank("You spent $23.40 at REFUND CENTRE with your card ending 4821.",
                                  ctx: store(), book: book(), at: now)
        #expect(!shop.refund, "\(shop.message)")
    }

    /// Two purchases in one bank sentence are refused ("not a purchase")
    /// when the amounts differ, but logged as one when they are equal:
    /// "$20.00 at UBER and $20.00 at DOORDASH" saves A$20 at Uber.
    ///
    /// Fixed 8 Oct 2026, was: `BankNotice.hasSecondAmount` (Spend/Services/BankNotice.swift:269) removes every copy of the
    /// first amount before looking for a second, so an equal second amount is never seen.
    @Test(.bug(id: "b10-A10", "two equal amounts in one bank sentence are read as one purchase"))
    func twoEqualAmountsInOneBankSentenceAreNotOnePurchase() async throws {
        for body in ["You spent $20.00 at UBER and $20.00 at DOORDASH.",
                     "You spent $5.50 at SEVEN SEEDS. You spent $5.50 at MARKET LANE."] {
            let ctx = store()
            let r = try await bank(body, ctx: ctx, book: book(), at: now)
            #expect(r.transaction == nil, "\(body) -> \(r.message)")
            #expect(try rows(ctx).isEmpty)
        }
    }

    // MARK: - A11-A12 Merges that do not happen

    /// An Australian card in Singapore: the tap says S$20.00, the bank's
    /// app says $23.10 (its own currency). One purchase, two rows: counted
    /// twice. Pairing matches on the amount only (spec: "currency is not
    /// compared"), so a converted amount never pairs. Expected behaviour is
    /// Raj's call; the double count is what a user sees.
    ///
    /// Known bug: `LogPurchaseIntent.mergeNotification` (Spend/Intents/LogPurchaseIntent.swift:625) needs
    /// `amount == parsed.amount`.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "b10-A11", "an overseas tap and the bank's converted amount are two rows"))
    func anOverseasTapAndTheBanksConvertedAmountAreOneRow() async throws {
        let ctx = store(), b = book()
        try await tap("S$20.00", "Toast Box", ctx: ctx, book: b, at: now)
        try await bank("You spent $23.10 at TOAST BOX SINGAPORE with your card ending 4821.", ctx: ctx, book: b,
                       at: now + minute)
        #expect(try rows(ctx).count == 1, "one purchase counted twice")
    }

    /// A shop named only in emoji ("🍕"): the tap and Wallet's notification
    /// of one purchase never pair, so it is counted twice.
    ///
    /// Fixed 10 Oct 2026, was: `LogPurchaseIntent.shopsAgree` (Spend/Intents/LogPurchaseIntent.swift:488) uses
    /// `Deduper.similarity`, which is 0 for two names with no letters or digits.
    @Test(.bug(id: "b10-A12", "an emoji-only shop's tap and notification are two rows"))
    func anEmojiOnlyShopsTapAndNotificationAreOneRow() async throws {
        let ctx = store(), b = book()
        try await tap("A$23.40", "🍕", ctx: ctx, book: b, at: now)
        try await wallet("NAB Visa Debit", "🍕", "A$23.40", ctx: ctx, book: b, at: now + 20)
        #expect(try rows(ctx).count == 1)
    }

    // MARK: - A13 Hang

    /// A 10,000-digit notification body (or free-text transaction) takes
    /// about 7.5 s, 20,000 digits about 30 s: every `money(in:)` call is
    /// quadratic. A bank sentence ("You spent 1111….00 at X") takes ~4 s even
    /// from a bank's app.
    ///
    /// Fixed 8 Oct 2026, was: `WalletTapText.money` (Spend/Intents/LogWalletTapIntent.swift:671), the "6.20 SGD"
    /// pattern has no lookbehind, so `\d+` restarts at every digit.
    @Test(.bug(id: "b10-A13", "a long run of digits makes the notification reader take seconds"))
    func aLongRunOfDigitsReturnsQuickly() async throws {
        let digits = String(repeating: "1", count: 10_000)
        for (body, app) in [(digits, ""), (digits, "Wallet"), ("You spent \(digits).00 at X", "CommBank")] {
            let start = Date()
            _ = try await wallet("NAB Visa Debit", nil, body, app: app, ctx: store(), book: book(), at: now)
            let took = Date().timeIntervalSince(start)
            #expect(took < 2, "app '\(app)': \(took) s")
        }
    }

    // MARK: - A14 Nudge

    /// The phone's clock set back a year and the app opened: the
    /// foreground check keeps only that month's records and saves them, so
    /// this month's "near its limit" record is wiped. Clock fixed: the same
    /// crossing is announced a second time.
    ///
    /// Fixed 10 Oct 2026, was: `CategoryBudgets.dueAlerts` dropped every other month, later ones
    /// included, and `Reminders.checkCategoryLimits` saved that.
    @Test(.bug(id: "b10-A14", "a clock set back wipes this month's limit records, so the alert repeats"))
    func aClockSetBackDoesNotRepeatALimitAlert() async throws {
        let d = suite()
        CategoryBudgets.set(200, for: .transport, d)
        let spent = [Transaction(date: now - 3_600, merchant: "Uber", amount: 180, currencyCode: Money.home,
                                 card: .other, category: .transport, source: .tap)]
        await Reminders.checkCategoryLimits(spent, now: now, defaults: d, allowed: { true })
        #expect((d.array(forKey: CategoryNudge.datesKey) as? [Date])?.count == 1)

        await Reminders.checkCategoryLimits(spent, now: now - 365 * 86_400, defaults: d, allowed: { true })
        await Reminders.checkCategoryLimits(spent, now: now + 60, defaults: d, allowed: { true })
        #expect((d.array(forKey: CategoryNudge.datesKey) as? [Date])?.count == 1, "the same crossing was posted twice")
    }

    // MARK: - A15 Zero refund

    /// "-0.00" in the tap's Amount saves a A$0.00 row marked refunded and
    /// says "Refund of $0.00 from Coles noted". A zero amount is a missing
    /// amount, not a refund.
    ///
    /// Fixed 10 Oct 2026, was: `LogPurchaseIntent.handle` (Spend/Intents/LogPurchaseIntent.swift:196, 336) takes the sign
    /// from the text even when the amount is 0.
    @Test(.bug(id: "b10-A15", "a minus-zero tap is saved as a refunded A$0.00 row"))
    func aMinusZeroTapIsNotARefund() async throws {
        let r = try await tap("-0.00", "Coles", ctx: store(), book: book(), at: now)
        #expect(!r.refund, "\(r.message)")
        #expect(r.transaction?.refunded != true)
    }

    // MARK: - Held up (regression)

    static let gaps: [TimeInterval] = [0, 59, 61]
    static let orders: [String] = ["twb", "tbw", "wtb", "wbt", "btw", "bwt"]

    /// One payment reported by the tap, Wallet and the bank, in every order,
    /// 0, 59 or 61 s apart: one row, all three letters. (9-minute gaps put
    /// the third report 18 min after the first row and make a second row;
    /// 11-minute gaps make three. Both follow the 10-minute window by design.)
    @Test(arguments: orders, gaps)
    func onePaymentFromThreeTriggersIsOneRow(order: String, gap: TimeInterval) async throws {
        let ctx = store(), b = book()
        for (i, k) in order.enumerated() {
            let at = now + Double(i) * gap
            switch k {
            case "t": try await tap("A$23.40", "DoorDash", ctx: ctx, book: b, at: at)
            case "w": try await wallet("NAB Visa Debit", "DoorDash", "A$23.40", ctx: ctx, book: b, at: at)
            default: try await bank("You spent $23.40 at DOORDASH*ORDER with your card ending 4821.", ctx: ctx, book: b, at: at)
            }
        }
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "tnb")
    }

    /// Two coffees of one amount at two shops, three reports each,
    /// interleaved: two rows, one per shop.
    @Test func twoShopsOneAmountThreeTriggersEachAreTwoRows() async throws {
        let ctx = store(), b = book()
        try await tap("A$5.50", "Seven Seeds", ctx: ctx, book: b, at: now)
        try await tap("A$5.50", "Market Lane", ctx: ctx, book: b, at: now + 120)
        try await wallet("NAB Visa Debit", "Seven Seeds", "A$5.50", ctx: ctx, book: b, at: now + 150)
        try await bank("You spent $5.50 at MARKET LANE COFFEE with your card ending 4821.", ctx: ctx, book: b, at: now + 160)
        try await wallet("NAB Visa Debit", "Market Lane", "A$5.50", ctx: ctx, book: b, at: now + 170)
        try await bank("You spent $5.50 at SEVEN SEEDS CARLTON with your card ending 4821.", ctx: ctx, book: b, at: now + 300)
        let all = try rows(ctx)
        #expect(all.map(\.rawMerchant) == ["Seven Seeds", "Market Lane"])
        #expect(all.allSatisfy { $0.tapOrigins == "tnb" })
    }

    /// The hand-built route (`LogPurchaseIntent`) still pairs with Wallet
    /// and the bank, either side first.
    @Test(arguments: [true, false])
    func theHandBuiltRouteStillMerges(tapFirst: Bool) async throws {
        let ctx = store(), b = book()
        func handBuilt(_ at: Date) async throws {
            _ = try await LogPurchaseIntent.handle(merchant: "DoorDash", amount: "A$23.40", card: "NAB Visa Debit",
                                                   in: ctx, book: b, now: at)
        }
        if tapFirst { try await handBuilt(now) }
        try await wallet("NAB Visa Debit", "DoorDash", "A$23.40", ctx: ctx, book: b, at: now + 30)
        try await bank("You spent $23.40 at DOORDASH*ORDER with your card ending 4821.", ctx: ctx, book: b, at: now + 60)
        if !tapFirst { try await handBuilt(now + 90) }
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "tnb")
    }

    /// One purchase that crosses 80%, reported three times: one alert.
    @Test func aCrossingReportedThreeTimesIsOneNudge() async throws {
        let d = suite()
        let ctx = store(), b = book()
        let first = try await tap("A$30.00", "Uber", ctx: ctx, book: b, at: now)
        let t = try #require(first.transaction)
        ctx.insert(Transaction(date: now - 7_200, merchant: "Shop", amount: 150, currencyCode: Money.home,
                               card: .other, category: t.category, source: .tap))
        try ctx.save()
        CategoryBudgets.set(200, for: t.category, d)
        await CategoryNudge.post(for: first, in: ctx, now: now, defaults: d, allowed: { true })
        let second = try await wallet("NAB Visa Debit", "Uber", "A$30.00", ctx: ctx, book: b, at: now + 30)
        await CategoryNudge.post(for: second, in: ctx, now: now + 30, defaults: d, allowed: { true })
        let third = try await bank("You spent $30.00 at UBER *TRIP with your card ending 4821.", ctx: ctx, book: b, at: now + 60)
        await CategoryNudge.post(for: third, in: ctx, now: now + 60, defaults: d, allowed: { true })
        #expect(second.merged && third.merged)
        #expect((d.array(forKey: CategoryNudge.datesKey) as? [Date])?.count == 1)
    }

    /// Limits of 0, below 0 and NaN are no limit; 1e9 is a limit that is
    /// never crossed by A$500.
    @Test func oddLimitsAreSafe() {
        let d = suite()
        d.set(["transport": 0.0, "groceries": -5.0, "eatingOut": Double.nan, "shopping": 1e9], forKey: CategoryBudgets.key)
        #expect(CategoryBudgets.all(d) == [.shopping: 1e9])
        let t = Transaction(date: now, merchant: "Big", amount: 500, currencyCode: Money.home, card: .other,
                            category: .shopping, source: .tap)
        #expect(CategoryNudge.due(for: t, in: [t], limits: CategoryBudgets.all(d), sent: [], now: now).alert == nil)
    }

    /// Month boundary in Melbourne (AEDT) and Singapore (SGT): a tap at
    /// 23:59:59 on 31 Oct counts for October; at 00:00:00 on 1 Nov the
    /// month starts again, so October's spend no longer counts.
    @Test(arguments: ["Australia/Melbourne", "Asia/Singapore"])
    func monthBoundaryIsLocal(zone: String) throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: zone))
        let lastSecond = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 59, second: 59)))
        let midnight = lastSecond + 1
        func txn(_ amount: Decimal, _ at: Date) -> Transaction {
            Transaction(date: at, merchant: "Uber", amount: amount, currencyCode: Money.home, card: .other,
                        category: .transport, source: .tap)
        }
        let earlier = txn(150, lastSecond - 86_400)
        let late = txn(30, lastSecond)
        let inOctober = CategoryNudge.due(for: late, in: [earlier, late], limits: [.transport: 200], sent: [],
                                          now: lastSecond, calendar: cal)
        #expect(inOctober.alert?.threshold == .near)
        #expect(inOctober.sent.contains("2026-10|transport|80"))
        let early = txn(30, midnight)
        let inNovember = CategoryNudge.due(for: early, in: [earlier, late, early], limits: [.transport: 200],
                                           sent: inOctober.sent, now: midnight, calendar: cal)
        #expect(inNovember.alert == nil)
    }

    /// Every run below gives one `result` word from the fixed list, the
    /// same ten keys, no denied key and no value that looks like money. A
    /// real shop named "Sortd Check" reads as `health_check` (by design).
    @Test func everyHostileRunLogsOneCleanResultWord() async throws {
        let words: Set<String> = ["saved", "merged", "needs_check", "blank", "no_amount", "not_completed", "money_in",
                                  "refund", "health_check", "queued", "not_saved", "not_purchase"]
        let keys: Set<String> = ["kind", "result", "has_amount", "has_shop", "has_card", "has_app", "has_title",
                                 "has_subtitle", "has_body", "has_text"]
        let hostile = ["₹1,23,456.00", "12\u{202F}345,67 €", "-0.00", "$1e3", "A$\u{0000}4.50", "\u{200F}A$4.50\u{200F}",
                       "🍕🍕", String(repeating: "\n", count: 500) + "A$4.50", "١٢٫٥٠", ""]
        var seen: Set<String> = []
        for text in hostile {
            for app in Self.apps {
                for runTap in [true, false] {
                    let ctx = store(), b = book()
                    let n = runTap ? WalletNotification() : WalletNotification(title: "NAB Visa Debit", subtitle: "Coles",
                                                                               body: text, app: app)
                    let outcome = try await LogWalletTapIntent.handle(nil, amount: runTap ? text : nil,
                                                                      merchant: runTap ? "Sortd Check" : nil,
                                                                      notificationTitle: n.title, notificationSubtitle: n.subtitle,
                                                                      notificationBody: n.body, notificationApp: n.app,
                                                                      in: ctx, book: b, now: now)
                    let event = LogWalletTapIntent.runEvent(outcome: outcome, transaction: nil, amount: runTap ? text : nil,
                                                            merchant: runTap ? "Sortd Check" : nil, card: nil, notification: n)
                    #expect(Set(event.keys) == keys)
                    #expect(Set(event.keys).isDisjoint(with: Analytics.deniedKeys))
                    guard case .string(let result)? = event["result"] else { Issue.record("no result"); continue }
                    #expect(words.contains(result), "\(text.debugDescription) app '\(app)' -> \(result)")
                    seen.insert(result)
                    for case .string(let s) in event.values {
                        #expect(s.range(of: #"\d"#, options: .regularExpression) == nil, "value \(s) carries digits")
                    }
                }
            }
        }
        #expect(seen.contains("health_check"))
    }
}
