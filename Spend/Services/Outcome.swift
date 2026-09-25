import Foundation

/// The Insights "outcome" line: this month against last month to the same
/// day, as a change you can feel ("12% less than last month by now"), not
/// only a total.
enum Outcome {
    /// Nil when last month had nothing to compare with.
    static func line(thisMonth: Double, lastMonthToSameDay: Double) -> String? {
        guard lastMonthToSameDay > 0 else { return nil }
        let percent = Int(((thisMonth - lastMonthToSameDay) / lastMonthToSameDay * 100).rounded())
        if percent == 0 { return "About the same as last month by now" }
        return "\(abs(percent))% \(percent < 0 ? "less" : "more") than last month by now"
    }
}
