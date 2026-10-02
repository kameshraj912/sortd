import Testing
import Foundation
@testable import Spend

/// The widget's numbers across month, day and DST edges. `WidgetBridge.build`
/// mirrors Home's "left of budget · $X a day" line exactly (its own doc
/// comment says so), so these pin both at once without touching any SwiftUI
/// view internals.
///
/// Every purchase is logged in `Money.home` itself (whatever the test
/// process currently has set, as `WidgetSummaryTests` also does): the whole
/// suite shares one `UserDefaults.standard`, so a purchase hardcoded to
/// "AUD" would silently read as 0 (needing a rate) if another suite left
/// the home currency set to something else.
@MainActor
@Suite struct FullBudgetWidgetTests {
    private func melbourne() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return c
    }

    private func singapore() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return c
    }

    private func at(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func spend(_ merchant: String, _ amount: Decimal, _ when: Date) -> Transaction {
        Transaction(date: when, merchant: merchant, amount: amount, currencyCode: Money.home,
                   card: .nab, category: .shopping, source: .manual)
    }

    // MARK: Stale day allowance across a month rollover

    /// `WidgetSummary.asOf` resets `month`, `categories` and `leftThisMonth`
    /// on a new month, but never touches `dayAllowance` (budget ÷ days in
    /// month). February (28 days) rolling into March (31 days) keeps
    /// February's per-day figure until the app is next opened to rebuild it —
    /// a stale number shown as if it were today's.
    @Test
    func dayAllowanceIsRecomputedForTheNewMonth() {
        let cal = melbourne()
        var s = WidgetSummary()
        s.updatedAt = at(cal, 2027, 2, 28, 20, 0)
        s.budget = 280
        s.dayAllowance = 280 / 28   // February: $10/day

        let next = s.asOf(at(cal, 2027, 3, 1, 8, 0), calendar: cal)
        let marchAllowance = (280 as Decimal) / 31
        #expect(next.dayAllowance == marchAllowance,
                "dayAllowance is still February's \(String(describing: next.dayAllowance)), not March's \(marchAllowance)")
    }

    // MARK: Month edges, as a sanity check (not a bug: kept as a regression)

    @Test func aPurchaseSecondsBeforeMidnightStaysInTheOldMonthMelbourne() throws {
        let cal = melbourne()
        let t = spend("Late Shop", 10, at(cal, 2026, 9, 30, 23, 59))
        let s = WidgetBridge.build(from: [t], budget: 0, now: at(cal, 2026, 10, 1, 0, 5), calendar: cal)
        #expect(s.month == 0, "a September purchase must not be in October's month total")
    }

    @Test func aPurchaseAtMidnightStartsTheNewMonthMelbourne() throws {
        let cal = melbourne()
        let t = spend("First of Month", 25, at(cal, 2026, 10, 1, 0, 0))
        let s = WidgetBridge.build(from: [t], budget: 0, now: at(cal, 2026, 10, 1, 0, 5), calendar: cal)
        #expect(s.month == 25)
    }

    /// Melbourne's spring-forward: 2am becomes 3am on 4 Oct 2026. A purchase
    /// logged either side of the gap must still land in the same day and the
    /// same month total, with no lost or doubled hour.
    @Test func springForwardDoesNotLoseOrDoubleTheDaysSpending() throws {
        let cal = melbourne()
        let before = spend("Before", 10, at(cal, 2026, 10, 4, 1, 30))
        let after = spend("After", 20, at(cal, 2026, 10, 4, 3, 30))
        let now = at(cal, 2026, 10, 4, 20, 0)
        let s = WidgetBridge.build(from: [before, after], budget: 0, now: now, calendar: cal)
        #expect(s.today == 30, "both purchases on the DST day must count as today")
    }

    /// Melbourne's autumn fallback: 3am becomes 2am on 5 Apr 2026 (2am–3am
    /// happens twice). Both taps should still be one calendar day.
    @Test func fallBackDoesNotLoseOrDoubleTheDaysSpending() throws {
        let cal = melbourne()
        let first = spend("First 1:30", 5, at(cal, 2026, 4, 5, 1, 30))
        let last = spend("Late", 15, at(cal, 2026, 4, 5, 23, 0))
        let now = at(cal, 2026, 4, 6, 8, 0)
        let s = WidgetBridge.build(from: [first, last], budget: 0, now: now, calendar: cal)
        #expect(s.month == 20)
    }

    /// Singapore has no daylight saving; a purchase at 23:59 on the last day
    /// of the month must not spill into next month's total.
    @Test func lastMinuteOfTheMonthStaysInThatMonthSingapore() throws {
        let cal = singapore()
        let t = spend("Last Minute", 50, at(cal, 2026, 9, 30, 23, 59))
        let s = WidgetBridge.build(from: [t], budget: 0, now: at(cal, 2026, 9, 30, 23, 59), calendar: cal)
        #expect(s.month == 50)
        #expect(s.today == 50)
    }

    // MARK: Budget size edges

    @Test func aTenMillionBudgetStillSplitsCleanlyOverTheDaysLeft() throws {
        let cal = melbourne()
        let now = at(cal, 2026, 9, 15, 18, 0)   // 16 days left of 30
        let t = spend("Big Spend", 2_000_000, at(cal, 2026, 9, 10, 12, 0))
        let s = WidgetBridge.build(from: [t], budget: 10_000_000, now: now, calendar: cal)
        #expect(s.leftThisMonth == Decimal(8_000_000))
        #expect(s.perDay == Decimal(8_000_000) / 16)
    }

    @Test func aOneCentBudgetGoesOverAfterAnyPurchase() throws {
        let cal = melbourne()
        let now = at(cal, 2026, 9, 15, 18, 0)
        let t = spend("Coffee", 0.01, at(cal, 2026, 9, 10, 12, 0))
        let s = WidgetBridge.build(from: [t], budget: 0.01, now: now, calendar: cal)
        #expect(s.leftThisMonth == 0)
        #expect(s.perDay == 0)
    }
}
