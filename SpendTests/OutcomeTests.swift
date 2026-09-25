import Testing
import Foundation
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
}
