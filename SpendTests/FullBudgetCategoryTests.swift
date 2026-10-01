import Testing
import Foundation
@testable import Spend

/// Category budgets are keyed by `SpendCategory.rawValue` in UserDefaults.
/// `CategoryBudgets.all` silently drops any key that is no longer a known
/// `SpendCategory` case — which is exactly what happens to a limit set for a
/// category that gets renamed or removed in a later version. The money
/// figure is still sitting in the defaults dictionary (nothing crashes), but
/// nobody is ever told: the limit just isn't there any more, with no
/// migration and no "we removed your Travel limit" message.
@Suite struct FullBudgetCategoryTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "FullBudgetCategoryTests.\(UUID().uuidString)")!
    }

    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a limit under an unknown (renamed/removed) category rawValue silently disappears"))
    func aLimitUnderARemovedCategoryIsNotSilentlyLost() {
        let d = defaults()
        // Simulates a limit that was set while "vacation" existed as a
        // category rawValue, before it was renamed to "travel".
        d.set(["vacation": 400.0, "groceries": 600.0], forKey: CategoryBudgets.key)

        let all = CategoryBudgets.all(d)
        // The still-valid one is fine...
        #expect(all[.groceries] == 600)
        // ...but the renamed one's money is nowhere to be found: not under
        // any current category, and not surfaced as needing attention.
        #expect(all.values.contains(400),
                "a $400 limit set before a category was renamed must still show up somewhere, not vanish")
    }

    /// A limit for a category with no spending this month: progress should
    /// still be reported (0 spent, full amount left), not skipped.
    @Test func aCategoryWithNoSpendingStillShowsFullProgress() {
        let cal: Calendar = {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
        }()
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!
        let progress = CategoryBudgets.progress(for: [], limits: [.travel: 500], now: now, calendar: cal)
        #expect(progress[.travel]?.spent == 0)
        #expect(progress[.travel]?.left == 500)
        #expect(progress[.travel]?.status == .ok)
    }
}
