import Testing
import Foundation
@testable import Spend

// The pager is debug-only now (spec 2026-10-03): so are its tests.
#if DEBUG
/// The Activity day pager (`DayPager`) at its edges: no days at all, a huge
/// history (5,000 days, well over 13 years of daily use), and a filter that
/// leaves nothing on screen.
@Suite struct FullBudgetDayPagerTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func days(_ n: Int, from start: Date) -> [Date] {
        (0..<n).map { cal.date(byAdding: .day, value: -$0, to: start)! }
    }

    // MARK: Zero days

    @Test func zeroDaysHasNoWindowAndNoPosition() {
        #expect(DayPager.window(around: 0, count: 0) == 0..<0)
        #expect(DayPager.dayIndex(for: .now, in: [], calendar: cal) == nil)
        #expect(DayPager.neighbour(of: .now, in: [], still: []) == nil)
    }

    // MARK: 5,000 days

    @Test func fiveThousandDaysStillIndexesTheOldestAndNewest() {
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let list = days(5000, from: start)
        #expect(DayPager.dayIndex(for: start, in: list, calendar: cal) == 0)
        #expect(DayPager.dayIndex(for: list.last!, in: list, calendar: cal) == 4999)

        // Window near the far end stays inside the list.
        let w = DayPager.window(around: 4999, count: 5000)
        #expect(w.upperBound <= 5000)
        #expect(w.lowerBound >= 0)

        // Position text for the oldest page.
        #expect(DayPager.position(4999, of: 5000).text == "5000 of 5000")
    }

    @Test func fiveThousandDaysPagesOneDayAtATime() {
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let list = days(5000, from: start)
        let middle = list[2500]
        let older = DayPager.day(1, from: middle, in: list, calendar: cal)
        #expect(older == list[2501])
        let newer = DayPager.day(-1, from: middle, in: list, calendar: cal)
        #expect(newer == list[2499])
    }

    // MARK: A filter that matches nothing

    @Test func aFilterWithNoMatchesLeavesNoNeighbourToLandOn() {
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let old = days(10, from: start)
        // The category filter just changed to one with zero purchases: no
        // days survive at all.
        #expect(DayPager.neighbour(of: old[3], in: old, still: []) == nil)
    }

    @Test func aFilterThatDropsTheCurrentDayLandsOnItsNeighbour() {
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let old = days(10, from: start)
        // old[3] no longer has any matching purchases; old[4] (the older
        // neighbour) still does.
        let new = old.filter { $0 != old[3] }
        #expect(DayPager.neighbour(of: old[3], in: old, still: new) == old[4])
    }
}
#endif
