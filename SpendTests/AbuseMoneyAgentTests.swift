import Testing
import Foundation
import SwiftData
@testable import Spend

// Adversarial tests against the money, amount-parsing, currency and FX logic.
// Every test here states what the app *should* do. A failure is a finding.
//
// Nothing in this file touches Spend/ or any other test file.

// MARK: - AmountParser: what counts as a number

struct AbuseAmountParserTests {

    /// A minus written after the currency marker is still a refund.
    /// Wallet/bank text shows refunds as "A$-4.50", "-A$4.50", "(A$4.50)"
    /// and "4.50-" depending on the bank. Only a leading minus is spotted,
    /// so the others are logged as *purchases* and push the total the wrong way.
    @Test func aMinusAfterTheCurrencyIsStillARefund() {
        #expect(AmountParser.isNegative("-A$4.50"))      // passes today
        #expect(AmountParser.isNegative("(A$4.50)"))     // passes today
        #expect(AmountParser.isNegative("A$-4.50"), "A$-4.50 read as a purchase")
        #expect(AmountParser.isNegative("SGD -12.30"), "SGD -12.30 read as a purchase")
        #expect(AmountParser.isNegative("4.50-"), "trailing-minus (bank exports) read as a purchase")
    }

    /// Three or more decimals are thrown away and the digits glued together,
    /// so 12.345 becomes twelve thousand three hundred and forty five.
    /// Real for 3-decimal currencies (KWD, BHD, OMR, JOD, TND) and for any
    /// unit price a CSV or receipt carries.
    @Test func extraDecimalsAreNotTurnedIntoThousands() {
        #expect(AmountParser.parse("12.345")?.amount == Decimal(string: "12.345"))
        #expect((AmountParser.parse("0.12345")?.amount ?? 0) < 1, "a sub-dollar amount became thousands")
        #expect((AmountParser.parse("KWD 12.345")?.amount ?? 0) < 100)
    }

    /// The leftmost number wins, not the one written like money.
    @Test func theAmountBeatsAnyOtherNumberInTheText() {
        #expect(AmountParser.parse("2 x A$4.50")?.amount == Decimal(string: "4.50"))
        #expect(AmountParser.parse("12/09/2026 A$4.50")?.amount == Decimal(string: "4.50"))
    }

    /// A currency marker is matched as a bare substring anywhere in the text,
    /// so ordinary letters name a currency.
    @Test func aCurrencyIsNotGuessedFromLettersInsideAWord() {
        #expect(AmountParser.currency(in: "CARMENS 12.00") == nil, "the RM in CARMENS read as Malaysian ringgit")
        #expect(AmountParser.currency(in: "HOURS. 12.00") == nil, "the RS. in HOURS. read as Indian rupees")
        #expect(AmountParser.currency(in: "MYRTLE CAFE 8.00") == nil)
    }

    /// Thousands separators in every written form.
    @Test func thousandsSeparatorsAreReadTheSameWay() {
        #expect(AmountParser.parse("1,234.56")?.amount == Decimal(string: "1234.56"))
        #expect(AmountParser.parse("1.234,56")?.amount == Decimal(string: "1234.56"))
        #expect(AmountParser.parse("1 234,56")?.amount == Decimal(string: "1234.56"))
        #expect(AmountParser.parse("Rp 12.500")?.amount == Decimal(string: "12500"))
    }

    /// Junk in, nothing out — never a number invented from the noise.
    @Test func junkGivesNothing() {
        #expect(AmountParser.parse("") == nil)
        #expect(AmountParser.parse("   ") == nil)
        #expect(AmountParser.parse("\u{200F}\u{200E}") == nil)
        #expect(AmountParser.parse("☕️🍰") == nil)
        #expect(AmountParser.parse("١٢٣") == nil)   // Arabic-Indic digits
        #expect(AmountParser.parse("１２３") == nil) // full-width digits
    }

