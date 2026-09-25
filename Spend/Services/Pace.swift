import Foundation

/// "On track to pass your budget by the 22nd": a straight-line projection
/// of this month's spend so far, and a once-a-month cap on telling you.
enum Pace {
    /// Where the once-a-month record lives: "2026-09" once nudged.
    static let nudgedKey = "paceNudgeMonth"

    /// The first day of the month on which spend, at today's rate, passes
    /// the budget. Nil when there is no budget, nothing spent yet, the
    /// budget is already passed (Home says so in its own words), or the
    /// month ends under budget.
    static func projectedOverDay(spent: Double, budget: Double, day: Int, daysInMonth: Int) -> Int? {
        guard budget > 0, spent > 0, day > 0, daysInMonth > 0, spent < budget else { return nil }
        let rate = spent / Double(day)
        // Day d has spent rate * d; the first d where that is over the budget.
        let over = Int((budget / rate).rounded(.down)) + 1
        guard over > day, over <= daysInMonth else { return nil }
        return over
    }

    /// The same, for a date: day of month and days in that month from `calendar`.
    static func projectedOverDay(spent: Double, budget: Double, now: Date = .now,
                                 calendar: Calendar = .current) -> Int? {
        let day = calendar.component(.day, from: now)
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return projectedOverDay(spent: spent, budget: budget, day: day, daysInMonth: days)
    }

    /// "On track to pass your budget by the 22nd".
    static func line(day: Int) -> String {
        "On track to pass your budget by the \(ordinal(day))"
    }

    /// "1st", "22nd".
    static func ordinal(_ day: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = Locale(identifier: "en_AU")
        return f.string(from: NSNumber(value: day)) ?? "\(day)"
    }

    static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// True until `markNudged` has run this calendar month.
    static func shouldNudge(now: Date = .now, defaults: UserDefaults = .standard,
                            calendar: Calendar = .current) -> Bool {
        defaults.string(forKey: nudgedKey) != monthKey(now, calendar: calendar)
    }

    static func markNudged(now: Date = .now, defaults: UserDefaults = .standard,
                           calendar: Calendar = .current) {
        defaults.set(monthKey(now, calendar: calendar), forKey: nudgedKey)
    }
}
