import Testing
import Foundation
@testable import Spend

/// One line of text into a purchase. The thing this competes with is not
/// another app, it's not bothering — so it has to work on what somebody
/// actually types standing at a counter, including the lazy versions.
struct QuickEntryTests {

    @Test func readsTheObviousCase() throws {
        let r = try #require(QuickEntry.read("coffee 5.50"))
        #expect(r.merchant == "Coffee")
        #expect(r.amount == Decimal(string: "5.50"))
        #expect(r.daysAgo == 0)
    }

    @Test(arguments: [
        "coffee 5.50", "coffee $5.50", "Coffee 5.50", "coffee for 5.50",
        "5.50 coffee", "spent 5.50 at coffee", "coffee 5,50",
    ])
    func readsTheLazyVersions(input: String) throws {
        let r = try #require(QuickEntry.read(input), "failed on: \(input)")
        #expect(r.amount == Decimal(string: "5.50"), "amount wrong for: \(input)")
        #expect(r.merchant.lowercased().contains("coffee"), "merchant wrong for: \(input)")
    }

    @Test func readsThousandsWithACommaAndDecimalCommas() throws {
        // Bug-hunt M7: "laptop 1,299" became $9 at "Laptop 1 29".
        #expect(QuickEntry.read("rent 1,200")?.amount == 1200)
        let laptop = try #require(QuickEntry.read("laptop 1,299"))
        #expect(laptop.amount == 1299)
        #expect(laptop.merchant.lowercased() == "laptop")
        #expect(QuickEntry.read("coffee 4,50")?.amount == Decimal(string: "4.50"))
    }

    @Test func keepsMultiWordNames() throws {
        let r = try #require(QuickEntry.read("seven seeds coffee 5.50"))
        #expect(r.merchant == "Seven Seeds Coffee")
    }

    @Test func leavesNamesThatAreAlreadyCapitalised() throws {
        #expect(QuickEntry.read("KFC 12")?.merchant == "KFC")
        #expect(QuickEntry.read("McDonald's 8.50")?.merchant == "McDonald's")
    }

    @Test func aNameWithDigitsKeepsThem() throws {
        // The last number is the amount, so "7 Eleven" survives.
        let r = try #require(QuickEntry.read("7 eleven 4.50"))
        #expect(r.amount == Decimal(string: "4.50"))
        #expect(r.merchant.lowercased().contains("eleven"))
    }

    @Test func readsWholeNumbers() throws {
        let r = try #require(QuickEntry.read("lunch 20"))
        #expect(r.amount == Decimal(20))
        #expect(r.merchant == "Lunch")
    }

    // MARK: Currency

    @Test func picksUpAWrittenCurrency() throws {
        #expect(QuickEntry.read("lunch S$12.50")?.currency == "SGD")
        #expect(QuickEntry.read("lunch 12.50 sgd")?.currency == "SGD")
        #expect(QuickEntry.read("lunch RM45")?.currency == "MYR")
        #expect(QuickEntry.read("lunch A$12.50")?.currency == "AUD")
    }

    @Test func aPlainDollarSignSaysNothingAboutCurrency() throws {
        // "$" means five different things depending on where you are, so
        // the app's own setting decides rather than a guess.
        #expect(QuickEntry.read("lunch $12.50")?.currency == nil)
        #expect(QuickEntry.read("lunch 12.50")?.currency == nil)
    }

    // MARK: When

    @Test func understandsYesterday() throws {
        let r = try #require(QuickEntry.read("coffee 5.50 yesterday"))
        #expect(r.daysAgo == 1)
        #expect(r.merchant == "Coffee")
    }

    @Test func theDateWordNeverEndsUpInTheName() throws {
        #expect(QuickEntry.read("yesterday coffee 5.50")?.merchant == "Coffee")
        #expect(QuickEntry.read("last night uber 24")?.merchant == "Uber")
        #expect(QuickEntry.read("lunch today 18")?.merchant == "Lunch")
    }

    @Test func dayBeforeYesterdayIsTwo() throws {
        #expect(QuickEntry.read("coffee 5.50 day before yesterday")?.daysAgo == 2)
    }

    // MARK: Refusing

    @Test func nothingUsefulGivesNothing() {
        #expect(QuickEntry.read("") == nil)
        #expect(QuickEntry.read("   ") == nil)
        #expect(QuickEntry.read("coffee") == nil, "no amount")
        #expect(QuickEntry.read("5.50") == nil, "no merchant")
        #expect(QuickEntry.read("yesterday") == nil)
    }

    @Test func zeroIsNotAPurchase() {
        #expect(QuickEntry.read("coffee 0") == nil)
        #expect(QuickEntry.read("coffee 0.00") == nil)
    }

    @Test func fillerWordsAloneAreNotAMerchant() {
        #expect(QuickEntry.read("at 5.50") == nil)
        #expect(QuickEntry.read("spent 5.50 on") == nil)
    }

    @Test func aCurrencySymbolInsideAWordIsNotACurrency() throws {
        // "farm 5" used to read as RM 5 (Malaysian ringgit).
        let r = try #require(QuickEntry.read("coffee at the farm 5"))
        #expect(r.currency == nil)
        #expect(r.amount == 5)
        #expect(QuickEntry.read("nasi lemak RM 8")?.currency == "MYR")
    }

