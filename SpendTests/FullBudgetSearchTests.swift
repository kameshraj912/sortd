import Testing
import Foundation
import SwiftData
@testable import Spend

/// The Search tab's filter: `SearchText.fold` keeps only alphanumerics, so a
/// query that is entirely emoji, currency signs or other symbols folds down
/// to the empty string. `SearchText.matches` treats an empty folded query as
/// "match everything" (the rule for the untyped search field), so typing a
/// symbol-only query that should find nothing instead shows every purchase.
@MainActor
@Suite struct FullBudgetSearchTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func log(_ context: ModelContext, _ merchant: String, _ amount: Decimal) throws -> Transaction {
        let p = IncomingPurchase(date: .now, merchant: merchant, amount: amount, currency: "AUD",
                                 card: .other, source: .manual)
        return try TransactionLogger.log(p, in: context).transaction
    }

    /// What the Search tab actually does: fold the trimmed, non-empty query
    /// text the person typed, then filter by it.
    private func matchesTyped(_ t: Transaction, typed: String) -> Bool {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        return SearchText.matches(t, folded: SearchText.fold(trimmed))
    }

    @Test
    func anEmojiOnlySearchMatchesNothingRatherThanEverything() throws {
        let ctx = try store()
        let coffee = try log(ctx, "Woolworths", 40)

        // Typed a real, non-empty query with no letters or digits in it.
        #expect(!"💸".trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(matchesTyped(coffee, typed: "💸") == false,
                "an emoji query with nothing alphanumeric in it must not match an unrelated purchase")
    }

    @Test
    func aDollarSignOnlySearchMatchesNothingRatherThanEverything() throws {
        let ctx = try store()
        let coffee = try log(ctx, "Woolworths", 40)

        #expect(matchesTyped(coffee, typed: "$") == false,
                "a bare currency sign must not match every purchase")
    }

    /// Regression: normal text still folds and matches as expected (accents,
    /// case, apostrophes) — already covered by `SearchTextTests`, kept here
    /// only to show the emoji/symbol cases are the odd ones out, not `fold`
    /// itself.
    @Test func aRealQueryStillMatchesTheRightPurchase() throws {
        let ctx = try store()
        let coffee = try log(ctx, "Woolworths", 40)
        #expect(matchesTyped(coffee, typed: "wool"))
    }

    @Test func aDollarAmountFindsThatAmount() throws {
        let ctx = try store()
        let a = try log(ctx, "Cafe", 5.50)
        let b = try log(ctx, "Bakery", 12)
        let match = SearchText.matcher(for: "$5.50")
        #expect(match(a))
        #expect(!match(b))
    }

    @Test func aBlankSearchMatchesEverythingButASymbolOnlyOneMatchesNothing() throws {
        let ctx = try store()
        let a = try log(ctx, "Cafe", 5.50)
        #expect(SearchText.matcher(for: "   ")(a))
        #expect(SearchText.matcher(for: "")(a))
        #expect(!SearchText.matcher(for: "$")(a))
        #expect(!SearchText.matcher(for: "💸")(a))
        #expect(SearchText.matcher(for: "caf")(a))
    }
}
