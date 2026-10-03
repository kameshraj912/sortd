import Testing
import Foundation
@testable import Spend

/// 4 Oct 2026, phone run: budget $2,000, $34.30 spent. Home said "$70 a day",
/// the small Spending widget said "of $65 a day" (budget over the 31 days of
/// the month). Both now come from `WidgetSummary.perDay`.
@MainActor
struct WidgetDailyFigureTests {
    private func melbourne() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return c
    }

    private func at(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func homeAndTheWidgetAgreeOnTheDailyFigure() {
        let cal = melbourne()
        let now = at(cal, 2026, 10, 4, 12)
        let t = Transaction(date: at(cal, 2026, 10, 4, 9), merchant: "Cafe", amount: Decimal(string: "34.30")!,
                            currencyCode: Money.home, card: .nab, category: .eatingOut, source: .manual)

        // What Home's budget line computes: no bills, 28 days left (4 to 31 Oct).
        let home = WidgetSummary.perDay(budget: 2000, spent: Decimal(string: "34.30")!, billsToCome: 0,
                                        now: now, calendar: cal)
        let widget = WidgetBridge.build(from: [t], budget: 2000, now: now, calendar: cal)

        #expect(widget.dayAllowance == home)
        #expect(widget.perDay == home)
        #expect(Money.format(home, Money.home, cents: false) == Money.format(widget.dayAllowance ?? 0, Money.home, cents: false))
        // $1,965.70 over 28 days is about $70, not $2,000 over 31 days ($65).
        #expect((home as NSDecimalNumber).doubleValue.rounded() == 70)
        #expect(widget.dayAllowance != Decimal(2000) / 31)
    }

    @Test func billsStillToChargeComeOffBeforeTheDivision() {
        let cal = melbourne()
        let now = at(cal, 2026, 10, 4, 12)
        let day = WidgetSummary.perDay(budget: 2000, spent: 0, billsToCome: 280, now: now, calendar: cal)
        #expect(day == Decimal(1720) / 28)
    }

    @Test func aUsedUpBudgetLeavesNothingPerDay() {
        let cal = melbourne()
        let now = at(cal, 2026, 10, 4, 12)
        #expect(WidgetSummary.perDay(budget: 100, spent: 100, billsToCome: 0, now: now, calendar: cal) == 0)
        #expect(WidgetSummary.perDay(budget: 100, spent: 150, billsToCome: 0, now: now, calendar: cal) == 0)
    }

    @Test func noBudgetMeansNoAllowance() {
        let cal = melbourne()
        let widget = WidgetBridge.build(from: [], budget: 0, now: at(cal, 2026, 10, 4, 12), calendar: cal)
        #expect(widget.dayAllowance == nil)
        #expect(widget.perDay == nil)
    }
}
