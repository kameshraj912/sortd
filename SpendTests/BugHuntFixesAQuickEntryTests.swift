import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt 3 Oct 2026, fixed on `fix-hunt-a`: Quick entry currencies (M3).
/// Each test failed before its fix. Helpers: `HuntA`.
@MainActor
struct BugHuntFixesAQuickEntryTests {

    private func store() throws -> ModelContext { try HuntA.store() }
    private func date(_ ymd: String, _ hm: String = "12:00") -> Date { HuntA.date(ymd, hm) }
    private func money(_ s: String) -> Decimal { HuntA.money(s) }
    private func calendar(_ id: Calendar.Identifier, _ zone: TimeZone = .current) -> Calendar { HuntA.calendar(id, zone) }
    private func ymd(_ d: Date?) -> String? { HuntA.ymd(d) }

    // MARK: M3. Quick entry currencies

    @Test func quickEntryReadsACodeBeforeTheNumberAndASignAfterIt() {
        #expect(QuickEntry.read("taxi SGD 12.50") == .init(merchant: "Taxi", amount: money("12.50"), currency: "SGD", daysAgo: 0))
        #expect(QuickEntry.read("lunch EUR 12") == .init(merchant: "Lunch", amount: money("12"), currency: "EUR", daysAgo: 0))
        #expect(QuickEntry.read("grab sgd12.50") == .init(merchant: "Grab", amount: money("12.50"), currency: "SGD", daysAgo: 0))
        #expect(QuickEntry.read("cafe 12,50€") == .init(merchant: "Cafe", amount: money("12.50"), currency: "EUR", daysAgo: 0))
        #expect(QuickEntry.read("dinner 350฿") == .init(merchant: "Dinner", amount: money("350"), currency: "THB", daysAgo: 0))
        #expect(QuickEntry.read("dinner ฿350") == .init(merchant: "Dinner", amount: money("350"), currency: "THB", daysAgo: 0))
        #expect(QuickEntry.read("taxi ₱250") == .init(merchant: "Taxi", amount: money("250"), currency: "PHP", daysAgo: 0))
        // Unchanged.
        #expect(QuickEntry.read("coffee 5.50") == .init(merchant: "Coffee", amount: money("5.50"), currency: nil, daysAgo: 0))
        #expect(QuickEntry.read("uber 12 sgd")?.currency == "SGD")
        #expect(QuickEntry.read("7 eleven 4")?.merchant == "7 Eleven")
    }
}
