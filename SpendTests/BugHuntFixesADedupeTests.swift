import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt 3 Oct 2026, fixed on `fix-hunt-a`: A tap on another day is not the hand-typed purchase (D1).
/// Each test failed before its fix. Helpers: `HuntA`.
@MainActor
struct BugHuntFixesADedupeTests {

    private func store() throws -> ModelContext { try HuntA.store() }
    private func date(_ ymd: String, _ hm: String = "12:00") -> Date { HuntA.date(ymd, hm) }
    private func money(_ s: String) -> Decimal { HuntA.money(s) }
    private func calendar(_ id: Calendar.Identifier, _ zone: TimeZone = .current) -> Calendar { HuntA.calendar(id, zone) }
    private func ymd(_ d: Date?) -> String? { HuntA.ymd(d) }

    // MARK: D1. A tap the next day is a new purchase

    /// A hand-typed purchase and an Apple Pay tap both carry the real time.
    /// The 2-day window is for statement rows, which carry only a date; a
    /// tap 24 hours after a hand-typed row at the same shop is a second
    /// purchase, and the first must stay on its own day.
    @Test func aTapTheNextDayDoesNotSwallowAHandTypedPurchase() throws {
        let ctx = try store()
        let monday = date("2026-09-21", "08:00")
        let typed = try TransactionLogger.log(IncomingPurchase(date: monday, merchant: "Starbucks", amount: money("6.50"),
                                                               currency: "AUD", card: .other, source: .manual), in: ctx)
        let tap = try TransactionLogger.log(IncomingPurchase(date: date("2026-09-22", "08:00"), merchant: "Starbucks",
                                                             amount: money("6.50"), currency: "AUD", card: .nab, source: .tap), in: ctx)
        guard case .added = tap else { Issue.record("the tap was merged into Monday's coffee"); return }
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 2)
        #expect(typed.transaction.date == monday)
        #expect(typed.transaction.source == .manual)
    }

    /// The other way round: a tap first, then a purchase typed (or a receipt
    /// scanned) the next day.
    @Test func aHandTypedPurchaseTheNextDayIsNotMergedIntoATap() throws {
        let ctx = try store()
        _ = try TransactionLogger.log(IncomingPurchase(date: date("2026-09-21", "08:00"), merchant: "Starbucks", amount: money("6.50"),
                                                       currency: "AUD", card: .nab, source: .tap), in: ctx)
        let typed = try TransactionLogger.log(IncomingPurchase(date: date("2026-09-22", "08:00"), merchant: "Starbucks",
                                                               amount: money("6.50"), currency: "AUD", card: .other, source: .manual), in: ctx)
        guard case .added = typed else { Issue.record("the typed purchase was merged into yesterday's tap"); return }
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    /// Unchanged: the same day, a hand-typed purchase and its tap are one.
    @Test func aHandTypedPurchaseStillMergesWithItsTapTheSameDay() throws {
        let ctx = try store()
        _ = try TransactionLogger.log(IncomingPurchase(date: date("2026-09-21", "08:00"), merchant: "Starbucks", amount: money("6.50"),
                                                       currency: "AUD", card: .other, source: .manual), in: ctx)
        let tap = try TransactionLogger.log(IncomingPurchase(date: date("2026-09-21", "08:06"), merchant: "Starbucks",
                                                             amount: money("6.50"), currency: "AUD", card: .nab, source: .tap), in: ctx)
        guard case .merged = tap else { Issue.record("the same-day tap was not merged"); return }
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    /// Unchanged: a statement row (a date, no time) still merges with a
    /// hand-typed purchase from the day before, posting lag being normal.
    @Test func aStatementRowStillMergesWithAHandTypedPurchaseFromTheDayBefore() throws {
        let ctx = try store()
        _ = try TransactionLogger.log(IncomingPurchase(date: date("2026-09-21", "08:00"), merchant: "Starbucks", amount: money("6.50"),
                                                       currency: "AUD", card: .other, source: .manual), in: ctx)
        let row = try TransactionLogger.log(IncomingPurchase(date: date("2026-09-22"), merchant: "STARBUCKS CARLTON",
                                                             amount: money("6.50"), currency: "AUD", card: .nab, source: .csv), in: ctx)
        guard case .merged = row else { Issue.record("the statement row was not merged"); return }
    }
}
