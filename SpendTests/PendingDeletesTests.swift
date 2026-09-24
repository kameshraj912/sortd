import Testing
import Foundation
import SwiftData
@testable import Spend

/// The Undo window behind swipe-to-delete on the Activity list.
@MainActor
struct PendingDeletesTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    var stored: [Transaction] { (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] }

    @discardableResult
    func purchase(_ merchant: String, amount: Decimal = 12) throws -> Transaction {
        let t = Transaction(date: .now, merchant: merchant, amount: amount, currencyCode: "AUD",
                            card: .other, category: .groceries, source: .manual)
        context.insert(t)
        try context.save()
        return t
    }

    @Test func stagingRemovesNothingFromStore() throws {
        let t = try purchase("Woolworths")
        let pending = PendingDeletes()
        pending.stage(t) {}

        #expect(pending.count == 1)
        #expect(pending.text == "Deleted Woolworths")
        #expect(stored.count == 1)
        #expect(!context.hasChanges)          // nothing written until commit
    }

    @Test func undoRestoresEveryPendingRow() throws {
        let a = try purchase("Woolworths")
        let b = try purchase("Coles")
        let pending = PendingDeletes()
        pending.stage(a) {}
        pending.stage(b) {}
        #expect(pending.text == "Deleted 2 purchases")

        pending.undo()

        #expect(pending.isEmpty)
        #expect(stored.count == 2)
        #expect(!a.isDeleted && !b.isDeleted)
    }

    @Test func commitDeletesAndSaves() throws {
        let a = try purchase("Woolworths")
        try purchase("Coles")
        let pending = PendingDeletes()
        pending.stage(a) {}

        pending.commit(in: context)

        #expect(pending.isEmpty)
        #expect(stored.map(\.merchant) == ["Coles"])
        #expect(!context.hasChanges)          // saved, not just marked
    }

    @Test func secondStageExtendsTheWindow() async throws {
        let a = try purchase("Woolworths")
        let b = try purchase("Coles")
        let pending = PendingDeletes(window: .seconds(10))
        pending.stage(a) {}
        let first = try #require(pending.deadline)

        try await Task.sleep(for: .milliseconds(20))
        pending.stage(b) {}
        let second = try #require(pending.deadline)

        #expect(second > first)
        #expect(pending.count == 2)

        // Swiping the same row twice does not double it up.
        pending.stage(a) {}
        #expect(pending.count == 2)
    }

    @Test func secondStageFiresOneExpiryAfterBothWindows() async throws {
        let a = try purchase("Woolworths")
        let b = try purchase("Coles")
        let pending = PendingDeletes(window: .milliseconds(200))
        var fired = 0
        pending.stage(a) { fired += 1 }
        try await Task.sleep(for: .milliseconds(30))
        pending.stage(b) { fired += 1 }

        try await Task.sleep(for: .milliseconds(600))

        #expect(fired == 1)
        #expect(pending.count == 2)
    }

    @Test func commitAfterUndoIsNoOp() throws {
        let t = try purchase("Woolworths")
        let pending = PendingDeletes()
        pending.stage(t) {}
        pending.undo()

        pending.commit(in: context)

        #expect(stored.count == 1)
        #expect(!t.isDeleted)
    }

    @Test func windowEndsWithOneCallback() async throws {
        let t = try purchase("Woolworths")
        let pending = PendingDeletes(window: .milliseconds(200))
        var fired = 0
        pending.stage(t) { fired += 1 }

        try await Task.sleep(for: .milliseconds(600))

        #expect(fired == 1)
        #expect(pending.count == 1)           // still staged: the view commits after its animation
        #expect(stored.count == 1)
    }

    @Test func undoCancelsTheWindow() async throws {
        let t = try purchase("Woolworths")
        let pending = PendingDeletes(window: .milliseconds(200))
        var fired = 0
        pending.stage(t) { fired += 1 }
        pending.undo()

        try await Task.sleep(for: .milliseconds(600))

        #expect(fired == 0)
        #expect(pending.deadline == nil)
    }

    @Test func defaultWindowIsEightSeconds() {
        #expect(PendingDeletes().window == .seconds(8))
    }
}
