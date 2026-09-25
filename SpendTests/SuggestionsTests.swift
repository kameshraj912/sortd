import Testing
import Foundation
import SwiftData
@testable import Spend

/// `Suggestions.forNow` ranks merchants from local history for the add
/// sheet: closeness of weekday-and-hour, and recency, with a merchant seen
/// only once never suggested.
@MainActor
struct SuggestionsTests {
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

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func log(_ merchant: String, at d: Date) throws -> Transaction {
        let p = IncomingPurchase(date: d, merchant: merchant, amount: 6.50, currency: "AUD", card: .other, source: .tap)
        return try TransactionLogger.log(p, in: context).transaction
    }

    // Five Tuesday 8 am coffees, Sep 2026.
    private let tuesdays = [1, 8, 15, 22, 29]

    @Test func fiveWeekdayEightAmCoffeesSurfaceThatShopAtTenPastEightOnATuesday() throws {
        var history: [Transaction] = []
        for day in tuesdays {
            history.append(try log("Common Grounds", at: date(2026, 9, day, 8, 0)))
        }
        let expectedCategory = history[0].category
        let now = date(2026, 10, 6, 8, 10) // also a Tuesday

        let suggestions = Suggestions.forNow(history, now: now, calendar: utc)

        #expect(suggestions.first?.merchant == "Common Grounds")
        #expect(suggestions.first?.category == expectedCategory)
    }

    @Test func emptyHistoryGivesNoSuggestions() throws {
        let now = date(2026, 10, 6, 8, 10)
        #expect(Suggestions.forNow([], now: now, calendar: utc).isEmpty)
    }

    @Test func aMerchantSeenOnceIsNotSuggested() throws {
        let now = date(2026, 10, 6, 8, 10)
        let history = [try log("Rare Cafe", at: date(2026, 9, 29, 8, 0))]

        let suggestions = Suggestions.forNow(history, now: now, calendar: utc)

        #expect(!suggestions.contains { $0.merchant == "Rare Cafe" })
    }

    @Test func anEightAmShopOutranksAnEightPmShopWhenNowIsEightTenAm() throws {
        var history: [Transaction] = []
        for day in tuesdays {
            history.append(try log("Common Grounds", at: date(2026, 9, day, 8, 0)))
            history.append(try log("Night Owl Bar", at: date(2026, 9, day, 20, 0)))
        }
        let now = date(2026, 10, 6, 8, 10)

        let suggestions = Suggestions.forNow(history, now: now, calendar: utc)

        #expect(suggestions.first?.merchant == "Common Grounds")
    }
}
