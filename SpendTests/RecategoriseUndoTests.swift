import Testing
import Foundation
import SwiftData
@testable import Spend

/// `TransactionLogger.recategorise` reports what it changed, so the UI can
/// show a toast ("Moved 12 others at Coles · Undo") and reverse it exactly:
/// every moved category, and the learned rule as it stood before.
@MainActor
struct RecategoriseUndoTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func log(_ merchant: String, _ amount: Decimal, minutes: Double) throws -> Transaction {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60), merchant: merchant,
                                 amount: amount, currency: "AUD", card: .other, source: .email)
        return try TransactionLogger.log(p, in: context).transaction
    }

    @Test func applyToOthersMovesTheShopAndListsEachMovedIdWithItsOldCategory() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        let b = try log("Spotify", 12.99, minutes: 60 * 24 * 30)
        let beforeA = a.category
        let beforeB = b.category

        let change = try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: true)

        #expect(a.category == .groceries)
        #expect(b.category == .groceries)
        let byID = Dictionary(uniqueKeysWithValues: change.moved.map { ($0.id, $0.from) })
        #expect(byID[a.id] == beforeA)
        #expect(byID[b.id] == beforeB)
        #expect(Set(byID.keys) == Set([a.id, b.id]))
    }

    @Test func undoRestoresEveryMovedTransaction() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        let b = try log("Spotify", 12.99, minutes: 60 * 24 * 30)
        let c = try log("Spotify", 12.99, minutes: 60 * 24 * 60)
        let beforeA = a.category
        let beforeB = b.category
        let beforeC = c.category

        let change = try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: true)
        try TransactionLogger.undo(change, in: context)

        #expect(a.category == beforeA)
        #expect(b.category == beforeB)
        #expect(c.category == beforeC)
    }

    @Test func undoRemovesTheNewlyLearnedRuleWhenNoneExistedBefore() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        #expect(try TransactionLogger.learnedRules(in: context)["spotify"] == nil)

        let change = try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: true)
        #expect(try TransactionLogger.learnedRules(in: context)["spotify"] == .groceries)

        try TransactionLogger.undo(change, in: context)
        #expect(try TransactionLogger.learnedRules(in: context)["spotify"] == nil)
    }

    @Test func undoRestoresThePreviousRuleCategoryWhenOneAlreadyExisted() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        try TransactionLogger.recategorise(a, to: .subscriptions, in: context, applyToOthers: true)
        #expect(try TransactionLogger.learnedRules(in: context)["spotify"] == .subscriptions)

        let change = try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: true)
        #expect(try TransactionLogger.learnedRules(in: context)["spotify"] == .groceries)

        try TransactionLogger.undo(change, in: context)
        #expect(try TransactionLogger.learnedRules(in: context)["spotify"] == .subscriptions)
    }

    @Test func justThisOneMovesOnlyThatPurchaseAndListsOne() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        let b = try log("Spotify", 12.99, minutes: 60 * 24 * 30)
        let beforeB = b.category

        let change = try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: false)

        #expect(a.category == .groceries)
        #expect(b.category == beforeB)
        #expect(change.moved.map(\.id) == [a.id])
        #expect(change.ruleKey == nil)
        #expect(change.ruleBefore == nil)
    }

    @Test func undoPutsBackTheRulesUpdatedAt() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        try TransactionLogger.recategorise(a, to: .subscriptions, in: context, applyToOthers: true)
        let rule = try #require(try context.fetch(FetchDescriptor<MerchantRule>()).first)
        let stamped = Date(timeIntervalSince1970: 1_700_000_000)
        rule.updatedAt = stamped
        try context.save()

        let change = try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: true)
        #expect(rule.updatedAt != stamped)
        try TransactionLogger.undo(change, in: context)

        #expect(rule.updatedAt == stamped)
        #expect(rule.category == .subscriptions)
    }

    @Test func rowsWaitingOnAPendingDeleteAreLeftOut() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        let b = try log("Spotify", 12.99, minutes: 60 * 24 * 30)
        let beforeB = b.category

        let change = try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: true,
                                                        excluding: [b.id])

        #expect(b.category == beforeB)
        #expect(change.moved.map(\.id) == [a.id])
        #expect(change.others == 0)
    }
}

/// The Undo window behind "Moved 12 others at Coles", shared by the detail
/// screen and Activity so leaving one keeps the Undo alive on the other.
@MainActor
struct PendingRecategoriseTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func log(_ merchant: String, minutes: Double) throws -> Transaction {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60), merchant: merchant,
                                 amount: 12.99, currency: "AUD", card: .other, source: .email)
        return try TransactionLogger.log(p, in: context).transaction
    }

    /// Returns as soon as `condition` holds. The limit is long because on a
    /// busy CI machine the main actor (where the fade timer runs) can be held
    /// for tens of seconds; 10 s timed out there twice on 3 Oct 2026.
    private func waitUntil(_ limit: Duration = .seconds(60), _ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let end = clock.now + limit
        while !condition(), clock.now < end {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func aChangeThatMovedNobodyElseIsNotStaged() throws {
        let a = try log("Spotify", minutes: 0)
        let pending = PendingRecategorise()
        let change = try TransactionLogger.recategorise(a, to: .groceries, in: context)
        pending.stage(change)
        #expect(pending.change == nil)
    }

    @Test func undoRestoresAndClears() throws {
        let a = try log("Spotify", minutes: 0)
        let b = try log("Spotify", minutes: 60 * 24 * 30)
        let before = b.category
        let pending = PendingRecategorise()
        pending.stage(try TransactionLogger.recategorise(a, to: .groceries, in: context))
        #expect(pending.text == "Moved 1 other at Spotify")

        pending.undo(in: context)

        #expect(pending.change == nil)
        #expect(b.category == before)
        #expect(a.category == before)
    }

    @Test func theWindowEndsWithAFadeThenClears() async throws {
        let a = try log("Spotify", minutes: 0)
        _ = try log("Spotify", minutes: 60 * 24 * 30)
        let pending = PendingRecategorise(window: .milliseconds(100), fade: .milliseconds(100))
        pending.stage(try TransactionLogger.recategorise(a, to: .groceries, in: context))

        try await waitUntil { pending.closing }
        // Still on screen and still undoable during the fade.
        #expect(pending.change != nil)
        try await waitUntil { pending.change == nil }
        #expect(!pending.closing)
    }

    @Test func undoDuringTheFadeStillWorks() async throws {
        let a = try log("Spotify", minutes: 0)
        let b = try log("Spotify", minutes: 60 * 24 * 30)
        let before = b.category
        let pending = PendingRecategorise(window: .milliseconds(50), fade: .seconds(5))
        pending.stage(try TransactionLogger.recategorise(a, to: .groceries, in: context))
        try await waitUntil { pending.closing }

        pending.undo(in: context)

        #expect(pending.change == nil)
        #expect(!pending.closing)
        #expect(b.category == before)
    }

    @Test func aNewChangeReplacesTheOldWindow() throws {
        let a = try log("Spotify", minutes: 0)
        _ = try log("Spotify", minutes: 60 * 24 * 30)
        let c = try log("Coles", minutes: 5)
        _ = try log("Coles", minutes: 60 * 24 * 10)
        let pending = PendingRecategorise()
        pending.stage(try TransactionLogger.recategorise(a, to: .groceries, in: context))
        pending.stage(try TransactionLogger.recategorise(c, to: .eatingOut, in: context))
        #expect(pending.text == "Moved 1 other at Coles")
    }
}
