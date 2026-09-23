import Testing
import Foundation
import SwiftData
@testable import Sortd

/// Reading bank statements. The samples below are shaped like real exports
/// (AU, SG and US), with the awkward bits kept in: headerless files, running
/// balance columns, separate Debit/Credit columns, CR/DR suffixes and
/// bracketed negatives.
struct StatementImportTests {

    private func ymd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    // MARK: Amounts

    @Test(arguments: [
        ("12.50", Decimal(string: "12.50")!),
        ("-12.50", Decimal(string: "-12.50")!),
        ("1,234.56", Decimal(string: "1234.56")!),
        ("-1,234.56", Decimal(string: "-1234.56")!),
        ("(12.50)", Decimal(string: "-12.50")!),
        ("12.50 DR", Decimal(string: "-12.50")!),
        ("12.50 CR", Decimal(string: "12.50")!),
        ("$58.30", Decimal(string: "58.30")!),
        ("S$22.10", Decimal(string: "22.10")!),
        ("12", Decimal(12)),
        ("12.5", Decimal(string: "12.50")!),
    ])
    func readsOneAmountCell(text: String, expected: Decimal) {
        #expect(StatementImport.signedAmount(text)?.amount == expected)
    }

    @Test func aDescriptionIsNotAnAmount() {
        #expect(StatementImport.signedAmount("WOOLWORTHS 3342") == nil)
        #expect(StatementImport.signedAmount("") == nil)
        #expect(StatementImport.signedAmount("Balance") == nil)
    }

    @Test func picksUpCurrencyFromTheSymbol() {
        #expect(StatementImport.signedAmount("S$22.10")?.currency == "SGD")
        #expect(StatementImport.signedAmount("RM45.00")?.currency == "MYR")
        #expect(StatementImport.signedAmount("58.30")?.currency == nil)
    }

    // MARK: Dates

    @Test func readsTheUnambiguousFormats() {
        #expect(ymd(StatementImport.parseDate("2026-09-01", order: .auto)!) == "2026-09-01")
        #expect(ymd(StatementImport.parseDate("1 Sep 2026", order: .auto)!) == "2026-09-01")
        #expect(ymd(StatementImport.parseDate("01 September 2026", order: .auto)!) == "2026-09-01")
        #expect(ymd(StatementImport.parseDate("Sep 1, 2026", order: .auto)!) == "2026-09-01")
        #expect(ymd(StatementImport.parseDate("04 Sep 26", order: .auto)!) == "2026-09-04")
    }

    @Test func dayFirstAndMonthFirstAreDecidedForTheWholeFile() {
        // 25 can only be a day, so the whole file is day-first.
        #expect(StatementImport.detectOrder(in: ["25/12/2026", "01/02/2026"]) == .dayFirst)
        // 25 in second place can only be a day, so month-first.
        #expect(StatementImport.detectOrder(in: ["12/25/2026", "02/01/2026"]) == .monthFirst)
        // No proof either way: Sortd's markets write day first.
        #expect(StatementImport.detectOrder(in: ["01/02/2026"]) == .dayFirst)
    }

    @Test func theSameDigitsReadBothWays() {
        #expect(ymd(StatementImport.parseDate("01/02/2026", order: .dayFirst)!) == "2026-02-01")
        #expect(ymd(StatementImport.parseDate("01/02/2026", order: .monthFirst)!) == "2026-01-02")
    }

    @Test func impossibleDatesAreRejected() {
        #expect(StatementImport.parseDate("31/02/2026", order: .dayFirst) == nil)
        #expect(StatementImport.parseDate("00/01/2026", order: .dayFirst) == nil)
        #expect(StatementImport.parseDate("not a date", order: .dayFirst) == nil)
    }

    // MARK: CSV with a header

