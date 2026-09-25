import Testing
import Foundation
import SwiftData
@testable import Spend

/// `Array.pendingConversions` counts purchases still waiting on a rate
/// (`needsRate`), for the Home "+1 converting" label.
@MainActor
struct PendingConversionTests {
    let context: ModelContext
    /// A currency other than whatever this run's detected home currency is,
    /// so the purchase is guaranteed to need a rate.
    let foreign: String

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        foreign = Money.home == "SGD" ? "USD" : "SGD"
    }

    private func log(_ amount: Decimal, currency: String, at date: Date) throws -> Transaction {
        let p = IncomingPurchase(date: date, merchant: "Grab", amount: amount, currency: currency, card: .other, source: .tap)
        return try TransactionLogger.log(p, in: context).transaction
    }

    @Test func addingAForeignPurchaseWithNoRateNeedsARateAndCountsAsOnePending() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let t = try log(25, currency: foreign, at: date)

        #expect(t.currencyCode == foreign)
        #expect(t.amount == 25)
        #expect(t.needsRate)
        #expect([t].pendingConversions == 1)
    }

    @Test func aRateArrivingClearsThePendingCount() async throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let t = try log(25, currency: foreign, at: date)
        #expect([t].pendingConversions == 1)

        // Pre-seed the exact day's rate so the backfill needs no network call.
        let day = FXService.dayString(date)
        let key = Money.home == "AUD" ? "\(foreign)-\(day)" : "\(foreign)>\(Money.home)-\(day)"
        context.insert(FXRate(key: key, rate: 1))
        try context.save()

        _ = await FXService.backfill(in: context)

        #expect(!t.needsRate)
        #expect([t].pendingConversions == 0)
    }
}
