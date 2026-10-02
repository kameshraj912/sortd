import Testing
import Foundation
@testable import Spend

/// Category limits and their alerts, plus the pace line, at the edges.
@Suite struct FullBudgetLimitsTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "FullBudgetLimitsTests.\(UUID().uuidString)")!
    }

    // MARK: Known bugs

    /// The monthly budget refuses anything over 1,000,000 (`BudgetSheet`),
    /// but the category limit sheet saves whatever digits were typed.
    @Test
    func aCategoryLimitIsCappedLikeTheMonthlyBudget() {
        let d = defaults()
        let saved = CategoryLimitSheet.apply("99999999999999999999", to: .bills, d)
        #expect((saved ?? 0) <= BudgetSheet.maxBudget(), "saved a limit of \(String(describing: saved))")
    }

    /// "Near" fired at 90 of 100. The person then raises the limit to 1,000
    /// and spends 950: they are near the new limit, but the alert record is
    /// keyed by month and category only, so the 80% alert never fires again.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("raising a category limit does not re-arm its near/over alerts for the month"))
    func aRaisedLimitCanAlertAgain() {
        let first = CategoryBudgets.dueAlerts([.travel: .init(spent: 90, limit: 100)], month: "2026-09", sent: [])
        #expect(first.alerts.count == 1)
        let second = CategoryBudgets.dueAlerts([.travel: .init(spent: 950, limit: 1000)], month: "2026-09",
                                               sent: first.sent)
        #expect(second.alerts.count == 1, "no alert at 95% of the new 1,000 limit")
    }

    // MARK: Working cases

    @Test func eachAlertFiresOncePerMonthAndRearmsNextMonth() {
        let p: [SpendCategory: CategoryBudgets.Progress] = [.travel: .init(spent: 85, limit: 100)]
        let a = CategoryBudgets.dueAlerts(p, month: "2026-09", sent: [])
        #expect(a.alerts.map(\.threshold) == [.near])
        #expect(CategoryBudgets.dueAlerts(p, month: "2026-09", sent: a.sent).alerts.isEmpty)
        #expect(CategoryBudgets.dueAlerts(p, month: "2026-10", sent: a.sent).alerts.count == 1)
    }

    @Test func crossingBothAtOnceSendsOnlyTheOverAlert() {
        let r = CategoryBudgets.dueAlerts([.travel: .init(spent: 150, limit: 100)], month: "2026-09", sent: [])
        #expect(r.alerts.map(\.threshold) == [.over])
        #expect(r.sent.count == 2)
    }

    @Test func exactlyAtTheLimitIsNearNotOver() {
        let p = CategoryBudgets.progress(spent: 100, limit: 100)
        #expect(p.status == .near)
        #expect(p.left == 0)
        #expect(CategoryBudgets.progress(spent: 100.01, limit: 100).status == .over)
    }

    @Test func aZeroLimitIsRemovedNotStored() {
        let d = defaults()
        CategoryBudgets.set(50, for: .bills, d)
        CategoryBudgets.set(0, for: .bills, d)
        #expect(CategoryBudgets.limit(for: .bills, d) == nil)
        #expect(CategoryLimitSheet.apply("0", to: .bills, d) == nil)
    }

    @Test func aOneCentLimitIsKept() {
        let d = defaults()
        #expect(CategoryLimitSheet.apply("0.01", to: .bills, d) == 0.01)
    }

    @Test func ordinalsReadRightForTeensAndLastDays() {
        #expect(Pace.ordinal(1) == "1st")
        #expect(Pace.ordinal(11) == "11th")
        #expect(Pace.ordinal(12) == "12th")
        #expect(Pace.ordinal(13) == "13th")
        #expect(Pace.ordinal(22) == "22nd")
        #expect(Pace.ordinal(31) == "31st")
    }

    @Test func noPaceLineOnTheLastDayOrWhenAlreadyAtBudget() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let lastDay = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        #expect(Pace.projectedOverDay(spent: 900, budget: 1000, now: lastDay, calendar: cal) == nil)
        #expect(Pace.projectedOverDay(spent: 1000, budget: 1000, day: 20, daysInMonth: 31) == nil)
    }
}
