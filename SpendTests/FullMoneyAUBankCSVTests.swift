import Testing
import Foundation
import SwiftData
@testable import Spend

/// Full-money hunt: statement import with the CSV shapes Australian banks
/// export. Shapes are written from memory of each bank's export, not from a
/// real file, so the report says which ones still need a real export to confirm.
@MainActor
struct FullMoneyAUBankCSVTests {

    private func ymd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    private func money(_ s: String) -> Decimal { Decimal(string: s)! }

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    // MARK: CommBank: no header, date / signed amount / description / balance

    @Test func commBankHeaderlessExportReadsEveryRow() {
        let csv = """
        01/09/2026,"-58.30","WOOLWORTHS 3342 RICHMOND VIC AUS","+2451.70"
        02/09/2026,"-5.50","SEVEN SEEDS COFFEE CARLTON VIC AUS","+2446.20"
        03/09/2026,"3200.00","SALARY ACME PTY LTD","+5646.20"
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 3)
        #expect(rows.filter { $0.kind == .spend }.count == 2)
        #expect(rows.first?.amount == money("58.30"))
        #expect(rows.first.map { ymd($0.date) } == "2026-09-01")
        #expect(rows.first?.detail.contains("WOOLWORTHS") == true)
    }

    @Test func commBankQuotedThousandsAreRead() {
        let csv = """
        01/09/2026,"-1,234.50","RENT PAYMENT REAL ESTATE","+100.00"
        02/09/2026,"-5.50","COFFEE","+94.50"
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.first?.amount == money("1234.50"))
    }

    /// CommBank card descriptions end with "Card xx1234 Value Date: 30/08/2026".
    /// With no header, the importer counts that cell as a second date column and
    /// leaves it out of the text columns, so the longest text left is the running
    /// balance: the shop becomes "+2451.70".
    ///
    /// Known bug: `StatementImport.layout(for:)` (Spend/Services/StatementImport.swift:141-158) counts a cell as a date if
    /// `parseDate` finds a date anywhere inside it, so a description holding a date is not text.
    @Test(.bug(id: "full-money-04", "a headerless CommBank description that contains a date is not used as the shop name"))
    func aDescriptionHoldingADateIsStillTheShopName() {
        let csv = """
        01/09/2026,"-58.30","WOOLWORTHS 3342 RICHMOND VIC AUS Card xx1234 Value Date: 30/08/2026","+2451.70"
        02/09/2026,"-5.50","SEVEN SEEDS COFFEE CARLTON AUS Card xx1234 Value Date: 31/08/2026","+2446.20"
        03/09/2026,"-24.99","KMART 1234 RICHMOND AUS Card xx1234 Value Date: 01/09/2026","+2421.21"
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 3)
        #expect(rows.first.map { ymd($0.date) } == "2026-09-01")   // the date column is right
        #expect(rows.first?.detail.contains("WOOLWORTHS") == true, "shop is '\(rows.first?.detail ?? "none")'")
    }

    // MARK: NAB: header, "dd MMM yy" dates

    @Test func nabExportWithTextMonthDatesKeepsDateAndAmount() {
        let csv = """
        Date,Amount,Account Number,,Transaction Type,Transaction Details,Balance,Category,Merchant Name
        01 Sep 26,-58.30,083-123 12345678,,DEBIT,EFTPOS WOOLWORTHS 3342 RICHMOND VIC,2451.70,Groceries,Woolworths
        02 Sep 26,3200.00,083-123 12345678,,CREDIT,SALARY ACME PTY LTD,5651.70,Income,
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 2)
        #expect(rows.first.map { ymd($0.date) } == "2026-09-01")
        #expect(rows.first?.amount == money("58.30"))
        #expect(rows.first?.kind == .spend)
        #expect(rows.last?.kind == .moneyIn)
    }

    // MARK: ANZ: no header, three loose columns

    @Test func anzThreeColumnExportReadsEveryRow() {
        let csv = """
        01/09/2026,-58.30,VISA DEBIT PURCHASE CARD 1234 WOOLWORTHS 3342 RICHMOND
        02/09/2026,-5.50,VISA DEBIT PURCHASE CARD 1234 SEVEN SEEDS COFFEE
        03/09/2026,3200.00,SALARY ACME PTY LTD
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 3)
        #expect(rows.filter { $0.kind == .spend }.count == 2)
        #expect(rows.first?.amount == money("58.30"))
    }

    @Test func looseDateDescriptionAmountWithNoHeaderReadsEveryRow() {
        let csv = """
        15/09/2026,WOOLWORTHS,-58.30
        16/09/2026,7-ELEVEN,-12.00
        17/09/2026,KMART,-24.99
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 3)
        #expect(rows.map { ymd($0.date) } == ["2026-09-15", "2026-09-16", "2026-09-17"])
    }

    // MARK: Westpac: separate Debit Amount / Credit Amount

    @Test func westpacDebitAndCreditAmountColumns() {
        let csv = """
        Bank Account,Date,Narrative,Debit Amount,Credit Amount,Balance,Categories,Serial
        032-123 123456,01/09/2026,WOOLWORTHS 3342 RICHMOND VIC AUS,58.30,,2451.70,GROCERIES,
        032-123 123456,03/09/2026,SALARY ACME PTY LTD,,3200.00,5651.70,INCOME,
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 2)
        #expect(rows.first?.kind == .spend)
        #expect(rows.first?.amount == money("58.30"))
        #expect(rows.first?.detail.contains("WOOLWORTHS") == true)
        #expect(rows.last?.kind == .moneyIn)
    }

    // MARK: Up: ISO timestamps

    @Test func isoTimestampWithSpaceIsADate() {
        let csv = """
        Time,Description,Amount
        2026-09-01 12:34:56,Seven Seeds Coffee,-5.50
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 1)
    }

    /// An ISO 8601 stamp with a "T": "01T" has no word boundary, so the yyyy-mm-dd pattern never matches (Spend/Services/StatementImport.swift:325).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "full-money-05", "an ISO timestamp with a T (2026-09-01T12:34:56+10:00) is not read as a date, the row is dropped"))
    func isoTimestampWithTIsADate() {
        let csv = """
        Date,Description,Amount
        2026-09-01T12:34:56+10:00,Seven Seeds Coffee,-5.50
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 1, "the row was silently dropped")
    }

    /// Header words "time" and "total" are not in the date and amount lists, so the layout is guessed from the data and the first number column (Round Up) wins (Spend/Services/StatementImport.swift:111,119). Up export shape is from memory, not a real file.
    @Test(.bug(id: "full-money-09", "a header of Time and Total is not recognised, so the Round Up column is read as the amount"))
    func upStyleHeaderWithTimeAndTotalColumns() {
        let csv = """
        Time,Category,Description,Round Up,Total,Currency
        2026-09-01 12:34:56,Restaurants & Cafes,Seven Seeds Coffee,0,-5.50,AUD
        2026-09-02 08:01:00,Groceries,Woolworths,-0.30,-19.70,AUD
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 2)
        #expect(rows.first?.amount == money("5.50"), "amount is \(rows.first?.amount.description ?? "none")")
        #expect(rows.last?.amount == money("19.70"))
    }

    // MARK: Date shapes

    /// Day-Mon-year dates (Excel and several banks): the month-name pattern needs whitespace after the day (Spend/Services/StatementImport.swift:353).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "full-money-06", "01-Sep-2026 is not read as a date, the row is dropped"))
    func dayDashMonthNameDates() {
        let csv = """
        Date,Description,Amount
        01-Sep-2026,WOOLWORTHS,-58.30
        2-Sep-26,KMART,-24.99
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 2, "the 01-Sep-2026 style date was not read")
    }

    /// Same cause as the dash form: the month-name pattern only allows spaces.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "full-money-06", "01/Sep/2026 is not read as a date, the row is dropped"))
    func slashMonthNameDates() {
        let csv = """
        Date,Description,Amount
        01/Sep/2026,WOOLWORTHS,-58.30
        """
        #expect(StatementImport.rows(fromCSV: csv).count == 1)
    }

    @Test func aMonthOfAllAmbiguousDatesIsReadDayFirst() {
        let csv = """
        Date,Description,Amount
        03/04/2026,WOOLWORTHS,-58.30
        05/04/2026,KMART,-24.99
        """
        let rows = StatementImport.rows(fromCSV: csv).sorted { $0.date < $1.date }
        #expect(ymd(rows[0].date) == "2026-04-03")
    }

    // MARK: Odd amounts and files

    /// A true minus sign (Excel, Numbers and some locales write it): `signedAmount` only knows the ASCII hyphen (Spend/Services/StatementImport.swift:482).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "full-money-07", "an amount with a U+2212 minus sign is not read, the row is dropped"))
    func unicodeMinusIsARefundSign() {
        let csv = "Date,Description,Amount\n01/09/2026,WOOLWORTHS,\u{2212}58.30"
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 1, "the row with a \u{2212} sign was silently dropped")
    }

    /// A cell with an ISO code in front: `signedAmount` allows only a few symbols, not codes (Spend/Services/StatementImport.swift:482).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "full-money-08", "an amount cell written as AUD -58.30 is not read, the row is dropped"))
    func currencyCodeBeforeTheAmountIsRead() {
        let csv = "Date,Description,Amount\n01/09/2026,WOOLWORTHS,AUD -58.30"
        #expect(StatementImport.rows(fromCSV: csv).count == 1, "the row with 'AUD -58.30' was silently dropped")
    }

    @Test func aBOMAndBlankLinesAndASummaryLineAreIgnored() {
        let csv = "\u{FEFF}Date,Description,Amount\n\n01/09/2026,WOOLWORTHS,-58.30\n\nTotal,,-58.30\n"
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 1)
    }

    @Test func tenThousandRowsAllImport() throws {
        var lines = ["Date,Description,Amount"]
        let day = Calendar(identifier: .gregorian)
        for i in 0..<10_000 {
            var c = DateComponents(); c.year = 2025; c.month = 1; c.day = 1 + (i / 20)
            let d = day.date(byAdding: .day, value: i / 20, to: day.date(from: DateComponents(year: 2025, month: 1, day: 1))!)!
            _ = c
            let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; f.timeZone = .current
            lines.append("\(f.string(from: d)),SHOP NUMBER \(i) PTY,-\(10 + i % 90).\(String(format: "%02d", i % 100))")
        }
        let rows = StatementImport.rows(fromCSV: lines.joined(separator: "\n"))
        #expect(rows.count == 10_000)
        let ctx = try store()
        let result = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(result.added + result.merged == 10_000)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == result.added)
    }
}