    /// A tap amount is never negative once parsed; the sign is carried by
    /// `isNegative`.
    @Test func parsedAmountsAreNeverNegative() {
        for text in ["-5", "−5", "(5.00)", "-0", "A$-9.99"] {
            let amount = AmountParser.parse(text)?.amount ?? 0
            #expect(amount >= 0, "\(text)")
        }
    }

    /// An absurd number of digits is a mangled field, not money.
    @Test func anAbsurdlyLongNumberIsRefused() {
        let forty = String(repeating: "9", count: 40)
        #expect(AmountParser.parse(forty) == nil, "a 40-digit tap amount was accepted")
        #expect(AmountParser.parse("4111111111111111") == nil, "a card number was accepted as an amount")
    }

    /// A very long string must not hang or produce a nonsense number.
    @Test func aVeryLongStringIsHandled() {
        let long = String(repeating: "1,234.56 ", count: 1200)
        let r = AmountParser.parse(long)
        #expect(r?.amount == Decimal(string: "1234.56"))
        #expect(AmountParser.parse(String(repeating: "x", count: 10_000)) == nil)
    }
}

// MARK: - Money: display

struct AbuseMoneyFormatTests {

    /// Yen, won and rupiah have no minor units. Showing "¥1,200.00" is wrong
    /// and reads as a hundredth of the real amount to anyone who knows them.
    @Test func zeroDecimalCurrenciesAreShownWithoutCents() {
        #expect(!Money.format(1200, "JPY").contains(".00"), Comment(rawValue: Money.format(1200, "JPY")))
        #expect(!Money.format(15000, "KRW").contains(".00"), Comment(rawValue: Money.format(15000, "KRW")))
        #expect(!Money.format(50000, "IDR").contains(".00"), Comment(rawValue: Money.format(50000, "IDR")))
    }

    /// Every supported currency must give the amount field a symbol to show.
    @Test func everySupportedCurrencyHasASymbol() {
        for code in Money.supported {
            let s = Money.symbol(code)
            #expect(!s.trimmingCharacters(in: .whitespaces).isEmpty, "no symbol for \(code)")
            let hasDigits = s.rangeOfCharacter(from: .decimalDigits) != nil
            #expect(!hasDigits, "symbol for \(code) contains digits: \(s)")
        }
    }

    /// A currency code that isn't real must not crash or print raw junk.
    @Test func anUnknownCurrencyCodeStillFormats() {
        for code in ["ZZZ", "aud", "XX", "ABCD", ""] {
            #expect(!Money.format(5, code).isEmpty, "empty output for \(code)")
        }
    }

    /// Negative values keep their sign in both formatting paths.
    @Test func negativesKeepTheirSign() {
        #expect(Money.format(-5, Money.home).hasPrefix("-"))
        #expect(Money.spoken(-5, "JPY").contains("-") || Money.spoken(-5, "JPY").lowercased().contains("minus"))
    }
}

// MARK: - Transaction: what reaches a total

