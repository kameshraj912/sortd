import Testing
import Foundation
@testable import Spend

/// Date, amount and layout shapes the statement importer must read, and the
/// count of rows it could not (never dropped without a word).
struct StatementImportReadingTests {

    private func ymd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    // MARK: Dates

    @Test(arguments: [
        ("2026-09-01T12:34:56+10:00", "2026-09-01"),
        ("2026-09-01T02:34:56Z", "2026-09-01"),
        ("2026-09-01T12:34:56.123+1000", "2026-09-01"),
        ("2026-09-01 12:34:56", "2026-09-01"),
        ("01-Sep-2026", "2026-09-01"),
        ("2-sep-26", "2026-09-02"),
        ("01/Sep/2026", "2026-09-01"),
        ("1 Sep 26", "2026-09-01"),
        ("01 September 2026", "2026-09-01"),
    ])
    func dateShapesAreRead(text: String, expected: String) {
        let date = StatementImport.parseDate(text, order: .dayFirst)
        #expect(date.map(ymd) == expected, "\(text)")
    }

    @Test func aWholeCellDateMayCarryATime() {
        #expect(StatementImport.isWholeDate("01/09/2026"))
        #expect(StatementImport.isWholeDate("01/09/2026 12:30"))
        #expect(StatementImport.isWholeDate("01/09/2026 9:05 PM"))
        #expect(StatementImport.isWholeDate("2026-09-01T12:34:56+10:00"))
        #expect(StatementImport.isWholeDate("1 Sep 26"))
    }

    @Test func aDescriptionWithADateInsideIsNotADateCell() {
        #expect(!StatementImport.isWholeDate("WOOLWORTHS Card xx1234 Value Date: 30/08/2026"))
        #expect(!StatementImport.isWholeDate("Paid 01/09/2026 to Kmart"))
        #expect(!StatementImport.isWholeDate(""))
        #expect(!StatementImport.isWholeDate("MARKET ST"))
    }

    @Test func aStreetNumberAndAMarketAreNotADate() {
        let rows = StatementImport.rows(fromText: "03/09/2026 CAFE 12 MARKET ST -12.50")
        #expect(rows.count == 1)
        #expect(rows.first.map { ymd($0.date) } == "2026-09-03")
        #expect(rows.first?.detail == "CAFE 12 MARKET ST")
    }

    // MARK: Layout

    @Test func theShopIsNeverTheBalanceColumn() {
        let csv = """
        01/09/2026,"-58.30","WOOLWORTHS 3342 RICHMOND VIC AUS Card xx1234 Value Date: 30/08/2026","+2451.70"
        02/09/2026,"-5.50","SEVEN SEEDS COFFEE Value Date: 31/08/2026","+2446.20"
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.detail.contains("Value Date") })
        #expect(rows.first?.amount == Decimal(string: "58.30"))
    }

    @Test func aRoundUpColumnIsNeverTheAmount() {
        let csv = """
        Time,Description,Round Up,Total
        2026-09-02 08:01:00,Woolworths,-0.30,-19.70
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.first?.amount == Decimal(string: "19.70"))
    }

    @Test(arguments: ["Timestamp", "Settled", "Time"])
    func timeStyleHeadersAreDateColumns(header: String) {
        let csv = "\(header),Description,Amount\n2026-09-01 08:00:00,Kmart,-24.99"
        #expect(StatementImport.rows(fromCSV: csv).count == 1, "\(header)")
    }
}

// MARK: - Amounts

extension StatementImportReadingTests {

    @Test func aTrueMinusSignAndAnEnDashAreRefundSigns() throws {
        let minus = try #require(StatementImport.signedAmount("\u{2212}58.30"))
        #expect(minus.amount == Decimal(string: "-58.30"))
        let dash = try #require(StatementImport.signedAmount("\u{2013}12.00"))
        #expect(dash.amount == Decimal(string: "-12.00"))
    }

