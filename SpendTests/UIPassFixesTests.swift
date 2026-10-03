import Testing
import SwiftData
import CloudKit
import Foundation
@testable import Spend

/// Fixes from the 3 Oct 2026 screen pass: the New Purchase save, shop name
/// length, the amount filter, and the iCloud switch with no account.
@MainActor
struct UIPassFixesTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func purchase(_ merchant: String = "Corner Cafe", amount: Decimal = 12) -> IncomingPurchase {
        IncomingPurchase(date: .now, merchant: merchant, amount: amount, currency: Money.home,
                         card: .nab, source: .manual, category: .eatingOut)
    }

    private struct Boom: Error {}

    // MARK: New Purchase save is idempotent

    @Test func retryAfterRecategoriseFailureUpdatesTheSameRow() throws {
        let ctx = try store()
        let saver = ManualPurchaseSave()
        #expect(throws: Boom.self) {
            try saver.save(purchase(), recategoriseTo: .groceries, in: ctx) { _, _, _ in throw Boom() }
        }
        // The first try already put the row in.
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)

        // The person edits the amount and shop, then taps Add again.
        let txn = try saver.save(purchase("Corner Market", amount: 15), recategoriseTo: .groceries, in: ctx)
        let rows = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(rows.count == 1)
        #expect(rows.first === txn)
        #expect(txn.amount == 15)
        #expect(txn.merchant == "Corner Market")
        #expect(txn.category == .groceries)
    }

    @Test func aSecondSaveOfTheSameSheetNeverAddsARow() throws {
        let ctx = try store()
        let saver = ManualPurchaseSave()
        try saver.save(purchase(), recategoriseTo: nil, in: ctx)
        try saver.save(purchase(), recategoriseTo: nil, in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test func aNewSheetStillAddsItsOwnRow() throws {
        let ctx = try store()
        try ManualPurchaseSave().save(purchase(), recategoriseTo: nil, in: ctx)
        try ManualPurchaseSave().save(purchase(), recategoriseTo: nil, in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    // MARK: Shop name length

    @Test func loggerCutsALongNameToEightyCharacters() throws {
        let ctx = try store()
        let paste = String(repeating: "Long Shop Name ", count: 70)   // ~1,000 characters
        let txn = try TransactionLogger.log(purchase(paste), in: ctx).transaction
        #expect(txn.merchant.count <= MerchantName.maxLength)
        #expect(txn.rawMerchant.count <= MerchantName.maxLength)
        #expect(!txn.merchant.isEmpty)
    }

    @Test func aNormalNameIsLeftAlone() {
        #expect(MerchantName.limited("  Corner Cafe ") == "Corner Cafe")
        #expect(MerchantName.limited(String(repeating: "a", count: 80)).count == 80)
        #expect(MerchantName.limited(String(repeating: "a", count: 81)).count == 80)
    }

    // MARK: Amount filter

    @Test func aSecondDecimalPointIsNotAccepted() {
        #expect(!AddTransactionView.isTypeable("12.34."))
        #expect(!AddTransactionView.isTypeable("12.3.4"))
        #expect(!AddTransactionView.isTypeable("12.345.6"))
        // What was there stays; no digit is changed.
        #expect(AmountEntry.accepted("12.34.", replacing: "12.34", wholeDigits: 6) == "12.34")
        #expect(AddTransactionView.isTypeable("12.34"))
    }

    // MARK: iCloud with no account

    @Test func iCloudSwitchSaysWhyWhenThereIsNoAccount() {
        #expect(CloudKitBackupStore.unavailableReason(for: .available) == nil)
        #expect(CloudKitBackupStore.unavailableReason(for: .noAccount) == "Sign in to iCloud in the Settings app to back up.")
        #expect(CloudKitBackupStore.unavailableReason(for: .restricted) != nil)
        #expect(CloudKitBackupStore.unavailableReason(for: .couldNotDetermine) != nil)
        #expect(CloudKitBackupStore.unavailableReason(for: .temporarilyUnavailable) != nil)
    }
}
