import Testing
import Foundation
@testable import Spend

/// `Pace.projectedOverDay` is linear: spend-per-day-so-far, projected across
/// the month, then the first day whole-day spend exceeds the budget. Nudges
/// are capped at once per calendar month.
struct PaceTests {
    @Test func sixHundredOfAThousandByDayTenOfThirtyProjectsPastBudgetOnDaySeventeen() {
        // Rate = 60/day. Day the running total first exceeds 1000: day 17 (1020).
        let day = Pace.projectedOverDay(spent: 600, budget: 1000, day: 10, daysInMonth: 30)
        #expect(day == 17)
    }

    @Test func onPaceToFinishUnderBudgetIsNil() {
        // Rate = 10/day over 30 days = 300, well under 1000.
        let day = Pace.projectedOverDay(spent: 100, budget: 1000, day: 10, daysInMonth: 30)
        #expect(day == nil)
    }

    @Test func zeroBudgetIsNil() {
        let day = Pace.projectedOverDay(spent: 600, budget: 0, day: 10, daysInMonth: 30)
        #expect(day == nil)
    }

    @Test func shouldNudgeIsTrueOncePerMonthThenFalseThenTrueAgainNextMonth() {
        let defaults = UserDefaults(suiteName: "PaceTests.\(UUID().uuidString)")!
        let calendar: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "UTC")!
            return c
        }()
        let sep = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9))!
        let laterInSeptember = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9))!
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))!

        #expect(Pace.shouldNudge(now: sep, defaults: defaults, calendar: calendar))

        Pace.markNudged(now: sep, defaults: defaults, calendar: calendar)
        #expect(!Pace.shouldNudge(now: laterInSeptember, defaults: defaults, calendar: calendar))

        #expect(Pace.shouldNudge(now: october, defaults: defaults, calendar: calendar))
    }
}
