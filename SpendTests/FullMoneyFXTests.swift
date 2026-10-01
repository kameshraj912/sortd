import Testing
import Foundation
import SwiftData
@testable import Spend

/// Full-money hunt, 28 Sep 2026: the FX maths behind `audValue`.
@MainActor
struct FullMoneyFXTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func at(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        c.calendar = Calendar(identifier: .gregorian)
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// Purchase Detail's Date field is bound straight to `transaction.date`
    /// with no `onChange` (unlike Amount and Currency, which both call
    /// `refreshAUD()`). Once `audAmount` has a value, `FXService.backfill`
    /// never looks at that purchase again — its own fetch is
    /// `audAmount == nil`. So correcting a foreign-currency purchase's date
    /// (a receipt mis-scanned as today, fixed to the day on the paper) keeps
    /// converting it at the *old* day's rate forever, even though a rate for
    /// the corrected day is sitting right there in the cache.
    ///
    /// Known bug: `TransactionDetailView` (Spend/Views/TransactionDetailView.swift:105,150-151) has no
    /// `.onChange(of: transaction.date)`, and `FXService.backfillPass` (Spend/Services/FXService.swift:147)
    /// only ever revisits a transaction whose `audAmount` is nil.
    @Test(.bug(id: "full-money-02", "correcting a purchase's date does not re-rate it, even when the right day's rate is cached"))
    func correctingTheDateReRatesTheAUDValue() async throws {
        let previousHome = UserDefaults.standard.string(forKey: Money.homeKey)
        UserDefaults.standard.set("AUD", forKey: Money.homeKey)
        defer { UserDefaults.standard.set(previousHome, forKey: Money.homeKey) }

        let ctx = try store()
        let scannedAsDay = at(2026, 9, 1)
        let actualDay = at(2026, 9, 20)
        ctx.insert(FXRate(key: "SGD-2026-09-01", rate: 0.80))
        ctx.insert(FXRate(key: "SGD-2026-09-20", rate: 0.90))
        try ctx.save()

        let t = Transaction(date: scannedAsDay, merchant: "Hawker Stall", rawMerchant: "Hawker Stall",
                            amount: 10, currencyCode: "SGD", card: .other, category: .eatingOut, source: .manual)
        ctx.insert(t)
        try ctx.save()

        _ = await FXService.backfill(in: ctx)
        #expect(t.audAmount == 8, "sanity check: 1 Sep's cached rate (0.80) should give 8")

        // The receipt was actually from 20 Sep; Raj fixes the date the way
        // Purchase Detail lets him.
        t.date = actualDay
        try ctx.save()
        _ = await FXService.backfill(in: ctx)

        #expect(t.audAmount == 9, "after correcting the date to 20 Sep, the AUD value still uses 1 Sep's rate (\(t.audAmount?.description ?? "nil"))")
    }
}
