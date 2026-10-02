import Testing
import Foundation
@testable import Spend

/// Subscriptions & bills detection at its edges: how many charges it takes,
/// yearly bills, cancelled subscriptions, month-end dates and big price rises.
@Suite struct FullBudgetBillsTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return c
    }()

    private func day(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = cal.timeZone
        f.calendar = cal
        return f.date(from: s + " 12:00")!
    }

    private func charge(_ d: String, _ merchant: String, _ amount: Decimal,
                        _ cat: SpendCategory = .subscriptions) -> RecurringDetector.Charge {
        .init(date: day(d), merchant: merchant, amount: amount, currency: "AUD", audAmount: amount,
              category: cat, card: .nab, renewsOn: nil, billingPeriod: nil)
    }

    // MARK: Known bug

    /// Netflix goes from 12.99 to 17.99 (a 38% rise). Amounts more than 25%
    /// apart never share a cluster, so the three old charges "win" the
    /// cluster vote and the real, newest charge is thrown away: the bill
    /// shows the old price and, because its predicted date is long past, is
    /// marked lapsed while it is still charging.
    @Test
    func aBigPriceRiseIsStillTheCurrentBill() throws {
        let found = RecurringDetector.detect([
            charge("2026-06-01", "Netflix", 12.99), charge("2026-07-01", "Netflix", 12.99),
            charge("2026-08-01", "Netflix", 12.99), charge("2026-09-01", "Netflix", 17.99),
        ], now: day("2026-09-19"), calendar: cal)
        let bill = try #require(found.first)
        #expect(bill.amount == 17.99, "bill shows \(bill.amount), not the latest charge of 17.99")
        #expect(bill.status == .active, "still charging on 1 Sep, but status is \(bill.status)")
    }

    // MARK: Working cases (regressions)

    @Test func twoMonthlyChargesAreEnoughForASubscription() {
        let found = RecurringDetector.detect([
            charge("2026-08-10", "Disney Plus", 13.99), charge("2026-09-10", "Disney Plus", 13.99),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.cadence == .monthly)
        #expect(found.first?.nextDate == day("2026-10-10"))
    }

    @Test func twoMonthlyVisitsToAShopAreNotABill() {
        let found = RecurringDetector.detect([
            charge("2026-08-10", "Kmart", 20, .shopping), charge("2026-09-10", "Kmart", 20, .shopping),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.isEmpty)
    }

    @Test func aYearlyBillFromTwoChargesAYearApart() {
        let found = RecurringDetector.detect([
            charge("2025-09-01", "Council Rates", 1200, .bills), charge("2026-09-01", "Council Rates", 1200, .bills),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.cadence == .yearly)
        #expect(found.first?.nextDate == day("2027-09-01"))
    }

    @Test func twelveMonthlyChargesStayOneMonthlyBill() {
        var list: [RecurringDetector.Charge] = []
        for m in 1...9 { list.append(charge(String(format: "2026-%02d-05", m), "Gym", 20, .health)) }
        for m in 10...12 { list.append(charge(String(format: "2025-%02d-05", m), "Gym", 20, .health)) }
        let found = RecurringDetector.detect(list, now: day("2026-09-19"), calendar: cal)
        #expect(found.count == 1)
        #expect(found.first?.cadence == .monthly)
        #expect(found.first?.charges == 12)
    }

    @Test func aSubscriptionCancelledAfterItsLastChargeIsCancelledAndNeverUpcoming() {
        let found = RecurringDetector.detect([
            charge("2026-07-10", "Stan", 12), charge("2026-08-10", "Stan", 12), charge("2026-09-10", "Stan", 12),
        ], cancelled: [MerchantName.key("Stan"): day("2026-09-12")], now: day("2026-09-19"), calendar: cal)
        let bill = found.first
        #expect(bill?.status == .cancelled)
        #expect(bill?.chargedAfterCancel == false)
        #expect(bill?.timesDue(before: day("2026-12-31"), calendar: cal) == 0)
        #expect(SpendSummary.upcomingBills(found, hasPurchases: true, now: day("2026-09-19"), calendar: cal)
                == "No bills due in the next 14 days.")
    }

    @Test func aBillOnThe31stRollsToTheEndOfShortMonths() {
        let found = RecurringDetector.detect([
            charge("2026-07-31", "Rent", 900, .housing), charge("2026-08-31", "Rent", 900, .housing),
        ], now: day("2026-09-05"), calendar: cal)
        #expect(found.first?.nextDate == day("2026-09-30"))
    }

    @Test func aWeeklyBillFallsFourOrFiveTimesInAMonth() {
        let found = RecurringDetector.detect([
            charge("2026-09-02", "Meal Box", 50, .subscriptions), charge("2026-09-09", "Meal Box", 50, .subscriptions),
            charge("2026-09-16", "Meal Box", 50, .subscriptions),
        ], now: day("2026-09-17"), calendar: cal)
        // Next charge 23 Sep, then 30 Sep: two more before October.
        #expect(found.first?.timesDue(before: day("2026-10-01"), calendar: cal) == 2)
        #expect(found.stillToCharge(before: day("2026-10-01"), calendar: cal) == 100)
    }
}
