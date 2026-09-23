import Testing
import SwiftData
import Foundation
@testable import Spend

/// Tester finds from the September abuse pass: a huge budget that crashed
/// the budget sheet, an emptied Amount field that saved its last digit, and
/// a Replace restore that kept old cards and said the wrong thing.
@MainActor
struct AbuseFixesDataTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "abuse-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: Budget

    @Test func aHugeStoredBudgetIsClearedNotCrashed() {
        #expect(BudgetSheet.sanitized(1e19, currency: "SGD") == 0)
        #expect(BudgetSheet.sanitized(.infinity, currency: "SGD") == 0)
        #expect(BudgetSheet.sanitized(.nan, currency: "SGD") == 0)
        #expect(BudgetSheet.sanitized(-5, currency: "SGD") == 0)
        #expect(BudgetSheet.sanitized(1_000_000, currency: "SGD") == 1_000_000)
        #expect(BudgetSheet.sanitized(1_000_000.01, currency: "SGD") == 0)
        #expect(BudgetSheet.text(for: 1e19, currency: "SGD") == "")
        #expect(BudgetSheet.text(for: 776.5, currency: "SGD") == "776.5")
        #expect(BudgetSheet.text(for: 1000, currency: "SGD") == "1000")
    }

    @Test func budgetInputStopsAtSevenDigits() {
        #expect(BudgetSheet.limitInput("1234567890123456789", currency: "AUD") == "1000000")
        #expect(BudgetSheet.limitInput("999999", currency: "AUD") == "999999")
        #expect(BudgetSheet.limitInput("0050", currency: "AUD") == "50")
        #expect(BudgetSheet.limitInput("12.345", currency: "AUD") == "12.34")
        #expect(BudgetSheet.limitInput("", currency: "AUD") == "")
    }

    @Test func bigNumberCurrenciesKeepTheirSetupPresets() {
        // Setup offers up to Rp30,000,000; that must survive the sheet.
        #expect(BudgetSheet.sanitized(30_000_000, currency: "IDR") == 30_000_000)
        #expect(BudgetSheet.sanitized(3_000_000, currency: "KRW") == 3_000_000)
    }

    // MARK: Amount field

    @Test func anEmptiedAmountKeepsTheOldOne() {
        #expect(TransactionDetailView.committedAmount(from: "") == nil)
        #expect(TransactionDetailView.committedAmount(from: "   ") == nil)
        #expect(TransactionDetailView.committedAmount(from: "abc") == nil)
        #expect(TransactionDetailView.committedAmount(from: "0") == nil)
        #expect(TransactionDetailView.committedAmount(from: "1000000.01") == nil)
        #expect(TransactionDetailView.committedAmount(from: "21.90") == Decimal(string: "21.90"))
        #expect(TransactionDetailView.committedAmount(from: "1,000,000") == 1_000_000)
    }

    // MARK: Replace restore

    private func backup(cards: [CardInfo], purchases: [(String, String)]) throws -> Data {
        var snap = Backup.Snapshot()
        snap.cards = cards
        snap.transactions = purchases.map { merchant, card in
            Backup.Snapshot.Row(id: UUID(), date: .now, merchant: merchant, rawMerchant: merchant,
                                amount: 10, currencyCode: "AUD", homeAmount: 10, card: card,
                                category: SpendCategory.groceries.rawValue, source: TxnSource.manual.rawValue,
                                seenIn: "", note: "", createdAt: .now, platform: nil, refunded: false,
                                renewsOn: nil, billingPeriod: nil, sourceAccount: nil)
        }
        return try Backup.encode(snap)
    }

    @Test func replaceTakesTheBackupsCards() throws {
        let book = CardBook(defaults: scratch())
        book.replaceAll([CardInfo(id: "old", name: "Old", shortName: "Old")])
        let data = try backup(cards: [CardInfo(id: "new", name: "New", shortName: "New")],
                              purchases: [("Woolworths", "new")])

        let result = try Backup.restore(data, mode: .replace, into: try store(), defaults: scratch(), cardBook: book)
        #expect(book.cards.map(\.id) == ["new"])
        #expect(result.cards == 1)
    }

    @Test func replaceWithACardlessBackupClearsTheCards() throws {
        let book = CardBook(defaults: scratch())
        book.replaceAll([CardInfo(id: "old", name: "Old", shortName: "Old")])
        let data = try backup(cards: [], purchases: [])

        let ctx = try store()
        ctx.insert(Transaction(date: .now, merchant: "Coles", amount: 5, currencyCode: "AUD",
                               card: .other, category: .groceries, source: .manual))
        try ctx.save()
        try Backup.restore(data, mode: .replace, into: ctx, defaults: scratch(), cardBook: book)
        #expect(book.cards.isEmpty)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test func replaceKeepsACardARestoredPurchaseStillUses() throws {
        let book = CardBook(defaults: scratch())
        book.replaceAll([CardInfo(id: "used", name: "Used", shortName: "Used"),
                         CardInfo(id: "unused", name: "Unused", shortName: "Unused")])
        let data = try backup(cards: [], purchases: [("Coles", "used")])
        try Backup.restore(data, mode: .replace, into: try store(), defaults: scratch(), cardBook: book)
        #expect(book.cards.map(\.id) == ["used"])
    }

    @Test func mergeStillNeverDropsACard() throws {
        let book = CardBook(defaults: scratch())
        book.replaceAll([CardInfo(id: "mine", name: "Mine", shortName: "Mine")])
        let data = try backup(cards: [CardInfo(id: "theirs", name: "Theirs", shortName: "Theirs")], purchases: [])
        try Backup.restore(data, mode: .merge, into: try store(), defaults: scratch(), cardBook: book)
        #expect(book.cards.map(\.id) == ["mine", "theirs"])
    }

    @Test func theReplaceWarningSaysWhatsInTheBackup() throws {
        let empty = try #require(Backup.contents(of: try backup(cards: [], purchases: [])))
        #expect(empty.purchases == 0)
        let warning = Backup.replaceWarning(backup: empty, purchasesHere: 31)
        #expect(warning.title == "Replace the 31 purchases on this iPhone?")
        #expect(warning.message.contains("This backup has no purchases. Replacing will leave Sortd empty."))

        let full = Backup.Contents(purchases: 12, cards: 2, createdAt: .now)
        let msg = Backup.replaceWarning(backup: full, purchasesHere: 1).message
        #expect(msg.contains("12 purchases and 2 cards"))
    }
}
