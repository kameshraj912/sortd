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
}