    @Test func readsWeekdaysAndDaysAgo() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        // Tuesday 22 September 2026.
        let tue = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12)))
        #expect(QuickEntry.relativeDay(in: "nandos last friday", today: tue, calendar: cal)?.days == 4)
        #expect(QuickEntry.relativeDay(in: "uber on mon", today: tue, calendar: cal)?.days == 1)
        #expect(QuickEntry.relativeDay(in: "coffee tuesday", today: tue, calendar: cal)?.days == 0)
        #expect(QuickEntry.relativeDay(in: "coffee last tuesday", today: tue, calendar: cal)?.days == 7)
        #expect(QuickEntry.relativeDay(in: "parking 3 days ago", today: tue, calendar: cal)?.days == 3)
        // The 3 in "3 days ago" is not the amount.
        let r = try #require(QuickEntry.read("parking 12 3 days ago"))
        #expect(r.amount == 12)
        #expect(r.daysAgo == 3)
        // "Sunday Market" style names still read (a weekday word is not always a date,
        // but the purchase and amount must survive either way).
        #expect(QuickEntry.read("sunday market 8")?.amount == 8)
    }

    // MARK: Review bugs (Sep 2026) — each failed on the old reader

    @Test func aDateLikeThreeSlashNineIsNotTheAmount() throws {
        // Was read as 9.
        let r = try #require(QuickEntry.read("coffee 5 3/9"))
        #expect(r.amount == 5)
        #expect(r.merchant == "Coffee")
    }

    @Test func aNumberInsideAHyphenatedNameIsNotTheAmount() throws {
        // Was read as 7.
        let r = try #require(QuickEntry.read("coffee 4.50 at 7-eleven"))
        #expect(r.amount == Decimal(string: "4.50"))
        #expect(r.merchant.lowercased().contains("7-eleven"))
        #expect(QuickEntry.read("7-eleven 5")?.amount == 5)
    }

    @Test func aNumberGluedToLettersIsNotTheAmount() throws {
        let r = try #require(QuickEntry.read("apples 2kg 6"))
        #expect(r.amount == 6)
    }

    @Test func aNumberWrittenLikeMoneyBeatsABareOne() throws {
        #expect(QuickEntry.read("2 coffees 9.50")?.amount == Decimal(string: "9.50"))
        #expect(QuickEntry.read("$12 lunch 2")?.amount == 12)
        // Two bare numbers: the last one, as before.
        #expect(QuickEntry.read("2 coffees 9")?.amount == 9)
    }

    @Test func kMeansThousands() throws {
        // Was read as 5.
        #expect(QuickEntry.read("coffee 5k")?.amount == 5000)
        #expect(QuickEntry.read("rent 1.2k")?.amount == 1200)
    }

    @Test func aMinusIsRefusedNotFlipped() {
        // Was read as 5 at "Refund -".
        #expect(QuickEntry.read("refund -5") == nil)
        #expect(QuickEntry.read("refund -$5") == nil)
        #expect(QuickEntry.hasNegativeAmount(in: "refund -5"))
        #expect(!QuickEntry.hasNegativeAmount(in: "7-eleven 5"))
    }

    @Test func dateWordsOnlyMatchWholeWords() throws {
        // Was "S Florist": "today" was cut out of "todays".
        let r = try #require(QuickEntry.read("todays florist 20"))
        #expect(r.merchant == "Todays Florist")
        #expect(r.daysAgo == 0)
    }

    @Test func aWeekdayInsideAShopNameIsNotADate() throws {
        // Was "Ruby", dated Tuesday.
        let r = try #require(QuickEntry.read("ruby tuesday 30"))
        #expect(r.merchant == "Ruby Tuesday")
        #expect(r.amount == 30)
        #expect(r.daysAgo == 0)
        #expect(QuickEntry.relativeDay(in: "ruby tuesday 30") == nil)
        // At the end of the line, or after on/last, it is still a date.
        #expect(QuickEntry.relativeDay(in: "coffee 5 tuesday") != nil)
        #expect(QuickEntry.relativeDay(in: "lunch on tuesday 20") != nil)
    }

    @Test func hugeAmountsAreRefused() {
        // "coffee 99999999999999999999" crashed the Add form.
        #expect(QuickEntry.read("coffee 99999999999999999999") == nil)
        #expect(QuickEntry.read("car 1000000") == nil)
        #expect(QuickEntry.read("car 999999")?.amount == 999_999)
        #expect(QuickEntry.read("coffee 5000k") == nil)
    }

    @Test func fieldTextKeepsCentsAndNeverOverflows() {
        #expect(QuickEntry.fieldText(Decimal(string: "5.50")!) == "5.50")
        #expect(QuickEntry.fieldText(Decimal(string: "5.5")!) == "5.50")
        #expect(QuickEntry.fieldText(20) == "20")
        #expect(QuickEntry.fieldText(Decimal(string: "1299")!) == "1299")
        #expect(QuickEntry.fieldText(Decimal(string: "99999999999999999999")!) == "99999999999999999999")
    }

    @Test func daysAgoSaysWhetherTheLineNamedATime() {
        #expect(QuickEntry.daysAgo(in: "coffee 5") == nil)
        #expect(QuickEntry.daysAgo(in: "coffee 5 today") == 0)
        #expect(QuickEntry.daysAgo(in: "coffee 5 this morning") == 0)
        #expect(QuickEntry.daysAgo(in: "coffee 5 yesterday") == 1)
        #expect(QuickEntry.daysAgo(in: "todays florist 20") == nil)
    }
}
