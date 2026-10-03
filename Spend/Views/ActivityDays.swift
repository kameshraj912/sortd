import Foundation
import SwiftData

/// Pure helpers behind Activity's one scrolling list (`TransactionsScreen`):
/// which purchases show, how they fall into days, and where "Go to Date…"
/// lands. No Views and no store reads, so it is tested with plain arrays.
enum ActivityDays {
    /// One day's section: the calendar day and its purchases, newest first.
    struct Day: Identifiable {
        /// The start of the day, in the calendar the list was grouped with.
        let date: Date
        let items: [Transaction]
        var id: Date { date }
        /// The header's total: AUD, transfers left out (`audTotal`, the
        /// same rule as every other total in the app).
        var total: Decimal { items.audTotal }
    }

    /// The purchases the list shows: inside the card's own list when
    /// `fixedCard` is set, matching the card and category filters and the
    /// search (`SearchText.matcher`), and not swiped away waiting on Undo
    /// (`hidden`). Order is kept.
    static func visible(_ all: [Transaction],
                        fixedCard: Card? = nil,
                        card: Card? = nil,
                        category: SpendCategory? = nil,
                        search: String = "",
                        hidden: Set<PersistentIdentifier> = []) -> [Transaction] {
        let matchesSearch = SearchText.matcher(for: search)
        return all.filter { t in
            !hidden.contains(t.persistentModelID)
            && (fixedCard == nil || t.card == fixedCard)
            && (card == nil || t.card == card)
            && (category == nil || t.category == category)
            && matchesSearch(t)
        }
    }

    /// One section per calendar day, newest day first, newest purchase
    /// first inside each day. 23:59 and 00:01 are two days.
    static func group(_ items: [Transaction], calendar: Calendar = .current) -> [Day] {
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            Day(date: day, items: (groups[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    /// Where "Go to Date…" scrolls in `days` (newest first): the picked day
    /// when it has purchases, else the nearest older day that does. A date
    /// after the newest day lands on the newest; one before the oldest
    /// lands on the oldest. Nil only when there are no days at all.
    static func target(for date: Date, in days: [Date], calendar: Calendar = .current) -> Date? {
        let picked = calendar.startOfDay(for: date)
        if let same = days.first(where: { calendar.isDate($0, inSameDayAs: picked) }) { return same }
        return days.first { calendar.startOfDay(for: $0) < picked } ?? days.last
    }
}
