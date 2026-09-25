import Foundation
import SwiftData

/// The Insights "outcome" line: this month against last month to the same
/// day, as a change you can feel ("12% less than last month by now"), not
/// only a total.
enum Outcome {
    /// Nil when last month had nothing to compare with, or nothing has been
    /// spent yet this month (day 1: "100% less" would be noise).
    static func line(thisMonth: Double, lastMonthToSameDay: Double) -> String? {
        guard lastMonthToSameDay > 0, thisMonth > 0 else { return nil }
        let percent = Int(((thisMonth - lastMonthToSameDay) / lastMonthToSameDay * 100).rounded())
        if percent == 0 { return "About the same as last month by now" }
        return "\(abs(percent))% \(percent < 0 ? "less" : "more") than last month by now"
    }

    /// Last month's spend through the same day of the month as `now` (the
    /// whole of that day), and never past the end of last month: on 31 May
    /// it is all of April, with none of May's first days leaking in.
    /// Transfers and refunds do not count, as in `audTotal`.
    static func lastMonthToSameDay(_ transactions: [Transaction], now: Date = .now,
                                   calendar: Calendar = .current) -> Double {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now),
              let lastStart = calendar.date(byAdding: .month, value: -1, to: thisMonth.start) else { return 0 }
        let day = calendar.component(.day, from: now)
        let sameDayEnd = calendar.date(byAdding: .day, value: day, to: lastStart) ?? thisMonth.start
        let end = min(sameDayEnd, thisMonth.start)
        return transactions
            .filter { $0.date >= lastStart && $0.date < end }
            .audTotal.double
    }
}
