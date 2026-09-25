import Foundation

/// Pure helpers for Activity's one-day-per-page mode (`TransactionsScreen.dayPages`).
/// Days are newest first, so paging back in time is a higher index.
enum DayPager {
    /// Pages built either side of the one on screen.
    static let reach = 3

    /// Index of the page holding `date`, by calendar day, in a newest-first list.
    static func dayIndex(for date: Date, in days: [Date], calendar: Calendar = .current) -> Int? {
        days.firstIndex { calendar.isDate($0, inSameDayAs: date) }
    }

    /// The day `delta` pages from `date`: +1 is the next older day (across a
    /// month edge or not), -1 the next newer; nil off either end.
    static func day(_ delta: Int, from date: Date, in days: [Date], calendar: Calendar = .current) -> Date? {
        guard let i = dayIndex(for: date, in: days, calendar: calendar) else { return nil }
        return days.indices.contains(i + delta) ? days[i + delta] : nil
    }

    /// The pages to build: `reach` either side of `index`, clamped to the list.
    static func window(around index: Int, count: Int, reach: Int = reach) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let i = min(max(index, 0), count - 1)
        return max(0, i - reach)..<min(count, i + reach + 1)
    }

    /// Where to go when `current` is no longer a page: the day that sat next
    /// to it in `old` (the older one first, then the newer, then further
    /// out) as long as `new` still has it; else the newest day. A day still
    /// shown stays.
    static func neighbour(of current: Date?, in old: [Date], still new: [Date]) -> Date? {
        guard let current else { return new.first }
        if new.contains(current) { return current }
        guard let i = old.firstIndex(of: current) else { return new.first }
        for step in 1..<max(old.count, 1) {
            for j in [i + step, i - step] where old.indices.contains(j) && new.contains(old[j]) {
                return old[j]
            }
        }
        return new.first
    }
}
