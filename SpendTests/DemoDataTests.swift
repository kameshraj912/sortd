import Testing
import SwiftData
import Foundation
@testable import Spend

/// Sample data. This is what App Review sees when they tap "Explore with
/// sample data" on a fresh install, so it either works or the review stalls
/// on an empty screen.
@MainActor
struct DemoDataTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test func loadingPutsPurchasesIn() throws {
        let ctx = try store()
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        DemoData.load(in: ctx)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(!all.isEmpty, "sample data should put purchases in the store")
        #expect(all.count > 10)

        DemoData.clear(in: ctx)
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
    }

    @Test func loadingTwiceDoesNotDouble() throws {
        let ctx = try store()
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        DemoData.load(in: ctx)
        let first = try ctx.fetch(FetchDescriptor<Transaction>()).count
        DemoData.load(in: ctx)
        let second = try ctx.fetch(FetchDescriptor<Transaction>()).count
        #expect(first == second)

        DemoData.clear(in: ctx)
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
    }

    /// The stuck state: the flag says loaded, the database is empty.
    /// Restoring an iPhone backup can do exactly this — preferences come
    /// across, the store doesn't — and the app used to sit there empty.
    @Test func aFlagWithoutDataReloadsInsteadOfSittingEmpty() throws {
        let ctx = try store()
        UserDefaults.standard.set(true, forKey: DemoData.activeKey)
        #expect(!DemoData.isLoaded(in: ctx), "flag alone is not loaded")

        DemoData.load(in: ctx)
        #expect(!(try ctx.fetch(FetchDescriptor<Transaction>()).isEmpty),
                "sample data should come back rather than leaving an empty app")

        DemoData.clear(in: ctx)
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
    }

    @Test func clearingTakesItAllBackOut() throws {
        let ctx = try store()
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        DemoData.load(in: ctx)
        #expect(!(try ctx.fetch(FetchDescriptor<Transaction>()).isEmpty))
        DemoData.clear(in: ctx)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).isEmpty)
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
    }
}
