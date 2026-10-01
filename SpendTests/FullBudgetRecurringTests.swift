import Testing
import Foundation
@testable import Spend

/// Bills and subscriptions: `RecurringDetector.detect` groups every charge by
/// merchant name alone (no card, no amount check) before it looks for a
/// cadence. Two genuinely separate recurring payments at one shop — a family
/// member's plan on another card, or two different subscriptions that happen
/// to share a display name — can therefore collide into a single merchant
/// group, and `mainCluster` keeps only the bigger (or more recent) cluster.
@Suite struct FullBudgetRecurringTests {
    private let cal = Calendar(identifier: .gregorian)

    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: s)!
    }

    private func charge(_ d: String, _ merchant: String, _ amount: Decimal,
                        _ cat: SpendCategory = .subscriptions) -> RecurringDetector.Charge {
        .init(date: day(d), merchant: merchant, amount: amount, currency: "AUD", audAmount: amount,
              category: cat, card: .nab, renewsOn: nil, billingPeriod: nil)
    }

    /// Two Netflix charges at one merchant name, four months each, on two
    /// different plans/cards (12.99 and 22.99 — more than 25% apart, so they
    /// can never share a cluster). A person watching either plan expects
    /// both to show as a bill; today only one survives.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("two recurring plans at one merchant collide; the smaller one vanishes"))
    func twoSubscriptionsAtOneShopWithDifferentAmountsAreBothKept() {
        let found = RecurringDetector.detect([
            charge("2026-06-01", "Netflix", 12.99), charge("2026-06-15", "Netflix", 22.99),
            charge("2026-07-01", "Netflix", 12.99), charge("2026-07-15", "Netflix", 22.99),
            charge("2026-08-01", "Netflix", 12.99), charge("2026-08-15", "Netflix", 22.99),
            charge("2026-09-01", "Netflix", 12.99), charge("2026-09-15", "Netflix", 22.99),
        ], now: day("2026-09-19"), calendar: cal)

        // Expected: both the 12.99 plan and the 22.99 plan are still bills.
        #expect(found.count == 2, "found \(found.count) Netflix bill(s): \(found.map(\.amount))")
        #expect(found.contains { $0.amount == 12.99 })
        #expect(found.contains { $0.amount == 22.99 })
    }
}
