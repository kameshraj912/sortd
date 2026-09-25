import Testing
import Foundation
import SwiftData
@testable import Spend

/// `Outcome.line` compares this month's spend so far to last month's spend
/// to the same day, for the Insights "outcome" line.
struct OutcomeTests {
    @Test func spendingLessThanLastMonthByNow() {
        // 880 vs 1000: 12% less.
        #expect(Outcome.line(thisMonth: 880, lastMonthToSameDay: 1000) == "12% less than last month by now")
    }

    @Test func spendingMoreThanLastMonthByNow() {
        // 1080 vs 1000: 8% more.
        #expect(Outcome.line(thisMonth: 1080, lastMonthToSameDay: 1000) == "8% more than last month by now")
    }

    @Test func lastMonthZeroGivesNoLine() {
        #expect(Outcome.line(thisMonth: 200, lastMonthToSameDay: 0) == nil)
    }

    @Test func equalSpendIsAboutTheSame() {
        #expect(Outcome.line(thisMonth: 1000, lastMonthToSameDay: 1000) == "About the same as last month by now")
    }

    @Test func nothingSpentYetGivesNoLine() {
        // Day 1 with nothing spent: "100% less" would be noise.
        #expect(Outcome.line(thisMonth: 0, lastMonthToSameDay: 1000) == nil)
    }
}

/// `Outcome.lastMonthToSameDay` sums last month up to the same day of the
/// month, and never past the end of last month: after a shorter month the
/// first days of this month must not leak in.
@MainActor
struct OutcomeWindowTests {
    let context: ModelContext
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @discardableResult
    private func spend(_ amount: Decimal, on d: Date, category: SpendCategory = .groceries) throws -> Transaction {
        // Home currency, so `audValue` counts it without an exchange rate.
        let p = IncomingPurchase(date: d, merchant: "Shop", amount: amount, currency: Money.home, card: .other,
                                 source: .tap, category: category)
        return try TransactionLogger.log(p, in: context).transaction
    }

    private var all: [Transaction] { (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] }

    @Test func may31AfterAprilCountsAllOfAprilAndNoneOfMay() throws {
        try spend(1000, on: date(2026, 4, 15))
        try spend(200, on: date(2026, 5, 1))
        try spend(800, on: date(2026, 5, 20))

        let last = Outcome.lastMonthToSameDay(all, now: date(2026, 5, 31), calendar: utc)

        #expect(last == 1000)
        #expect(Outcome.line(thisMonth: 1000, lastMonthToSameDay: last) == "About the same as last month by now")
    }

    @Test func march31AfterFebruaryStopsAtTheEndOfFebruary() throws {
        try spend(500, on: date(2026, 2, 28, 23))
        try spend(300, on: date(2026, 3, 1, 0))
        try spend(300, on: date(2026, 3, 2))

        #expect(Outcome.lastMonthToSameDay(all, now: date(2026, 3, 31), calendar: utc) == 500)
    }

    @Test func midMonthCountsOnlyThroughTheSameDayLastMonth() throws {
        try spend(100, on: date(2026, 8, 10, 23))
        try spend(100, on: date(2026, 8, 11, 0))
        try spend(100, on: date(2026, 9, 3))

        #expect(Outcome.lastMonthToSameDay(all, now: date(2026, 9, 10, 8), calendar: utc) == 100)
    }

    @Test func transfersAndRefundsDoNotCount() throws {
        try spend(100, on: date(2026, 8, 5))
        try spend(900, on: date(2026, 8, 5), category: .transfers)
        let refunded = try spend(50, on: date(2026, 8, 6))
        refunded.refunded = true

        #expect(Outcome.lastMonthToSameDay(all, now: date(2026, 9, 10), calendar: utc) == 100)
    }
}