    @Test func aTrueMinusInAFreeTextLineIsNotLeftInTheShopName() throws {
        let rows = StatementImport.rows(fromText: "01/09/2026 WOOLWORTHS \u{2212}58.30")
        #expect(rows.first?.detail == "WOOLWORTHS")
        #expect(rows.first?.amount == Decimal(string: "58.30"))
    }

    @Test func aCurrencyCodeBeforeOrAfterTheAmountIsRead() throws {
        let a = try #require(StatementImport.signedAmount("AUD -58.30"))
        #expect(a.amount == Decimal(string: "-58.30") && a.currency == "AUD")
        let b = try #require(StatementImport.signedAmount("SGD 12.00"))
        #expect(b.amount == Decimal(string: "12.00") && b.currency == "SGD")
        let c = try #require(StatementImport.signedAmount("12.00 sgd"))
        #expect(c.amount == Decimal(string: "12.00") && c.currency == "SGD")
        let d = try #require(StatementImport.signedAmount("-USD 5.50"))
        #expect(d.amount == Decimal(string: "-5.50") && d.currency == "USD")
    }

    @Test func threeLettersThatAreNotACurrencyAreNotAnAmount() {
        #expect(StatementImport.signedAmount("KFC 12") == nil)
        #expect(StatementImport.signedAmount("12 MARKET") == nil)
    }

    @Test func theCurrencyReachesTheRow() {
        let csv = "Date,Description,Amount\n01/09/2026,HAWKER,SGD -12.00"
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.first?.currency == "SGD")
        #expect(rows.first?.kind == .spend)
    }

    @Test func aPlusSignedBalanceIsNeverTheShop() throws {
        let a = try #require(StatementImport.signedAmount("+2451.70"))
        #expect(a.amount == Decimal(string: "2451.70"))
    }
}

// MARK: - Rows that could not be read

extension StatementImportReadingTests {

    @Test func unreadableCSVRowsAreCountedNotDropped() {
        let csv = """
        Date,Description,Amount
        01/09/2026,WOOLWORTHS,-58.30
        not a date,KMART,-24.99
        02/09/2026,MYSTERY,twelve dollars
        03/09/2026,,-5.00
        04/09/2026,SEVEN SEEDS,-5.50
        """
        let parsed = StatementImport.parse(csv: csv)
        #expect(parsed.rows.count == 2)
        #expect(parsed.skipped == 3)
        #expect(parsed.rows.count + parsed.skipped == 5)
    }

    @Test func aCleanFileSkipsNothing() {
        let csv = "Date,Description,Amount\n01/09/2026,WOOLWORTHS,-58.30\n02/09/2026,KMART,-24.99"
        let parsed = StatementImport.parse(csv: csv)
        #expect(parsed.rows.count == 2)
        #expect(parsed.skipped == 0)
    }

    @Test func aFileWithNoDateOrAmountColumnCountsEveryRowSkipped() {
        let parsed = StatementImport.parse(csv: "Name,Colour\nAda,Red\nBo,Blue")
        #expect(parsed.rows.isEmpty)
        #expect(parsed.skipped == 3)
    }

    @Test func aStatementLineWithADateButNoAmountIsCounted() {
        let text = """
        STATEMENT OF ACCOUNT
        01/09/2026 WOOLWORTHS 58.30
        02/09/2026 OPENING BALANCE CARRIED FORWARD
        Page 1 of 2
        """
        let parsed = StatementImport.parse(text: text)
        #expect(parsed.rows.count == 1)
        #expect(parsed.skipped == 1)
    }

    @Test func theNoteIsPlainAndSingularWhenOne() {
        #expect(StatementImport.skippedNote(0) == nil)
        #expect(StatementImport.skippedNote(1) == "1 row couldn't be read.")
        #expect(StatementImport.skippedNote(3) == "3 rows couldn't be read.")
    }

    @Test func rowsFromCSVStillReturnsJustTheRows() {
        let csv = "Date,Description,Amount\n01/09/2026,WOOLWORTHS,-58.30\nbad,KMART,-1.00"
        #expect(StatementImport.rows(fromCSV: csv).count == 1)
    }
}
