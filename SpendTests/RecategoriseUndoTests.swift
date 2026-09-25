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
}
