import Testing
import Foundation
@testable import Spend

/// Pure "should celebrate" logic for confetti: a finished month that closed
/// under budget, and the first Apple Pay tap ever. No UserDefaults, no
/// store — just dates, decimals and a set of what's already been shown.
struct CelebrationsTests {
    private let cal = Calendar(identifier: .gregorian)

    private func at(_ ymd: String, _ hm: String = "12:00") -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        f.calendar = cal
        return f.date(from: "\(ymd) \(hm)")!
    }

    @Test func monthKeyFormatsYearAndMonth() {
        #expect(Celebrations.monthKey(at("2026-08-15"), calendar: cal) == "2026-08")
        #expect(Celebrations.monthKey(at("2026-01-03"), calendar: cal) == "2026-01")
    }

    @Test func celebratesAFinishedMonthUnderBudget() {
        let now = at("2026-09-05")           // opened the app early in September
        let august = at("2026-08-15")        // the month that just finished
        let result = Celebrations.shouldCelebrateBudgetWin(
            finishedMonthTotal: 800, budget: 1000, now: now, finishedMonth: august,
            alreadyCelebrated: [], calendar: cal)
        #expect(result)
    }

    @Test func celebratesWhenSpendingExactlyHitsBudget() {
        // "Under" includes landing right on it — the app never overspent.
        let now = at("2026-09-05")
        let august = at("2026-08-15")
        let result = Celebrations.shouldCelebrateBudgetWin(
            finishedMonthTotal: 1000, budget: 1000, now: now, finishedMonth: august,
            alreadyCelebrated: [], calendar: cal)
        #expect(result)
    }

    @Test func noCelebrationWithoutABudgetSet() {
        let now = at("2026-09-05")
        let august = at("2026-08-15")
        let result = Celebrations.shouldCelebrateBudgetWin(
            finishedMonthTotal: 50, budget: 0, now: now, finishedMonth: august,
            alreadyCelebrated: [], calendar: cal)
        #expect(!result)
    }

    @Test func noCelebrationForTheStillOpenMonth() {
        // "Finished month" is the same month the app is opened in: not over yet.
        let now = at("2026-08-20")
        let sameMonth = at("2026-08-05")
        let result = Celebrations.shouldCelebrateBudgetWin(
            finishedMonthTotal: 100, budget: 1000, now: now, finishedMonth: sameMonth,
            alreadyCelebrated: [], calendar: cal)
        #expect(!result)
    }

    @Test func noCelebrationForAMonthThatHasNotStarted() {
        let now = at("2026-08-01")
        let future = at("2026-09-15")
        let result = Celebrations.shouldCelebrateBudgetWin(
            finishedMonthTotal: 0, budget: 1000, now: now, finishedMonth: future,
            alreadyCelebrated: [], calendar: cal)
        #expect(!result)
    }

    @Test func noCelebrationWhenOverBudget() {
        let now = at("2026-09-05")
        let august = at("2026-08-15")
        let result = Celebrations.shouldCelebrateBudgetWin(
            finishedMonthTotal: 1200, budget: 1000, now: now, finishedMonth: august,
            alreadyCelebrated: [], calendar: cal)
        #expect(!result)
    }

    @Test func noCelebrationWhenAlreadyShown() {
        let now = at("2026-09-05")
        let august = at("2026-08-15")
        let result = Celebrations.shouldCelebrateBudgetWin(
            finishedMonthTotal: 800, budget: 1000, now: now, finishedMonth: august,
            alreadyCelebrated: ["2026-08"], calendar: cal)
        #expect(!result)
    }

    @Test func stillCelebratesADifferentMonthAfterOneWasShown() {
        let now = at("2026-10-05")
        let september = at("2026-09-15")
        let result = Celebrations.shouldCelebrateBudgetWin(
            finishedMonthTotal: 400, budget: 1000, now: now, finishedMonth: september,
            alreadyCelebrated: ["2026-08"], calendar: cal)
        #expect(result)
    }

    // MARK: First tap

    @Test func celebratesTheFirstTapOnce() {
        #expect(Celebrations.shouldCelebrateFirstTap(hasTapTransaction: true, alreadyCelebrated: false))
        #expect(!Celebrations.shouldCelebrateFirstTap(hasTapTransaction: true, alreadyCelebrated: true))
        #expect(!Celebrations.shouldCelebrateFirstTap(hasTapTransaction: false, alreadyCelebrated: false))
    }

    // MARK: Flags (isolated UserDefaults, never leaks between tests)

    private func defaults() -> UserDefaults {
        let name = "CelebrationsTests-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func firstTapFlagStartsUnsetAndLatches() {
        let d = defaults()
        #expect(!CelebrationFlags.firstTapCelebrated(d))
        CelebrationFlags.markFirstTapCelebrated(d)
        #expect(CelebrationFlags.firstTapCelebrated(d))
    }

    @Test func budgetMonthFlagsAccumulate() {
        let d = defaults()
        #expect(CelebrationFlags.celebratedBudgetMonths(d).isEmpty)
        CelebrationFlags.markBudgetMonthCelebrated("2026-08", d)
        CelebrationFlags.markBudgetMonthCelebrated("2026-09", d)
        #expect(CelebrationFlags.celebratedBudgetMonths(d) == ["2026-08", "2026-09"])
    }
}
