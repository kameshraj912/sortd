import Testing
import Foundation
import SwiftData
@testable import Spend

/// Full-money hunt, 28 Sep 2026: every way money gets in except Apple Pay and
/// Gmail (hunted separately), and the money maths. One failing test per finding.
@MainActor
struct FullMoneyStatementImportTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    /// A single signed "Amount" column: NAB's own export shape. A negative
    /// row is a purchase; a positive row (salary, a refund) is money in and
    /// `StatementImport.rows` correctly tags it `.moneyIn` — but `save`
    /// never looks at `kind` at all, so it books every row it is handed as
    /// spending. Today's `ImportView` happens to filter to `.spend` rows
    /// before calling `save`, so this cannot yet happen through the app's
    /// own screen; it is a gap in `save`'s own contract, not (yet) a thing a
    /// user can trigger, which is why this is reported rather than silently
    /// fixed. Any other caller of the public `StatementImport.save` — a
    /// Shortcut, a Files share extension, a future screen — would double
    /// Raj's spending by the size of his salary.
    ///
    /// Known bug: `StatementImport.save` (Spend/Services/StatementImport.swift:216) builds an
    /// `IncomingPurchase` from every row regardless of `row.kind`, never checking `.spend` vs `.moneyIn`.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("full-money-01: StatementImport.save logs a moneyIn row (salary, refund) as spending"))
    func saveNeverBooksAMoneyInRowAsAPurchase() throws {
        let previousHome = UserDefaults.standard.string(forKey: Money.homeKey)
        UserDefaults.standard.set("AUD", forKey: Money.homeKey)
        defer { UserDefaults.standard.set(previousHome, forKey: Money.homeKey) }

        let ctx = try store()
        let csv = """
        Date,Description,Amount
        01/09/2026,Cafe Blossom,-4.50
        02/09/2026,Salary,2000.00
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 2)
        #expect(rows.first { $0.detail == "Cafe Blossom" }?.kind == .spend)
        #expect(rows.first { $0.detail == "Salary" }?.kind == .moneyIn)

        _ = StatementImport.save(rows, card: .nab, in: ctx)
        let saved = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(saved.count == 1, "the Salary row (kind: .moneyIn) was booked as a purchase alongside the real one")
        #expect(saved.audTotal == Decimal(string: "4.50"), "the month total includes a $2000 salary deposit as spending")
    }
}