    @Test func readsACommBankStyleExport() {
        let csv = """
        Date,Description,Debit,Credit,Balance
        01/09/2026,WOOLWORTHS 3342 RICHMOND,58.30,,2451.70
        02/09/2026,SEVEN SEEDS COFFEE CARLTON,5.50,,2446.20
        03/09/2026,SALARY ACME PTY LTD,,3200.00,5646.20
        04/09/2026,REFUND KMART ONLINE,,38.00,5684.20
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 4)

        let spend = rows.filter { $0.kind == .spend }
        let moneyIn = rows.filter { $0.kind == .moneyIn }
        #expect(spend.count == 2)
        #expect(moneyIn.count == 2)

        #expect(spend[0].detail == "WOOLWORTHS 3342 RICHMOND")
        #expect(spend[0].amount == Decimal(string: "58.30")!)
        #expect(ymd(spend[0].date) == "2026-09-01")
        #expect(moneyIn[0].amount == Decimal(string: "3200.00")!)
    }

    @Test func aSignedAmountColumnSaysWhichWayTheMoneyWent() {
        let csv = """
        Date,Amount,Description
        01/09/2026,-58.30,WOOLWORTHS 3342
        03/09/2026,3200.00,SALARY
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 2)
        #expect(rows[0].kind == .spend)
        #expect(rows[0].amount == Decimal(string: "58.30")!)
        #expect(rows[1].kind == .moneyIn)
    }

    @Test func aRunningBalanceIsNotImportedAsAPurchase() {
        let csv = """
        Date,Description,Amount,Balance
        01/09/2026,WOOLWORTHS 3342,-58.30,2451.70
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 1)
        #expect(rows[0].amount == Decimal(string: "58.30")!)
    }

    @Test func handlesCommasInsideQuotedFields() {
        let csv = """
        Date,Description,Amount
        01/09/2026,"SMITH, JOHN & CO",-58.30
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 1)
        #expect(rows[0].detail == "SMITH, JOHN & CO")
    }

    @Test func handlesSemicolonAndTabExports() {
        let semi = """
        Date;Description;Amount
        01/09/2026;WOOLWORTHS 3342;-58.30
        """
        #expect(StatementImport.rows(fromCSV: semi).count == 1)

        let tab = "Date\tDescription\tAmount\n01/09/2026\tWOOLWORTHS 3342\t-58.30"
        #expect(StatementImport.rows(fromCSV: tab).count == 1)
    }

    @Test func aUSStatementIsReadMonthFirst() {
        let csv = """
        Date,Description,Amount
        09/01/2026,TRADER JOES,-58.30
        12/25/2026,AMAZON MARKETPLACE,-24.99
        """
        let rows = StatementImport.rows(fromCSV: csv).sorted { $0.date < $1.date }
        #expect(rows.count == 2)
        #expect(ymd(rows[0].date) == "2026-09-01")
        #expect(ymd(rows[1].date) == "2026-12-25")
    }

    // MARK: CSV without a header

    @Test func readsAHeaderlessExport() {
        // NAB's older export: date, amount, account, type, details, balance.
        let csv = """
        01/09/26,-58.30,084-234 12345678,EFTPOS,WOOLWORTHS 3342 RICHMOND,2451.70
        02/09/26,-5.50,084-234 12345678,EFTPOS,SEVEN SEEDS COFFEE CARLTON,2446.20
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 2)
        #expect(rows[0].kind == .spend)
        #expect(rows[0].amount == Decimal(string: "58.30")!)
        #expect(rows[0].detail.contains("WOOLWORTHS"))
        #expect(ymd(rows[0].date) == "2026-09-01")
    }

    @Test func emptyOrJunkInputGivesNothingRatherThanNonsense() {
        #expect(StatementImport.rows(fromCSV: "").isEmpty)
        #expect(StatementImport.rows(fromCSV: "hello\nworld").isEmpty)
        #expect(StatementImport.rows(fromCSV: "Date,Description\n01/09/2026,No amount here").isEmpty)
    }

    // MARK: PDF statements and screenshots

    @Test func readsLinesFromAPDFStatement() {
        let text = """
        Standard Chartered Bank (Singapore) Limited
        Statement of Account
        Account 12345678          Page 1 of 3

        01 Sep 2026   NTUC FAIRPRICE ORCHARD        22.10
        02 Sep 2026   GRAB *RIDE SINGAPORE          14.80
        03 Sep 2026   PAYMENT RECEIVED - THANK YOU  500.00 CR
        """
        let rows = StatementImport.rows(fromText: text)
        #expect(rows.count == 3)
        #expect(rows[0].detail.contains("NTUC FAIRPRICE"))
        #expect(rows[0].amount == Decimal(string: "22.10")!)
        #expect(rows[0].kind == .spend)
        #expect(rows[2].kind == .moneyIn)
    }

    @Test func skipsHeadersPageNumbersAndMarketing() {
        let text = """
        Your monthly statement
        Page 2 of 3
        Earn 10% back at selected partners. Terms apply.
        01/09/2026  WOOLWORTHS 3342   58.30
        """
        let rows = StatementImport.rows(fromText: text)
        #expect(rows.count == 1)
        #expect(rows[0].detail.contains("WOOLWORTHS"))
    }

    @Test func readsAScreenshotOfABankApp() {
        // What Vision gives back from a bank app's transaction list.
        let ocr = """
        Transactions
        1 Sep    Woolworths Richmond    -$58.30
        1 Sep    Seven Seeds Coffee     -$5.50
        31 Aug   Transfer from Savings  +$200.00
        """
        let rows = StatementImport.rows(fromText: ocr, today: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(rows.count == 3)
        #expect(rows[0].detail.contains("Woolworths"))
        #expect(rows[0].amount == Decimal(string: "58.30")!)
    }

    @Test func aStreetNumberIsNotTheAmount() {
        let text = "01/09/2026  MCDONALDS 123 GEORGE ST  12.50"
        let rows = StatementImport.rows(fromText: text)
        #expect(rows.count == 1)
        #expect(rows[0].amount == Decimal(string: "12.50")!)
        #expect(rows[0].detail.contains("MCDONALDS"))
    }

    @Test func theRunningBalanceOnAPDFLineIsNotTheAmount() {
        // Bug-hunt M2: the balance at the end of the line was taken as the purchase.
        let rows = StatementImport.rows(fromText: "02/09/2026  WOOLWORTHS METRO  12.50  1,034.20")
        #expect(rows.count == 1)
        #expect(rows[0].amount == Decimal(string: "12.50")!)
        #expect(rows[0].kind == .spend)
        let credit = StatementImport.rows(fromText: "02/09/2026  WOOLWORTHS METRO  12.50  1,034.20 CR")
        #expect(credit.first?.amount == Decimal(string: "12.50")!)
        #expect(credit.first?.kind == .spend)
    }

    @Test func fullWidthAndArabicDigitsDoNotCrash() {
        // Bug-hunt S1: \d matched these, Int() returned nil and the force unwrap trapped.
        for text in ["２０２６-０９-２１  NTUC FAIRPRICE  22.10",
                     "٢١/٠٩/٢٠٢٦  NTUC FAIRPRICE  22.10",
                     "１２ Sep ２０２６  GRAB  14.80"] {
            _ = StatementImport.rows(fromText: text)
        }
    }

    @Test func aShopNameIsNotAMonth() {
        // Bug-hunt M4: "12 MARKET" was read as 12 March.
        let rows = StatementImport.rows(fromText: "03/09/2026  CAFE 12 MARKET ST  5.50")
        #expect(rows.count == 1)
        let c = Calendar.current.dateComponents([.month, .day], from: rows[0].date)
        #expect(c.month == 9 && c.day == 3)
    }

    @Test func aDateWithNoYearIsNeverInTheFuture() {
        // Bug-hunt M5: "28 Dec" read on 5 Jan 2027 became 28 Dec 2027.
        var jan = DateComponents(); jan.year = 2027; jan.month = 1; jan.day = 5; jan.hour = 12
        let today = Calendar.current.date(from: jan)!
        let rows = StatementImport.rows(fromText: "28 Dec  COLES  40.00", today: today)
        #expect(rows.count == 1)
        #expect(Calendar.current.component(.year, from: rows[0].date) == 2026)
    }

    @Test func bracketedAmountsAreMoneyOut() {
        let text = "01/09/2026  WOOLWORTHS 3342  (58.30)"
        let rows = StatementImport.rows(fromText: text)
        #expect(rows.count == 1)
        #expect(rows[0].kind == .spend)
        #expect(rows[0].amount == Decimal(string: "58.30")!)
    }

    @Test func aLeadingPlusMeansMoneyIn() {
        // What a bank app's list looks like through OCR.
        let rows = StatementImport.rows(fromText: """
        1 Sep    Woolworths Richmond    -$58.30
        31 Aug   Transfer from Savings  +$200.00
        """, today: Date(timeIntervalSince1970: 1_790_000_000))

        #expect(rows.count == 2)
        #expect(rows[0].kind == .spend)
        #expect(rows[1].kind == .moneyIn)
        #expect(rows[1].amount == Decimal(string: "200.00")!)
        // The sign belongs to the amount, not the merchant name.
        #expect(rows[1].detail == "Transfer from Savings")
        #expect(rows[0].detail == "Woolworths Richmond")
    }

    @Test func aLineWithNoSignAtAllIsStillSpending() {
        let rows = StatementImport.rows(fromText: "01 Sep 2026   NTUC FAIRPRICE ORCHARD   22.10")
        #expect(rows.count == 1)
        #expect(rows[0].kind == .spend)
    }

    @Test func aLineWithNoAmountIsNotAPurchase() {
        #expect(StatementImport.rows(fromText: "01/09/2026 Opening balance").isEmpty)
    }

    @Test func aLineWithNoDateIsNotAPurchase() {
        #expect(StatementImport.rows(fromText: "WOOLWORTHS 3342   58.30").isEmpty)
    }

    // MARK: The trap

    @Test func moneyInIsNeverCountedAsSpending() {
        let csv = """
        Date,Description,Debit,Credit,Balance
        01/09/2026,WOOLWORTHS,58.30,,100.00
        02/09/2026,SALARY,,3200.00,3300.00
        03/09/2026,REFUND JB HI-FI,,199.00,3499.00
        """
        let rows = StatementImport.rows(fromCSV: csv)
        let spent = rows.filter { $0.kind == .spend }.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(spent == Decimal(string: "58.30")!)
    }
}

/// The statement import meeting the rest of the app: a line that Sortd
/// already has from an Apple Pay tap must be counted once, not twice.
@MainActor
struct StatementImportFlowTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func date(_ ymd: String, _ hm: String = "12:00") -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f.date(from: "\(ymd) \(hm)")!
    }

    private func log(_ ctx: ModelContext, _ p: IncomingPurchase) throws -> TransactionLogger.Outcome {
        try TransactionLogger.log(p, in: ctx)
    }

    @Test func aStatementLineMergesWithTheTapItAlreadyHas() throws {
        let ctx = try store()

        // Paid in store this morning; the tap logged it.
        _ = try log(ctx, IncomingPurchase(date: date("2026-09-01", "09:14"), merchant: "Seven Seeds",
                                          amount: Decimal(string: "5.50")!, currency: "AUD",
                                          card: .nab, source: .tap))

        // The statement arrives later with the same purchase.
        let csv = """
        Date,Description,Amount
        01/09/2026,SEVEN SEEDS COFFEE CARLTON,-5.50
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 1)

        for row in rows where row.kind == .spend {
            _ = try log(ctx, IncomingPurchase(date: row.date, merchant: row.detail,
                                              amount: row.amount, currency: row.currency ?? "AUD",
                                              card: .nab, source: .csv))
        }

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(all[0].amount == Decimal(string: "5.50")!)
        #expect(all[0].seenIn.contains(.tap))
    }

    @Test func importingTheSameStatementTwiceDoesNotDouble() throws {
        let ctx = try store()
        let csv = """
        Date,Description,Amount
        01/09/2026,WOOLWORTHS 3342,-58.30
        02/09/2026,COLES RICHMOND,-12.00
        """
        for _ in 0..<2 {
            for row in StatementImport.rows(fromCSV: csv) where row.kind == .spend {
                _ = try log(ctx, IncomingPurchase(date: row.date, merchant: row.detail,
                                                  amount: row.amount, currency: "AUD",
                                                  card: .nab, source: .csv))
            }
        }
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    @Test func twoIdenticalLinesInOneStatementAreTwoPurchases() throws {
        // Bug-hunt I1: the second "PTV 5.30" merged into the first.
        let ctx = try store()
        let rows = StatementImport.rows(fromText: """
        02/09/2026  PTV MYKI TOP UP  5.30
        02/09/2026  PTV MYKI TOP UP  5.30
        """)
        #expect(rows.count == 2)
        let first = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(first.added == 2)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
        // The same statement again still doesn't double.
        let again = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(again.added == 0)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    @Test func moneyInNeverReachesTheStore() throws {
        let ctx = try store()
        let csv = """
        Date,Description,Debit,Credit,Balance
        01/09/2026,WOOLWORTHS,58.30,,100.00
        02/09/2026,SALARY ACME,,3200.00,3300.00
        """
        // The screen only saves .spend rows; this is that rule, pinned.
        for row in StatementImport.rows(fromCSV: csv) where row.kind == .spend {
            _ = try log(ctx, IncomingPurchase(date: row.date, merchant: row.detail,
                                              amount: row.amount, currency: "AUD",
                                              card: .nab, source: .csv))
        }
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(all[0].merchant.lowercased().contains("woolworths"))
    }

    @Test func twoDifferentCoffeesOnTheSameDayBothSurvive() throws {
        let ctx = try store()
        let csv = """
        Date,Description,Amount
        01/09/2026,SEVEN SEEDS COFFEE,-5.50
        01/09/2026,MARKET LANE COFFEE,-4.80
        """
        for row in StatementImport.rows(fromCSV: csv) where row.kind == .spend {
            _ = try log(ctx, IncomingPurchase(date: row.date, merchant: row.detail,
                                              amount: row.amount, currency: "AUD",
                                              card: .nab, source: .csv))
        }
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }
}
