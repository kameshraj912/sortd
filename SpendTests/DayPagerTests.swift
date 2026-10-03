import Testing
import Foundation
@testable import Spend

// The pager is debug-only now (spec 2026-10-03): so are its tests.
#if DEBUG
/// Spec 5's day pager (DEBUG `SPEND_ACTIVITY_PAGER=1` only since 3 Oct
/// 2026): the day index from a date, paging back across a month edge, the
/// built window, where the pager lands when the day on screen goes, and
/// that one swipe is one day.
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

    // MARK: One swipe is one day (UI pass P2: a fast swipe once skipped a day)

    @Test func aSwipeToTheNextDayLandsThere() {
        let days = [d(2026, 9, 25), d(2026, 9, 24), d(2026, 9, 22), d(2026, 9, 20)]
        #expect(DayPager.settle(d(2026, 9, 24), from: d(2026, 9, 25), in: days, calendar: cal) == d(2026, 9, 24))
        #expect(DayPager.settle(d(2026, 9, 25), from: d(2026, 9, 24), in: days, calendar: cal) == d(2026, 9, 25))
        // Staying put is fine too.
        #expect(DayPager.settle(d(2026, 9, 24), from: d(2026, 9, 24), in: days, calendar: cal) == d(2026, 9, 24))
    }

    @Test func aSwipeTwoDaysAwaySettlesOnTheAdjacentDay() {
        let days = [d(2026, 9, 25), d(2026, 9, 24), d(2026, 9, 22), d(2026, 9, 20)]
        // Older: skipped 24 Sep, lands on it.
        #expect(DayPager.settle(d(2026, 9, 22), from: d(2026, 9, 25), in: days, calendar: cal) == d(2026, 9, 24))
        #expect(DayPager.settle(d(2026, 9, 20), from: d(2026, 9, 25), in: days, calendar: cal) == d(2026, 9, 24))
        // Newer: the same the other way.
        #expect(DayPager.settle(d(2026, 9, 25), from: d(2026, 9, 20), in: days, calendar: cal) == d(2026, 9, 22))
    }

    @Test func aSwipeWithNoDayOnScreenOrAnUnknownDayIsTakenAsIs() {
        let days = [d(2026, 9, 25), d(2026, 9, 22)]
        #expect(DayPager.settle(d(2026, 9, 22), from: nil, in: days, calendar: cal) == d(2026, 9, 22))
        // The day on screen just went (a filter): nothing to be adjacent to.
        #expect(DayPager.settle(d(2026, 9, 22), from: d(2026, 9, 24), in: days, calendar: cal) == d(2026, 9, 22))
    }

    @Test func positionReadsAsOneOfCount() {
        let p = DayPager.position(1, of: 14)
        #expect(p.text == "2 of 14")
        #expect(p.spoken == "day 2 of 14")
        #expect(DayPager.position(0, of: 1).text == "1 of 1")
    }
}
#endif