@MainActor
struct AbuseAudValueTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    /// A currency code that differs only in case is the same currency. Today
    /// it never matches home, never gets a rate, and counts as zero for good.
    @Test func aLowercaseHomeCurrencyStillCountsInTotals() throws {
        let t = Transaction(date: .now, merchant: "Cafe", amount: 25, currencyCode: Money.home.lowercased(),
                            card: .other, category: .eatingOut, source: .csv)
        #expect(t.audValue == 25, "a purchase in \(Money.home.lowercased()) counted as 0")
        #expect(!t.needsRate)
    }

    /// Padded or oddly-cased codes from a CSV must not silently zero a purchase.
    @Test func aPaddedCurrencyCodeStillCountsInTotals() throws {
        let t = Transaction(date: .now, merchant: "Cafe", amount: 25, currencyCode: Money.home + " ",
                            card: .other, category: .eatingOut, source: .csv)
        #expect(t.audValue == 25, "a purchase in '\(Money.home) ' counted as 0")
    }

    /// A currency with no daily rates can never be converted, so it sits at
    /// "Converting…" for ever and silently counts as zero. It should be
    /// flagged as un-convertible, not left looking like it is still loading.
    @Test func anUnsupportedCurrencyIsNotLeftConvertingForEver() throws {
        let t = Transaction(date: .now, merchant: "Pho 24", amount: 250_000, currencyCode: "VND",
                            card: .other, category: .eatingOut, source: .email)
        #expect(t.audValue == 0)  // by design: better than counting 1:1
        #expect(!t.needsRate, "VND shows 'Converting…' for ever and counts as 0")
    }

    /// Many small amounts must add up exactly — Decimal, not Double.
    @Test func manySmallAmountsDoNotDrift() throws {
        let ctx = try store()
        for i in 0..<1000 {
            let t = Transaction(date: Date(timeIntervalSince1970: 1_790_000_000 + Double(i)), merchant: "Shop \(i)",
                                amount: Decimal(string: "0.01")!, currencyCode: Money.home,
                                card: .other, category: .groceries, source: .manual)
            ctx.insert(t)
        }
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.audTotal == Decimal(string: "10.00"))
    }

    /// A single absurd amount must not poison every total in the app. Decimal
    /// overflow turns into NaN, and NaN spreads through the sum.
    @Test func oneAbsurdAmountDoesNotPoisonTheTotal() throws {
        let ctx = try store()
        let huge = Decimal(string: String(repeating: "9", count: 38))!
        for i in 0..<4 {
            let t = Transaction(date: Date(timeIntervalSince1970: 1_790_000_000 + Double(i)), merchant: "Shop \(i)",
                                amount: i == 0 ? huge : 10, currencyCode: Money.home,
                                card: .other, category: .groceries, source: .tap)
            ctx.insert(t)
        }
        let total = try ctx.fetch(FetchDescriptor<Transaction>()).audTotal
        #expect(!total.isNaN, "one huge purchase made the whole total NaN")
        #expect(total.double.isFinite, "the total is not a usable number for the charts")
    }

    /// Refunds and transfers stay out of the total.
    @Test func refundsAndTransfersStayOutOfTheTotal() throws {
        let ctx = try store()
        let a = Transaction(date: .now, merchant: "A", amount: 10, currencyCode: Money.home,
                            card: .other, category: .groceries, source: .tap)
        let b = Transaction(date: .now, merchant: "B", amount: 20, currencyCode: Money.home,
                            card: .other, category: .groceries, source: .tap)
        b.refunded = true
        let c = Transaction(date: .now, merchant: "C", amount: 100, currencyCode: Money.home,
                            card: .other, category: .transfers, source: .tap)
        [a, b, c].forEach(ctx.insert)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).audTotal == 10)
    }
}

// MARK: - FX

struct AbuseFXTests {

    /// A nonsense rate from the network must leave the budget alone, not
    /// silently set it to zero.
    @Test func agarbageRateDoesNotWipeTheBudget() {
        #expect(FXService.convertSetting(1000, rate: .infinity) > 0, "an infinite rate wiped the budget to 0")
        #expect(FXService.convertSetting(1000, rate: .nan) > 0, "a NaN rate wiped the budget to 0")
    }

    /// A rate of zero would convert every purchase to nothing.
    @Test func aZeroRateIsRefused() {
        #expect(FXService.convertSetting(1000, rate: 0) > 0, "a zero rate wiped the budget to 0")
    }

    /// Converting there and back must not lose money.
    @Test func convertingBothWaysKeepsTheValue() {
        let there = FXService.convertSetting(1000, rate: 0.9123)
        let back = FXService.convertSetting(there, rate: 1 / 0.9123)
        #expect(abs(back - 1000) < 0.02, "1000 → \(there) → \(back)")
    }

    /// The day key must be a real date for any date the app can hold.
    @Test func theDayKeyIsAlwaysAValidDate() {
        for d in [Date.distantPast, Date.distantFuture, Date(timeIntervalSince1970: 0), Date.now] {
            let s = FXService.dayString(d)
            #expect(s.range(of: #"^-?\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, "\(s)")
        }
    }
}

