import Testing
import Foundation
@testable import Spend

/// Spec 5's day pager (behind `SPEND_ACTIVITY_DAYS`): the day index from a
/// date, paging back across a month edge, the built window, and where the
/// pager lands when the day on screen goes.
@Suite("DayPager")
struct DayPagerTests {
    let cal = Calendar(identifier: .gregorian)
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day))!
    }

    @Test func indexFromDateByCalendarDay() {
        let days = [d(2026, 9, 25), d(2026, 9, 24), d(2026, 9, 22)]
        #expect(DayPager.dayIndex(for: d(2026, 9, 24), in: days, calendar: cal) == 1)
        // Any time on the day finds its page.
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: d(2026, 9, 22))!
        #expect(DayPager.dayIndex(for: noon, in: days, calendar: cal) == 2)
        #expect(DayPager.dayIndex(for: d(2026, 9, 23), in: days, calendar: cal) == nil)
    }

    @Test func backAcrossAMonthEdge() {
        let days = [d(2026, 9, 1), d(2026, 8, 31), d(2026, 8, 30)]
        #expect(DayPager.day(1, from: d(2026, 9, 1), in: days, calendar: cal) == d(2026, 8, 31))
        #expect(DayPager.day(-1, from: d(2026, 8, 31), in: days, calendar: cal) == d(2026, 9, 1))
        #expect(DayPager.day(-1, from: d(2026, 9, 1), in: days, calendar: cal) == nil)
        #expect(DayPager.day(1, from: d(2026, 8, 30), in: days, calendar: cal) == nil)
    }

    @Test func windowClampsToTheList() {
        #expect(DayPager.window(around: 0, count: 10, reach: 3) == 0..<4)
        #expect(DayPager.window(around: 5, count: 10, reach: 3) == 2..<9)
        #expect(DayPager.window(around: 9, count: 10, reach: 3) == 6..<10)
        #expect(DayPager.window(around: 4, count: 3, reach: 3) == 0..<3)
        #expect(DayPager.window(around: 0, count: 0, reach: 3) == 0..<0)
    }

    @Test func removedDayFallsToItsOlderNeighbour() {
        let old = [d(2026, 9, 25), d(2026, 9, 24), d(2026, 9, 22)]
        let new = [d(2026, 9, 25), d(2026, 9, 22)]
        #expect(DayPager.neighbour(of: d(2026, 9, 24), in: old, still: new) == d(2026, 9, 22))
    }

    @Test func removedOldestDayFallsToItsNewerNeighbour() {
        let old = [d(2026, 9, 25), d(2026, 9, 24), d(2026, 9, 22)]
        let new = [d(2026, 9, 25), d(2026, 9, 24)]
        #expect(DayPager.neighbour(of: d(2026, 9, 22), in: old, still: new) == d(2026, 9, 24))
    }

    @Test func noPageYetOrNothingNearbyGivesTheNewestDay() {
        let new = [d(2026, 9, 25), d(2026, 9, 22)]
        #expect(DayPager.neighbour(of: nil, in: [], still: new) == d(2026, 9, 25))
        #expect(DayPager.neighbour(of: d(2026, 9, 10), in: [d(2026, 9, 10)], still: new) == d(2026, 9, 25))
        #expect(DayPager.neighbour(of: nil, in: [], still: []) == nil)
    }

    @Test func aDayStillShownStays() {
        let days = [d(2026, 9, 25), d(2026, 9, 22)]
        #expect(DayPager.neighbour(of: d(2026, 9, 22), in: days, still: days) == d(2026, 9, 22))
    }
}
