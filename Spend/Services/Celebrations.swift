import Foundation

/// Decides when a small win earns confetti: the first Apple Pay tap ever
/// logged, and a finished month that closed under the monthly budget.
/// Kept pure (no UserDefaults, no clock but `now`) so the "should celebrate"
/// calls can be unit tested without a store or a view.
enum Celebrations {
    /// "2026-08", used both to group a month and as the "already
    /// celebrated" flag stored in UserDefaults.
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// True once, the first time the app is opened after a month has fully
    /// finished under budget. `finishedMonth` is any date inside the month
    /// being checked (usually the previous calendar month from `now`).
    ///
    /// Won't fire: with no budget set, for the current (still-open) month or
    /// a month that hasn't started yet, for a month already in
    /// `alreadyCelebrated`, or when spending was at or over budget.
    static func shouldCelebrateBudgetWin(finishedMonthTotal: Decimal,
                                          budget: Double,
                                          now: Date,
                                          finishedMonth: Date,
                                          alreadyCelebrated: Set<String>,
                                          calendar: Calendar = .current) -> Bool {
        guard budget > 0 else { return false }
        // The month must actually be over: not the month `now` is in, and
        // not a future month.
        guard !calendar.isDate(now, equalTo: finishedMonth, toGranularity: .month) else { return false }
        guard let finishedEnd = calendar.dateInterval(of: .month, for: finishedMonth)?.end, now >= finishedEnd else { return false }
        guard finishedMonthTotal <= Decimal(budget) else { return false }
        return !alreadyCelebrated.contains(monthKey(finishedMonth, calendar: calendar))
    }

    /// True once: a tap-sourced purchase exists and the first-tap moment
    /// hasn't been celebrated yet. Can be checked from Onboarding (the
    /// "Connected" moment) or from Home (a tap arriving after onboarding
    /// was skipped) — whichever sees it first wins; the flag stops the other.
    static func shouldCelebrateFirstTap(hasTapTransaction: Bool, alreadyCelebrated: Bool) -> Bool {
        hasTapTransaction && !alreadyCelebrated
    }
}

/// UserDefaults-backed "already celebrated" flags, so confetti never repeats.
enum CelebrationFlags {
    private static let firstTapKey = "celebratedFirstTap"
    private static let budgetMonthsKey = "celebratedBudgetMonths"

    static func firstTapCelebrated(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: firstTapKey)
    }

    static func markFirstTapCelebrated(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: firstTapKey)
    }

    static func celebratedBudgetMonths(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: budgetMonthsKey) ?? [])
    }

    static func markBudgetMonthCelebrated(_ key: String, _ defaults: UserDefaults = .standard) {
        var months = celebratedBudgetMonths(defaults)
        months.insert(key)
        defaults.set(Array(months), forKey: budgetMonthsKey)
    }

    #if DEBUG
    /// Testing/demo only: clears both flags so confetti can be triggered again.
    static func resetAll(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: firstTapKey)
        defaults.removeObject(forKey: budgetMonthsKey)
    }
    #endif
}
