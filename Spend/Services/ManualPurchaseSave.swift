import Foundation
import SwiftData

/// One New Purchase sheet's save. The first save logs the purchase through
/// `TransactionLogger`; if a later step then throws (re-filing the category),
/// the row is already in the store. A retry must change that row, not log a
/// second one: hand-typed purchases are never merged as duplicates, so
/// nothing else would catch it.
@MainActor
final class ManualPurchaseSave {
    /// The row this sheet has already put in the store, if any.
    private(set) var logged: Transaction?

    typealias Recategorise = (Transaction, SpendCategory, ModelContext) throws -> Void

    /// Logs `purchase`, or updates the row logged by an earlier try of this
    /// same sheet. `recategorise` runs when the category was picked by hand.
    /// Throws what failed; the row (if it got in) stays remembered for the retry.
    @discardableResult
    func save(_ purchase: IncomingPurchase, recategoriseTo category: SpendCategory?, in context: ModelContext,
              recategorise: Recategorise = { t, c, ctx in try TransactionLogger.recategorise(t, to: c, in: ctx) }) throws -> Transaction {
        let txn: Transaction
        if let existing = logged {
            Self.update(existing, from: purchase)
            try context.save()
            txn = existing
        } else {
            let outcome = try TransactionLogger.log(purchase, in: context)
            // A merge is another row that was already there: never ours to rewrite.
            if case .added(let added) = outcome { logged = added }
            txn = outcome.transaction
        }
        if let category { try recategorise(txn, category, context) }
        return txn
    }

    /// The sheet's fields onto the row it logged. The same fields `log`
    /// sets on a new purchase, so a retry ends where a first try would have.
    private static func update(_ t: Transaction, from p: IncomingPurchase) {
        let name = MerchantName.limited(p.merchant)
        t.date = p.date
        t.merchant = MerchantName.clean(name)
        t.rawMerchant = name
        t.amount = p.amount
        t.currencyCode = p.currency
        t.audAmount = p.currency == Money.home ? p.amount : nil
        t.card = p.card
        if let category = p.category { t.category = category }
        t.note = p.note
    }
}
