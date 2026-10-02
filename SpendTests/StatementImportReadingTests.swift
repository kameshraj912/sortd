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
