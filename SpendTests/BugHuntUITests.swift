import Testing
import SwiftData
import Foundation
@testable import Spend

/// Bug hunt 26 Sep 2026, area ui-intents-widget: the Wallet tap intents, the
/// Siri questions, the widget summary and its reload timing.
///
/// Every test here documents an unfixed finding. Each is tagged as a known
/// bug and runs only with `scripts/test.sh --known-bugs`. Fixing one means
/// removing its tag and trait.
@MainActor
struct BugHuntUITests {

    // MARK: - Harness

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func book() -> CardBook {
        CardBook(defaults: UserDefaults(suiteName: "bughunt-ui-\(UUID().uuidString)")!)
    }

    private let melbourne: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return c
    }()

    private func at(_ ymdhm: String) -> Date {
        let f = DateFormatter()
        f.calendar = melbourne
        f.timeZone = melbourne.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: ymdhm)!
    }

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - 1. Partial refund tap

    /// Returning one item of a A$59.90 purchase: a "-A$20.00" tap at the same
    /// shop makes its own refunded row (worth 0) and leaves the A$59.90 row
    /// counting in full, while Siri says "Refund of $20.00 from Uniqlo noted".
    ///
    /// `LogPurchaseIntent.handle` (Spend/Intents/LogPurchaseIntent.swift:116-124)
    /// only matches a refund whose amount equals a whole purchase
    /// (`Refunds.markRefunded`, `t.amount == amount`); anything else falls
    /// through to lines 140-144 and becomes a standalone refunded row.
    @Test
    func aPartialRefundTapLowersTheTotal() async throws {
        let ctx = try store()
        let b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Uniqlo", amount: "A$59.90", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: start)
        let refund = try await LogPurchaseIntent.handle(merchant: "Uniqlo", amount: "-A$20.00", card: "NAB Visa Debit",
                                                        in: ctx, book: b, now: start.addingTimeInterval(3 * 86400))
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        // What still counts, in the purchase's own currency (so the host's
        // home currency and exchange rates play no part).
        let counted = all.reduce(Decimal(0)) { $0 + ($1.refunded ? 0 : $1.amount) }
        // The message claims the refund counted. Either the total drops by the
        // refund, or the message must say it could not be matched.
        #expect(counted == Decimal(string: "39.90")!,
                "A$\(counted) still counts after a A$20 refund on a A$59.90 purchase; message was: \(refund.message)")
    }

    // MARK: - 2. Bills widget: a bill with no exchange rate shows as 0

    /// A monthly subscription charged in a currency Sortd has no daily rate
    /// for (AED is not in `Money.supported`) is written to the widget as
    /// `audAmount` (nil → 0) in the home currency, so the Bills widget shows
    /// "$0.00 · in 2w" for Careem Plus. Siri's "Upcoming Bills" shows the real
    /// "AED 19.00" because `SpendSummary.upcomingBills` keeps the original
    /// amount and currency.
    ///
    /// `WidgetBridge.build` (Spend/Services/WidgetBridge.swift:131).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-ui-02", "the Bills widget shows a foreign bill with no rate as $0.00"))
    func aBillInACurrencyWithNoRateIsNotShownAsZero() throws {
        let ctx = try store()
        for day in ["2026-07-01 09:00", "2026-08-01 09:00", "2026-09-01 09:00"] {
            var p = IncomingPurchase(date: at(day), merchant: "Careem Plus", amount: 19, currency: "AED",
                                     card: .other, source: .email)
            p.category = .subscriptions
            _ = try TransactionLogger.log(p, in: ctx)
        }
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let now = at("2026-09-15 12:00")
        let bills = all.recurring(now: now)
        let careem = try #require(bills.first { $0.merchant == "Careem Plus" }, "the subscription was not detected")
        #expect(careem.status == .active)

        let s = WidgetBridge.build(from: all, budget: 0, now: now, calendar: melbourne)
        let shown = try #require(s.bills.first { $0.name == "Careem Plus" }, "the bill is not in the widget")
        #expect(shown.amount > 0, "the widget writes \(shown.amount) \(shown.currency) for an AED 19 bill")
    }

    // MARK: - 3. A text tap that is only a card name becomes a purchase (fixed)

    /// Fixed by spec 2026-09-26 ("Apple Pay logging — failsafes", failsafe
    /// #10): the one-field Wallet action given just "NAB Visa Debit" used to
    /// save a purchase called "Nab Visa Debit" with amount 0, marking it as
    /// a real tap and firing the activation event — reading as a real
    /// purchase, not a mis-wired automation. It no longer does either of
    /// that, but it also isn't dropped like the three-field action's bare ▶
    /// case: the tap is kept, with no shop name, tagged "needs a check", so
    /// a genuinely mis-wired automation still shows up somewhere instead of
    /// vanishing silently.
    ///
    /// `LogWalletTapIntent.resolvedFields` (Spend/Intents/LogWalletTapIntent.swift)
    /// now refuses to promote text to the merchant when that text
    /// `looksLikeCard` — `WalletTapText.parse` had already put it in `card`.
    @Test
    func aTextTapThatIsOnlyACardNameIsFlaggedNotSavedAsAShop() async throws {
        let ctx = try store()
        let out = try await LogWalletTapIntent.handle("NAB Visa Debit", in: ctx, book: book(), now: start)
        let t = try #require(out.transaction, "the tap must still be kept, not dropped")
        #expect(t.merchant == "Unknown merchant")
        #expect(t.needsCheck)
        #expect(t.amount == 0)
    }

    // MARK: - 4. Widget reload time across a daylight-saving change

    /// The three timeline providers (SortdWidget/SortdWidget.swift:69,
    /// SortdWidget/SortdWidgetIntent.swift:145 and :171) schedule the next
    /// reload as `startOfDay(for: .now + 86_400 s)`. On the 23-hour day when
    /// clocks go forward, a timeline built between 23:00 and midnight the
    /// night before lands on the midnight *after* next, so "Today" keeps the
    /// previous day's total for a whole day. On the 25-hour day when clocks
    /// go back, a timeline built in the first hour gets a date already in
    /// the past. The widget target can't be imported here, so this repeats
    /// the exact expression from those three lines.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-ui-04", "widget reload date is wrong on the daylight-saving change days"))
    func theWidgetReloadDateIsTheNextMidnightAcrossDaylightSaving() {
        func widgetPolicy(_ now: Date) -> Date {
            // As written in the providers, with the Melbourne calendar in
            // place of Calendar.current.
            melbourne.startOfDay(for: now.addingTimeInterval(86_400))
        }
        func nextMidnight(_ now: Date) -> Date {
            melbourne.date(byAdding: .day, value: 1, to: melbourne.startOfDay(for: now))!
        }
        // Clocks go forward at 02:00 on Sunday 4 Oct 2026 (a 23-hour day).
        let eve = at("2026-10-03 23:30")
        #expect(widgetPolicy(eve) == nextMidnight(eve),
                "reload set for \(widgetPolicy(eve)) instead of \(nextMidnight(eve))")
        // Clocks go back at 03:00 on Sunday 5 Apr 2026 (a 25-hour day).
        let small = at("2026-04-05 00:30")
        #expect(widgetPolicy(small) > small, "reload date \(widgetPolicy(small)) is already in the past")
    }

    // MARK: - Bug hunt 3 Oct 2026 (docs/BugHunt-2026-10-03.md)

    /// U1: an all-caps shop word that is also a currency code, followed by a
    /// number ("TOP 10 PIZZA"), was read as the amount, so the real A$23.50
    /// in the body was lost.
    @Test(.bug("U1: a currency code in the shop name beats the real amount"))
    func aShopNameThatStartsWithACurrencyCodeIsNotTheAmount() async throws {
        let ctx = try store()
        let r = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                                    notificationTitle: "TOP 10 PIZZA", notificationSubtitle: "",
                                                    notificationBody: "A$23.50 with NAB Visa Debit",
                                                    in: ctx, book: book(), now: start)
        let t = try #require(r.transaction)
        #expect(t.amount == Decimal(string: "23.50"))
        #expect(t.currencyCode == "AUD")
        #expect(t.rawMerchant == "TOP 10 PIZZA")
    }

    /// U2: one-line tap text with a clock time in it was skipped whole as a
    /// date line, so nothing was logged.
    @Test(.bug("U2: one-line tap text with a time is thrown away"))
    func aOneLineTapWithATimeIsStillLogged() async throws {
        let ctx = try store()
        let r = try await LogWalletTapIntent.handle("Coles A$23.50 9:41 am NAB Visa Debit",
                                                    in: ctx, book: book(), now: start)
        let t = try #require(r.transaction, "nothing logged: \(r.message)")
        #expect(t.amount == Decimal(string: "23.50"))
        #expect(t.rawMerchant == "Coles")
    }

    /// U4: Siri's questions read every row, so "Last Purchase" named the
    /// hidden "Sortd Check" row.
    @Test(.bug("U4: Siri question intents read the hidden health-check rows"))
    func siriLeavesOutTheHiddenCheckRows() async throws {
        let ctx = try store()
        let b = book()
        _ = try await LogWalletTapIntent.handle(nil, amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                                in: ctx, book: b, now: start)
        _ = try await LogWalletTapIntent.handle(ApplePayHealthCheck.payloadText, in: ctx, book: b,
                                                now: start.addingTimeInterval(7200))
        let rows = try SpendQuestions.transactions(in: ctx)
        #expect(!rows.contains { $0.merchant == ApplePayHealthCheck.merchant || $0.rawMerchant == ApplePayHealthCheck.merchant })
        let text = SpendSummary.lastPurchase(rows.map(SpendSummary.Purchase.init),
                                             now: start.addingTimeInterval(7300), calendar: melbourne)
        #expect(text.contains("Seven Seeds"), "Siri said: \(text)")
    }

    /// U5: a tap with no shop is saved as "Unknown merchant", which the
    /// Recent widget's empty-name rule did not catch.
    @Test(.bug("U5: Recent and Today widgets show taps that came with no shop"))
    func aTapWithNoShopIsLeftOutOfTheRecentWidget() async throws {
        let ctx = try store()
        _ = try await LogWalletTapIntent.handle(nil, amount: "A$12.00", merchant: "", card: "NAB Visa Debit",
                                                in: ctx, book: book(), now: start)
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(WidgetBridge.recentItems(from: all, currency: Money.home).isEmpty,
                "shown: \(WidgetBridge.recentItems(from: all, currency: Money.home).map(\.merchant))")
    }

    /// U6: the "Log it now" widget's Scan button (sortd://scan) opened the
    /// plain Add sheet, the same as its Add button.
    @Test(.bug("U6: the widget's Scan link opens plain Add"))
    func theScanLinkOpensTheReceiptScanner() throws {
        let router = Router.shared
        router.sheet = nil
        router.follow(try #require(Router.target(for: URL(string: "sortd://scan")!)))
        #expect(router.sheet == .scan)
        router.sheet = nil
        router.tab = .home
    }

    /// U7: "Needs a check … Tap to fix" opened the Activity list, not the
    /// purchase that needs fixing.
    @Test(.bug("U7: the needs-a-check notice opens Activity, not the purchase"))
    func aNeedsACheckNoticeOpensThatPurchase() throws {
        let id = UUID()
        let link = LoggedNotice.link(for: .needsCheck(id: id, missingShop: false, missingAmount: true))
        #expect(link == "sortd://purchase/\(id.uuidString)")
        let url = try #require(URL(string: link))
        let target = try #require(Router.target(for: url))
        #expect(target == Router.Target(name: "purchase", id: id.uuidString))
    }
}