// MARK: - QuickEntry currencies

struct AbuseQuickEntryCurrencyTests {

    /// A currency the app supports and the line clearly names must survive.
    /// Anything outside a short hard-coded list is dropped and the purchase
    /// is logged in the home currency instead.
    @Test func aWrittenCurrencyTheAppSupportsIsKept() {
        #expect(QuickEntry.read("dinner 120 thb")?.currency == "THB", "120 THB logged as 120 in the home currency")
        #expect(QuickEntry.read("lunch 50 chf")?.currency == "CHF")
        #expect(QuickEntry.read("taxi 200 php")?.currency == "PHP")
        #expect(QuickEntry.read("coffee 35 cny")?.currency == "CNY")
    }

    /// Currency signs the app shows elsewhere must be read here too.
    @Test func currencySignsAreRead() {
        #expect(QuickEntry.read("sushi ¥1200")?.currency == "JPY", "¥1200 logged as 1200 in the home currency")
        #expect(QuickEntry.read("coffee £3.20")?.currency == "GBP")   // passes today
        #expect(QuickEntry.read("beer €4.50")?.currency == "EUR")     // passes today
    }

    /// A bare "$" says nothing, and nothing is invented.
    @Test func noCurrencyIsInventedFromNothing() {
        #expect(QuickEntry.read("coffee 5")?.currency == nil)
        #expect(QuickEntry.read("coffee $5")?.currency == nil)
    }

    /// Absurd or sub-cent amounts are refused rather than rounded.
    @Test func quickEntryRefusesAmountsThatAreNotMoney() {
        #expect(QuickEntry.read("coffee 0.005") == nil)
        #expect(QuickEntry.read("coffee 0") == nil)
        #expect(QuickEntry.read("coffee 1000000") == nil)
        #expect(QuickEntry.read("refund -5") == nil)
        #expect(QuickEntryAI.modelAmount("0.001") == nil)
        #expect(QuickEntryAI.modelAmount("1e5") == nil)
        #expect(QuickEntryAI.modelAmount("999999999999") == nil)
        #expect(QuickEntryAI.modelAmount("-5") == nil)
    }
}

// MARK: - Wallet tap text

struct AbuseWalletTextTests {

    /// A card number is not an amount.
    @Test func aCardNumberIsNotAnAmount() {
        #expect(WalletTapText.money(in: "Card ending 4111 1111 1111 1111") == nil)
        #expect(WalletTapText.money(in: "NAB 4821") == nil)
    }

    /// The real amount is found even with a masked card beside it.
    @Test func theAmountIsFoundBesideACardNumber() {
        #expect(WalletTapText.money(in: "NAB Visa Debit ••4821 A$4.50") == "A$4.50")
        #expect(WalletTapText.money(in: "Seven Seeds SGD 6.20 SC Journey") == "SGD 6.20")
    }

    /// A refund in Wallet text keeps its sign all the way through.
    @Test func aRefundInWalletTextStaysARefund() {
        let hit = WalletTapText.money(in: "Apple Store A$-129.00 NAB Visa Debit")
        #expect(hit != nil)
        #expect(AmountParser.isNegative(hit ?? ""), "the refund sign was lost: \(hit ?? "nil")")
    }
}

// MARK: - Dedupe

