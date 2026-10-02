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

    /// The typed view (`all`) can only hold known categories, so it leaves
    /// the old key out. The stored dictionary must keep it through every
    /// write (set, remove, currency change), so a later version that knows
    /// the key again, or a restore, finds the limit intact.
    @Test
    func aLimitUnderARemovedCategoryIsNotSilentlyLost() {
        let d = defaults()
        d.set(["vacation": 400.0, "groceries": 600.0], forKey: CategoryBudgets.key)

        #expect(CategoryBudgets.all(d) == [.groceries: 600])

        CategoryBudgets.set(120, for: .bills, d)
        CategoryBudgets.remove(.groceries, d)
        #expect(CategoryBudgets.stored(d)["vacation"] == 400, "set/remove dropped the unknown key")

        CategoryBudgets.convert(from: CategoryBudgets.stored(d), rate: 0.5, d)
        #expect(CategoryBudgets.stored(d)["vacation"] == 200, "currency change dropped the unknown key")
        #expect(CategoryBudgets.stored(d)["bills"] == 60)
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
