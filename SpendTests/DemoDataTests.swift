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

    /// What a relaunch actually does: `load` runs in one `ModelContext`,
    /// saves, and the process exits. Next launch opens the same container
    /// (same file on disk) and hands `load` a brand new `ModelContext` — the
    /// app never reuses the one from last time. If the reload guard were
    /// checked on one context but inserted through another, or the fetch
    /// missed a just-saved row, sample purchases would pile up once per
    /// launch. Reproduced here without a second process: same container,
    /// second `ModelContext`.
    @Test func loadingAgainFromANewContextOnTheSameContainerDoesNotDouble() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)

        let launch1 = ModelContext(container)
        DemoData.load(in: launch1)
        let afterFirstLaunch = try launch1.fetch(FetchDescriptor<Transaction>()).count
        #expect(afterFirstLaunch > 10)

        // A fresh context on the same container, the way `SpendApp.init()`
        // asks `SpendStore.container.mainContext` for it on every launch.
        let launch2 = ModelContext(container)
        DemoData.load(in: launch2)
        let afterSecondLaunch = try launch2.fetch(FetchDescriptor<Transaction>()).count
        #expect(afterSecondLaunch == afterFirstLaunch,
                "relaunching must not insert the sample purchases again")

        let launch3 = ModelContext(container)
        DemoData.load(in: launch3)
        let afterThirdLaunch = try launch3.fetch(FetchDescriptor<Transaction>()).count
        #expect(afterThirdLaunch == afterFirstLaunch,
                "a third launch must still see one copy of each sample purchase")

        DemoData.clear(in: launch3)
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
    }

    /// The actual bug. `context.save()` commits the sample rows to disk at
    /// once; `UserDefaults.set` does not — iOS flushes it in its own time,
    /// and a launch killed between those two lines (or a restore that
    /// dropped just this one preference) leaves the rows saved with the flag
    /// back to false. `isLoaded` checked the flag first and returned false
    /// without ever looking at the rows, so the next launch — a brand new
    /// process, a brand new `ModelContext` on the same store — inserted a
    /// second full set on top of the first.
    @Test func aLostFlagAfterTheRowsAreSavedDoesNotDuplicateThem() throws {
        let ctx = try store()
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        DemoData.load(in: ctx)
        let first = try ctx.fetch(FetchDescriptor<Transaction>()).count
        #expect(first > 10)

        // The rows made it to disk last launch; the flag didn't.
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        #expect(DemoData.isLoaded(in: ctx), "rows already on disk count as loaded even without the flag")

        // The next launch: a fresh context on the same container, same as
        // `SpendApp.init()` asking `SpendStore.container.mainContext` again.
        let relaunch = ModelContext(ctx.container)
        DemoData.load(in: relaunch)
        let second = try relaunch.fetch(FetchDescriptor<Transaction>()).count
        #expect(second == first, "a lost flag must not bring back a second copy of the sample data")

        DemoData.clear(in: relaunch)
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
    }
}