@MainActor
struct AbuseDedupeTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func tap(_ ctx: ModelContext, _ merchant: String, _ amount: Decimal, minutes: Double,
                     currency: String = "AUD") throws -> TransactionLogger.Outcome {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60),
                                 merchant: merchant, amount: amount, currency: currency,
                                 card: .nab, source: .tap)
        return try TransactionLogger.log(p, in: ctx)
    }

    /// The same tap arriving twice in a second is one purchase. (Intended.)
    @Test func theSameTapTwiceInASecondIsOnePurchase() throws {
        let ctx = try store()
        _ = try tap(ctx, "Seven Seeds", 4.50, minutes: 0)
        _ = try tap(ctx, "Seven Seeds", 4.50, minutes: 1.0 / 60.0)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    /// Two real payments at the same shop, minutes apart, for the same amount
    /// — two coffees paid separately — are two purchases, not a re-send.
    @Test func twoSeparatePaymentsAtOneShopAreTwoPurchases() throws {
        let ctx = try store()
        _ = try tap(ctx, "Seven Seeds", 4.50, minutes: 0)
        _ = try tap(ctx, "Seven Seeds", 4.50, minutes: 9)
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 2, "the second $4.50 coffee was swallowed as a duplicate")
        #expect(all.audTotal == 9)
    }

    /// The same amount in two different currencies is never the same purchase.
    @Test func sameAmountInAnotherCurrencyIsNotADuplicate() throws {
        let ctx = try store()
        _ = try tap(ctx, "Seven Seeds", 4.50, minutes: 0, currency: "AUD")
        _ = try tap(ctx, "Seven Seeds", 4.50, minutes: 1, currency: "SGD")
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    /// A zero-amount tap is never merged into a real purchase.
    @Test func anAmountlessTapNeverEatsARealPurchase() throws {
        let ctx = try store()
        _ = try tap(ctx, "Seven Seeds", 4.50, minutes: 0)
        _ = try tap(ctx, "Seven Seeds", 0, minutes: 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }
}

// MARK: - Refunds end to end through the tap intent

@MainActor
struct AbuseRefundIntentTests {

    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// A refund tap written the plain way cancels the purchase.
    @Test func aRefundTapCancelsThePurchase() async throws {
        let ctx = store()
        _ = try await LogPurchaseIntent.handle(merchant: "Uniqlo", amount: "A$59.90", card: "NAB Visa Debit",
                                               in: ctx, book: CardBook(), now: start)
        _ = try await LogPurchaseIntent.handle(merchant: "Uniqlo", amount: "-A$59.90", card: "NAB Visa Debit",
                                               in: ctx, book: CardBook(), now: start.addingTimeInterval(3 * 86400))
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1, "the refund was saved as a second row")
        #expect(all.first?.refunded == true)
        #expect(all.audTotal == 0)
    }

    /// The same refund written with the minus after the currency marker.
    /// Today it is read as a purchase, so a refund *raises* the total.
    @Test func aRefundWithTheMinusAfterTheSymbolIsStillARefund() async throws {
        let ctx = store()
        _ = try await LogPurchaseIntent.handle(merchant: "Uniqlo", amount: "A$59.90", card: "NAB Visa Debit",
                                               in: ctx, book: CardBook(), now: start)
        _ = try await LogPurchaseIntent.handle(merchant: "Uniqlo", amount: "A$-59.90", card: "NAB Visa Debit",
                                               in: ctx, book: CardBook(), now: start.addingTimeInterval(3 * 86400))
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.audTotal == 0, "a refund added \(all.audTotal) to the total instead of cancelling it")
    }

    /// The same refund arriving twice must not leave a second, phantom row.
    @Test func theSameRefundTwiceLeavesOneRow() async throws {
        let ctx = store()
        _ = try await LogPurchaseIntent.handle(merchant: "Uniqlo", amount: "A$59.90", card: "NAB Visa Debit",
                                               in: ctx, book: CardBook(), now: start)
        for i in 1...2 {
            _ = try await LogPurchaseIntent.handle(merchant: "Uniqlo", amount: "-A$59.90", card: "NAB Visa Debit",
                                                   in: ctx, book: CardBook(),
                                                   now: start.addingTimeInterval(Double(i) * 86400))
        }
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    /// A mangled amount from Shortcuts must not become a five-figure purchase.
    @Test func aMangledTapAmountIsNotStoredAsMoney() async throws {
        let ctx = store()
        let out = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "4111111111111111",
                                                     card: "NAB Visa Debit", in: ctx, book: CardBook(), now: start)
        let saved = try #require(out.transaction)
        #expect(saved.needsReview || saved.amount < 1_000_000,
                "a tap stored \(saved.amount) with no sanity check")
    }
}
