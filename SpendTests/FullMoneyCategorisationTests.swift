import Testing
import Foundation
import SwiftData
@testable import Spend

/// Full-money hunt, 28 Sep 2026: merchant rules after a rename.
@MainActor
struct FullMoneyCategorisationTests {

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

    /// Purchase Detail's "Paid to" field only ever writes `transaction.merchant`
    /// (`commitMerchant`, Spend/Views/TransactionDetailView.swift:270-282); it never
    /// touches `rawMerchant`. But `TransactionLogger`'s "same place" grouping and rule
    /// learning key on `rawMerchant` (`ruleKey`, Spend/Services/SpendStore.swift:219-221),
    /// not on the name shown on screen. So renaming one purchase — fixing a shop the
    /// cleaner mangled, or just correcting a typo — leaves it grouped under its old,
    /// un-renamed name for every future categorisation: recategorising it still moves
    /// *other* purchases of the old name, and a rule learned there never applies to a
    /// new purchase logged under the name Raj actually renamed it to.
    ///
    /// Known bug: `TransactionLogger.ruleKey`/`samePlace`/`recategorise` (Spend/Services/SpendStore.swift:219-269)
    /// use `t.rawMerchant`, which a rename in Purchase Detail never updates.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("full-money-03: renaming a purchase's Paid To field learns and groups by the old name, not the new one"))
    func renamingAPurchaseMovesItsOwnRuleToTheNewName() throws {
        let ctx = try store()
        let renamed = try TransactionLogger.log(
            IncomingPurchase(date: at(2026, 9, 1), merchant: "cafe blossom", amount: 5,
                             currency: "AUD", card: .other, source: .manual), in: ctx).transaction
        let untouched = try TransactionLogger.log(
            IncomingPurchase(date: at(2026, 9, 2), merchant: "cafe blossom", amount: 6,
                             currency: "AUD", card: .other, source: .manual), in: ctx).transaction

        // Raj discovers this purchase was really at a different shop and
        // renames just this one, the way Purchase Detail's "Paid to" field does:
        // it tidies the text and writes `merchant`, never `rawMerchant`.
        renamed.merchant = MerchantName.clean("Bluebird Mart")
        try ctx.save()

        _ = try TransactionLogger.recategorise(renamed, to: .shopping, in: ctx)
        #expect(untouched.category != .shopping,
                "recategorising the renamed purchase also moved the other, un-renamed Cafe Blossom purchase")

        // A fresh purchase logged under the name Raj actually renamed it to
        // should pick up the rule he just taught for "Bluebird Mart".
        let fresh = try TransactionLogger.log(
            IncomingPurchase(date: at(2026, 9, 3), merchant: "Bluebird Mart", amount: 7,
                             currency: "AUD", card: .other, source: .manual), in: ctx).transaction
        #expect(fresh.category == .shopping,
                "a new Bluebird Mart purchase was filed under \(fresh.category), not the rule Raj taught after the rename")
    }
}
