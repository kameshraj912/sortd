import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt, 26 Sep 2026: statement import. Each test documents one unfixed
/// bug and fails today. They run only with `scripts/test.sh --known-bugs`.
///
/// The pure parser cases (CRLF, credit-card signs, the NAB header, the
/// foreign amount, absurd years) were reproduced by compiling
/// `StatementImport.swift` alone with `swiftc` and feeding it the same input.
/// The store cases (card currency, posting delay) are traced through
/// `StatementImport.save` and `TransactionLogger.log`.
@MainActor
struct BugHuntStatementTests {

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

    private func ymd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    private func money(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: 1. CRLF line endings

    /// A CSV with Windows line endings (CRLF, which RFC 4180 and most bank
    /// exports use) collapses into one row: `"\r\n"` is a single Swift
    /// `Character`, so `parseCSV`'s `case "\n", "\r"` never matches it and
    /// the line break is appended to the cell instead. A CommBank-style
    /// headerless file then yields one row with the first line's date, the
    /// first line's amount and the second line's merchant; every other
    /// purchase is lost. A file with a header yields no rows at all.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-stmt-1", "parseCSV never splits on CRLF: \"\\r\\n\" is one Character"))
    func aCRLFStatementKeepsEveryRow() {
        let commbank = "01/09/2026,\"-58.30\",\"WOOLWORTHS 3342 RICHMOND\",\"2451.70\"\r\n"
            + "02/09/2026,\"-5.50\",\"SEVEN SEEDS COFFEE CARLTON\",\"2446.20\"\r\n"
        let rows = StatementImport.rows(fromCSV: commbank)
        #expect(rows.count == 2)
        #expect(rows.first?.detail == "WOOLWORTHS 3342 RICHMOND")
        #expect(rows.first?.amount == money("58.30"))
        #expect(rows.last?.detail == "SEVEN SEEDS COFFEE CARLTON")
        #expect(rows.last?.amount == money("5.50"))

        let withHeader = "Date,Description,Amount\r\n01/09/2026,WOOLWORTHS 3342,-58.30\r\n02/09/2026,COLES RICHMOND,-12.00\r\n"
        #expect(StatementImport.rows(fromCSV: withHeader).count == 2)
    }

    // MARK: 2. Credit-card sign convention

    /// A credit-card export (Amex AU: Date, Description, Amount) lists
    /// purchases as positive numbers and the payment to the card as negative.
    /// `money(in:layout:)` assumes a bank account ("out is negative, in is
    /// positive"), so every purchase lands in "Money In — Not Added" and the
    /// $500 payment is the only ticked purchase. The right rule is not
    /// obvious from the sign alone; "PAYMENT RECEIVED" is the giveaway.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-stmt-2", "a signed Amount column is read with bank-account signs; credit-card exports invert"))
    func aCreditCardExportKeepsPurchasesAsSpending() {
        let amex = """
        Date,Description,Amount
        01/09/2026,WOOLWORTHS 3342 RICHMOND,58.30
        02/09/2026,SEVEN SEEDS COFFEE,5.50
        05/09/2026,PAYMENT RECEIVED - THANK YOU,-500.00
        """
        let rows = StatementImport.rows(fromCSV: amex)
        #expect(rows.count == 3)
        let spend = rows.filter { $0.kind == .spend }
        let moneyIn = rows.filter { $0.kind == .moneyIn }
        #expect(spend.count == 2)
        #expect(moneyIn.count == 1)
        #expect(moneyIn.first?.detail == "PAYMENT RECEIVED - THANK YOU")
        #expect(spend.reduce(Decimal(0)) { $0 + $1.amount } == money("63.80"))
    }

    // MARK: 3. The card's currency is ignored

    /// A statement's amounts are in the account's currency. A row with no
    /// currency symbol (most rows: "NTUC FAIRPRICE 22.10") is saved as
    /// `Money.home` (StatementImport.swift:224), not the chosen card's
    /// currency, so a Standard Chartered SGD statement on a phone whose home
    /// is AUD books S$22.10 as A$22.10, one for one, and `audAmount` is set
    /// so FX never corrects it.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-stmt-3", "StatementImport.save uses Money.home, not the card's currency, for rows with no symbol"))
    func aRowWithNoSymbolTakesTheCardsCurrency() throws {
        let ctx = try store()
        let foreign = Money.home == "SGD" ? "AUD" : "SGD"
        let info = CardInfo(id: "bughunt-stmt-\(foreign)", name: "Test \(foreign)", shortName: "Test",
                            currency: foreign, country: foreign == "SGD" ? "SG" : "AU")
        CardBook.shared.upsert(info)
        defer { CardBook.shared.remove(info, hasPurchases: false) }
        try #require(info.card.homeCurrency == foreign)

        let rows = StatementImport.rows(fromText: "01 Sep 2026   NTUC FAIRPRICE ORCHARD   22.10")
        try #require(rows.count == 1)
        #expect(rows[0].currency == nil)

        let result = StatementImport.save(rows, card: info.card, in: ctx)
        #expect(result.added == 1)
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(all.first?.currencyCode == foreign)
        #expect(all.first?.amount == money("22.10"))
    }

    // MARK: 4. "Transaction Type" steals the description column

    /// NAB's CSV header puts "Transaction Type" before "Transaction Details".
    /// `layout(for:)` matches the detail keyword "transaction" on the first
    /// of them and never looks again, so every purchase is named
    /// "EFTPOS DEBIT". Those rows then never merge with the Apple Pay tap for
    /// the same coffee (no name overlap), so each tapped purchase is counted
    /// twice after the import.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-stmt-4", "layout(for:) takes 'Transaction Type' as the description column"))
    func aTransactionTypeColumnIsNotTheMerchant() {
        let nab = """
        Date,Amount,Account Number,Empty,Transaction Type,Transaction Details,Balance,Category,Merchant Name
        01/09/2026,-58.30,084234 12345678,,EFTPOS DEBIT,WOOLWORTHS 3342 RICHMOND,2451.70,Groceries,WOOLWORTHS
        02/09/2026,-5.50,084234 12345678,,EFTPOS DEBIT,SEVEN SEEDS COFFEE CARLTON,2446.20,Cafe,SEVEN SEEDS
        """
        let rows = StatementImport.rows(fromCSV: nab)
        #expect(rows.count == 2)
        #expect(rows.first?.detail.contains("WOOLWORTHS") == true)
        #expect(rows.last?.detail.contains("SEVEN SEEDS") == true)
        #expect(rows.allSatisfy { $0.detail != "EFTPOS DEBIT" })
    }

    // MARK: 6. Weekend purchases post days later

    /// A Friday-evening tap and the same purchase on the statement dated the
    /// following Tuesday (banks post weekend spending on the next business
    /// day) are 3 days 17 hours apart. `Deduper.window` is 2 days, so the
    /// logger never sees the tap as a candidate and the coffee is counted
    /// twice.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-stmt-6", "a statement row posted more than 2 days after the tap is not merged"))
    func aTapPostedAfterTheWeekendStillMerges() throws {
        let ctx = try store()
        let tap = IncomingPurchase(date: date("2026-09-04", "19:00"), merchant: "Seven Seeds",
                                   amount: money("5.50"), currency: Money.home, card: .nab, source: .tap)
        _ = try TransactionLogger.log(tap, in: ctx)

        let rows = StatementImport.rows(fromCSV: """
        Date,Description,Amount
        08/09/2026,SEVEN SEEDS COFFEE CARLTON,-5.50
        """)
        try #require(rows.count == 1)
        let result = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(result.merged == 1)
        #expect(result.added == 0)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    // MARK: 7. A decimal number inside the description wins

    /// `lastAmount` takes the first number with cents as the purchase (the
    /// M2 fix, so a trailing balance is skipped). On a foreign purchase line
    /// the description carries the foreign amount ("24.99 USD"), so that is
    /// booked in the home currency and the real charge (36.50) is dropped
    /// into the merchant name. Either the home-currency figure or
    /// 24.99 marked as USD would be right; 24.99 in AUD is wrong money.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-stmt-7", "lastAmount takes the foreign amount in the description as the purchase"))
    func aForeignAmountInTheDescriptionIsNotThePurchase() {
        let rows = StatementImport.rows(fromText: "02/09/2026  AMAZON MKTPLACE SEATTLE 24.99 USD  36.50")
        #expect(rows.count == 1)
        guard let row = rows.first else { return }
        let bookedAsHome = row.amount == money("24.99") && row.currency == nil
        #expect(!bookedAsHome, "24.99 USD was booked as 24.99 in the home currency")
        #expect(row.amount == money("36.50") || row.currency == "USD")
        #expect(!row.detail.contains("36.50"))
    }

    // MARK: 8. Absurd years pass

    /// `make(year:month:day:)` accepts 1900...2200, so a mis-read year
    /// ("01/01/2099" from OCR, or a bad export) is imported as a purchase
    /// dated 2099 that sits at the top of the list forever and never falls
    /// in any month's total. attacks.md asks for these to be rejected.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-stmt-8", "dates in 1900 or 2099 are accepted as purchase dates"))
    func absurdYearsAreRejected() {
        #expect(StatementImport.parseDate("01/01/2099", order: .dayFirst) == nil)
        #expect(StatementImport.parseDate("01/01/1900", order: .dayFirst) == nil)
        let rows = StatementImport.rows(fromCSV: "Date,Description,Amount\n01/01/2099,WOOLWORTHS,-58.30")
        #expect(rows.isEmpty)
    }
}

/// Bug hunt, 3 Oct 2026: statement import. New findings only; the 26 Sep
/// ones above are still open and not repeated. A test tagged `.knownBug`
/// fails today and runs only with `scripts/test.sh --known-bugs`; the
/// untagged ones (stmt-4 to stmt-8) were fixed on `fix-hunt-a` and run
/// everywhere as regression tests.
@MainActor
struct BugHuntStatement1003Tests {

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

    private func money(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: 1. Re-import after a tap merge

    /// A statement row that merged into an Apple Pay tap is added again when
    /// the same statement (or an overlapping one) is imported a second time:
    /// the merged row keeps the tap's time (09:14) and now has `.csv` in
    /// `seenIn`, so `Deduper.match` treats the new `.csv` row as "same source"
    /// and needs the times within 10 minutes, but statement rows are at noon.
    @Test(.bug(id: "hunt-1003-stmt-1", "re-importing a statement doubles every row that merged with a tap"))
    func reimportingAfterATapMergeDoesNotDouble() throws {
        let ctx = try store()
        let tap = IncomingPurchase(date: date("2026-09-01", "09:14"), merchant: "Seven Seeds",
                                   amount: money("5.50"), currency: Money.home, card: .nab, source: .tap)
        _ = try TransactionLogger.log(tap, in: ctx)

        let rows = StatementImport.rows(fromCSV: """
        Date,Description,Amount
        01/09/2026,SEVEN SEEDS COFFEE CARLTON,-5.50
        """)
        try #require(rows.count == 1)
        let first = StatementImport.save(rows, card: .nab, in: ctx)
        try #require(first.merged == 1)

        let again = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(again.added == 0)
        #expect(again.merged == 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    /// Fixed by comparing statement rows by calendar day. Two identical lines
    /// in one statement are still two purchases, on the first import and when
    /// the same file is imported again; a coffee on two different days stays
    /// two as well.
    @Test func identicalLinesInOneStatementStayTwoRows() throws {
        let ctx = try store()
        let rows = StatementImport.rows(fromCSV: """
        Date,Description,Amount
        01/09/2026,SEVEN SEEDS COFFEE CARLTON,-5.50
        01/09/2026,SEVEN SEEDS COFFEE CARLTON,-5.50
        02/09/2026,SEVEN SEEDS COFFEE CARLTON,-5.50
        """)
        try #require(rows.count == 3)
        let first = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(first.added == 3)
        #expect(first.merged == 0)

        let again = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(again.added == 0)
        #expect(again.merged == 3)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 3)
    }

    // MARK: 2. A tap abroad never meets its statement line

    /// A tap in Singapore on an Australian card is logged as S$5.50; the AU
    /// statement lists the same purchase as A$6.12. Deduper.match used to need
    /// equal amount and currency, so the two never merged and the purchase was
    /// counted twice once the statement was imported. Now a tap or hand-typed
    /// purchase meets a statement line in another currency when the saved FX
    /// rate puts it within 6% of the statement amount and the names agree at
    /// 0.6 or better. The row keeps the foreign amount and currency, and the
    /// bank's home-currency amount becomes its home value.

    private let foreign = Money.home == "SGD" ? "AUD" : "SGD"
    private let tapDay = "2026-09-20"

    private func saveRate(_ rate: Decimal, in ctx: ModelContext) {
        ctx.insert(FXRate(key: FXService.savedRateKey(from: foreign, to: Money.home, on: date(tapDay)), rate: rate))
    }

    private func tapAbroad(_ amount: String, merchant: String = "Ya Kun Kaya Toast",
                           in ctx: ModelContext) throws {
        let tap = IncomingPurchase(date: date(tapDay, "13:05"), merchant: merchant,
                                   amount: money(amount), currency: foreign, card: .nab, source: .tap)
        _ = try TransactionLogger.log(tap, in: ctx)
    }

    private func statementLine(_ detail: String = "YA KUN KAYA TOAST SINGAPORE", amount: String = "6.12") -> [StatementImport.Row] {
        StatementImport.rows(fromCSV: """
        Date,Description,Amount
        20/09/2026,\(detail),-\(amount)
        """)
    }

    @Test(.bug(id: "hunt-1003-stmt-2", "a foreign-currency tap never merges with the home-currency statement row"))
    func aForeignTapMergesWithItsStatementLine() throws {
        let ctx = try store()
        saveRate(1.11, in: ctx)           // 5.50 x 1.11 = 6.105, bank charged 6.12
        try tapAbroad("5.50", in: ctx)
        let rows = statementLine()
        try #require(rows.count == 1)
        let result = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(result.merged == 1)
        #expect(result.added == 0)
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        // Original kept; the bank's figure is the home value.
        #expect(all.first?.amount == money("5.50"))
        #expect(all.first?.currencyCode == foreign)
        #expect(all.first?.audAmount == money("6.12"))
        #expect(all.first?.audValue == money("6.12"))
        #expect(all.first?.seenIn.contains(.csv) == true)
    }

    @Test func aStatementLineThenTheForeignTapMergesToo() throws {
        let ctx = try store()
        saveRate(1.11, in: ctx)
        let first = StatementImport.save(statementLine(), card: .nab, in: ctx)
        try #require(first.added == 1)
        try tapAbroad("5.50", in: ctx)
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(all.first?.amount == money("5.50"))
        #expect(all.first?.currencyCode == foreign)
        #expect(all.first?.audValue == money("6.12"))
    }

    @Test func aForeignMergeSurvivesTheNextStatementImportAndRateRefresh() async throws {
        let ctx = try store()
        saveRate(1.11, in: ctx)
        try tapAbroad("5.50", in: ctx)
        let rows = statementLine()
        _ = StatementImport.save(rows, card: .nab, in: ctx)
        let again = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(again.added == 0)
        #expect(again.merged == 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 1)
        // The rate refresh (it re-rates a foreign row when the day's rate is
        // saved) must not replace the bank's figure with the ECB one (6.11).
        _ = await FXService.backfill(in: ctx)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).first?.audValue == money("6.12"))
    }

    @Test func mergesWhenTheRateIsFivePercentOff() throws {
        let ctx = try store()
        saveRate(1.20, in: ctx)           // 5.35 x 1.20 = 6.42, which is 4.9% over 6.12
        try tapAbroad("5.35", in: ctx)
        let result = StatementImport.save(statementLine(), card: .nab, in: ctx)
        #expect(result.merged == 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    @Test func doesNotMergeWhenTheRateIsEightPercentOff() throws {
        let ctx = try store()
        saveRate(1.20, in: ctx)           // 5.50 x 1.20 = 6.60, which is 7.8% over 6.12
        try tapAbroad("5.50", in: ctx)
        let result = StatementImport.save(statementLine(), card: .nab, in: ctx)
        #expect(result.merged == 0)
        #expect(result.added == 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    @Test func doesNotMergeAForeignTapWithAWeakName() throws {
        let ctx = try store()
        saveRate(1.11, in: ctx)
        try tapAbroad("5.50", in: ctx)
        let rows = statementLine("KAYA TOAST HOUSE ORCHARD")
        // Passes the 0.3 used for the same currency, fails the 0.6 used here.
        let score = Deduper.similarity("Ya Kun Kaya Toast", "KAYA TOAST HOUSE ORCHARD")
        try #require(score >= 0.3 && score < 0.6)
        let result = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(result.merged == 0)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    @Test func doesNotMergeAForeignTapWhenThereIsNoRate() throws {
        let ctx = try store()
        try tapAbroad("5.50", in: ctx)
        let result = StatementImport.save(statementLine(), card: .nab, in: ctx)
        #expect(result.merged == 0)
        #expect(result.added == 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    @Test func twoStatementLinesInDifferentCurrenciesNeverMerge() {
        let day = date(tapDay)
        let a = Deduper.Candidate(date: day, merchant: "Ya Kun", amount: money("6.12"),
                                  currency: Money.home, card: .nab, source: .csv)
        let b = Deduper.Candidate(date: day, merchant: "Ya Kun", amount: money("5.50"),
                                  currency: foreign, card: .nab, source: .csv)
        #expect(Deduper.match(b, in: [a], convert: { amount, _, _, _ in amount * 1.11 }) == nil)
        // A tap against the same statement line does merge with the same rates.
        let tap = Deduper.Candidate(date: day, merchant: "Ya Kun", amount: money("5.50"),
                                    currency: foreign, card: .nab, source: .tap)
        #expect(Deduper.match(tap, in: [a], convert: { amount, _, _, _ in amount * 1.11 }) == 0)
        // And with no rates it does not.
        #expect(Deduper.match(tap, in: [a]) == nil)
    }

    @Test func sameCurrencyBehaviourIsUnchangedWithRatesSaved() throws {
        let ctx = try store()
        saveRate(1.11, in: ctx)
        let tap = IncomingPurchase(date: date(tapDay, "13:05"), merchant: "Seven Seeds",
                                   amount: money("5.50"), currency: Money.home, card: .nab, source: .tap)
        _ = try TransactionLogger.log(tap, in: ctx)
        // Same amount, same currency: merges as before.
        let same = StatementImport.save(statementLine("SEVEN SEEDS COFFEE CARLTON", amount: "5.50"), card: .nab, in: ctx)
        #expect(same.merged == 1)
        // A different amount in the same currency is still a new purchase.
        let other = StatementImport.save(statementLine("SEVEN SEEDS COFFEE CARLTON", amount: "6.12"), card: .nab, in: ctx)
        #expect(other.added == 1)
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.currencyCode == Money.home })
        #expect(all.contains { $0.amount == money("5.50") })
    }

    // MARK: 3. An account line on top sends the CSV to the free-text reader

    /// `ImportView` used to need 2+ separators on the first line to call a
    /// file a CSV. A CSV with an account line on top ("Account,NAB Classic
    /// ...", one comma) went to the free-text reader instead, where an
    /// unsigned number is spending: the $3,200 salary in the Credit column was
    /// listed as a ticked purchase. `StatementImport.reader(for:)` now looks
    /// past the first line, and `parse(statement:)` is what the screen runs.
    @Test(.bug(id: "hunt-1003-stmt-3", "a CSV with an account line on top is read as free text; credits become purchases"))
    func aCSVWithAnAccountLineOnTopKeepsTheSalaryOut() {
        let csv = """
        Account,NAB Classic Banking 084-234 12345678
        Date,Description,Debit,Credit,Balance
        01/09/2026,WOOLWORTHS 3342,58.30,,2451.70
        02/09/2026,SALARY ACME PTY LTD,,3200.00,5651.70
        """
        #expect(StatementImport.reader(for: csv) == .csv)
        // What ImportView actually runs for this file.
        let spend = StatementImport.parse(statement: csv).rows.filter { $0.kind == .spend }
        #expect(!spend.contains { $0.detail.contains("SALARY") })
        #expect(spend.reduce(Decimal(0)) { $0 + $1.amount } == money("58.30"))
        #expect(spend.allSatisfy { !$0.detail.contains("2451.70") })
    }

    /// Pasted text (one shop and amount per line, no separators) and PDF text
    /// with thousands commas still go to the text reader, and so does anything
    /// that was scanned, even if it happens to look like a CSV.
    @Test func plainTextAndScansStillGoToTheTextReader() {
        let pasted = """
        01 Sep 2026 Woolworths 58.30
        02 Sep 2026 Seven Seeds Coffee 5.50
        03 Sep 2026 Kmart Burwood 22.00
        """
        #expect(StatementImport.reader(for: pasted) == .text)
        #expect(StatementImport.parse(statement: pasted).rows.count == 3)

        let pdf = """
        Statement period 1 Sep to 30 Sep 2026
        01 Sep 2026 Woolworths 1,258.30
        02 Sep 2026 Seven Seeds Coffee 5.50
        """
        #expect(StatementImport.reader(for: pdf) == .text)

        let csv = "Date,Description,Amount\n01/09/2026,WOOLWORTHS,-58.30\n02/09/2026,COLES,-12.00"
        #expect(StatementImport.reader(for: csv) == .csv)
        #expect(StatementImport.reader(for: csv, wasScanned: true) == .text)
        #expect(StatementImport.reader(for: "") == .text)
    }

    // MARK: 4. "0.00" in the unused Debit column

    /// With Debit/Credit columns, `money(in:layout:)` takes the Debit cell
    /// whenever it parses, and "0.00" parses. A salary row written as
    /// "0.00,3200.00" becomes a ticked $0.00 purchase named SALARY, saved
    /// to the store, and the credit is never listed as money in.
    @Test(.bug(id: "hunt-1003-stmt-4", "a 0.00 Debit cell wins over the Credit cell; credits become $0 purchases"))
    func aZeroInTheUnusedColumnIsNotAPurchase() throws {
        let rows = StatementImport.rows(fromCSV: """
        Date,Description,Debit,Credit,Balance
        01/09/2026,WOOLWORTHS 3342,58.30,0.00,2451.70
        02/09/2026,SALARY ACME PTY LTD,0.00,3200.00,5651.70
        """)
        #expect(rows.count == 2)
        let salary = rows.first { $0.detail.contains("SALARY") }
        #expect(salary?.kind == .moneyIn)
        #expect(salary?.amount == money("3200.00"))

        let ctx = try store()
        let result = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(result.added == 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).allSatisfy { $0.amount > 0 })
    }

    // MARK: 5. Decimal commas

    /// A semicolon CSV with decimal commas ("-12,50", the European format,
    /// which is why `parseCSV` supports ";") reads no rows at all:
    /// `signedAmount`'s pattern only knows "." for cents, so every row is
    /// "couldn't be read".
    @Test(.bug(id: "hunt-1003-stmt-5", "signedAmount does not read decimal commas, so a ; CSV imports nothing"))
    func aSemicolonCSVWithDecimalCommasIsRead() {
        let parsed = StatementImport.parse(csv: """
        Date;Description;Amount
        01/09/2026;CARREFOUR PARIS;-12,50
        02/09/2026;MONOPRIX;-8,20
        """)
        #expect(parsed.rows.count == 2)
        #expect(parsed.skipped == 0)
        #expect(parsed.rows.first?.amount == money("12.50"))
        #expect(parsed.rows.last?.amount == money("8.20"))
    }

    // MARK: 6. Screenshots with the date on its own line

    /// "Choose a Screenshot" asks for "a picture of your bank app's list",
    /// but `parse(text:)` only keeps a line that has a date and an amount
    /// together. Apple Wallet's card list puts the merchant and amount on one
    /// line and the day ("Yesterday", "26/09/2026") on a line below; bank
    /// apps group rows under a date header. Both read as zero purchases.
    @Test(.bug(id: "hunt-1003-stmt-6", "screenshot import needs date and amount on one line; Wallet and bank-app lists read as nothing"))
    func aWalletOrBankAppListIsRead() {
        let today = date("2026-10-03")
        let wallet = StatementImport.rows(fromText: """
        Latest Transactions
        Seven Seeds Coffee $5.50
        Carlton VIC
        Yesterday
        Woolworths $58.30
        Richmond VIC
        Thursday
        Kmart Burwood $22.00
        Burwood VIC
        26/09/2026
        """, today: today)
        #expect(wallet.count == 3)
        #expect(wallet.map(\.amount) == [money("5.50"), money("58.30"), money("22.00")])

        let bankApp = StatementImport.rows(fromText: """
        Fri 26 Sep
        Woolworths Richmond -$58.30
        Seven Seeds Coffee -$5.50
        Thu 25 Sep
        Kmart Burwood -$22.00
        """, today: today)
        #expect(bankApp.count == 3)
    }

    // MARK: 7. UTF-16 files

    /// Excel's "Unicode Text" export is UTF-16 with a BOM. `decodeText`
    /// tries UTF-8, then Windows-1252, which accepts those bytes and turns
    /// them into "ÿþD\0a\0t\0e..." So the import says nothing was found.
    @Test(.bug(id: "hunt-1003-stmt-7", "decodeText reads a UTF-16 file as Windows-1252 garbage"))
    func aUTF16FileIsDecoded() throws {
        let text = "Date,Description,Amount\n01/09/2026,WOOLWORTHS 3342,-58.30\n"
        let data = try #require(text.data(using: .utf16))
        let decoded = StatementReader.decodeText(data)
        #expect(decoded?.contains("WOOLWORTHS 3342") == true)
        #expect(StatementImport.rows(fromCSV: decoded ?? "").count == 1)
    }

    // MARK: 8. Pubs and bakeries lose their name on a receipt

    /// `ReceiptScanner.merchant` skips any line containing "tel", "table",
    /// "time", "order", "copy" and so on as substrings, so "ROYAL HOTEL"
    /// (and "PASTEL BAKERY") is skipped and the next line ("Public Bar") is
    /// used as the shop. Australian pubs are nearly all "... Hotel".
    @Test(.bug(id: "hunt-1003-stmt-8", "receipt merchant skip words match inside HOTEL and PASTEL"))
    func aHotelReceiptKeepsItsName() {
        #expect(ReceiptScanner.merchant(in: """
        ROYAL HOTEL
        Public Bar
        Tax Invoice
        Carlton Draught  9.50
        TOTAL $9.50
        """) == "Royal Hotel")
        #expect(ReceiptScanner.merchant(in: """
        PASTEL BAKERY
        Croissant  5.50
        TOTAL $5.50
        """) == "Pastel Bakery")
    }
}

/// Bug hunt, 8 Oct 2026: statement import. New findings only; the 26 Sep and
/// 3 Oct ones above are not repeated. Each test fails today and runs only
/// with `scripts/test.sh --known-bugs`. The parser cases were reproduced by
/// compiling `StatementImport.swift` (save functions removed) with `swiftc`
/// and feeding it the same input.
@MainActor
struct BugHuntStatement1008Tests {

    private func date(_ ymd: String, _ hm: String = "12:00", zone: TimeZone = .current) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = zone
        return f.date(from: "\(ymd) \(hm)")!
    }

    private func ymd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    private func money(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: 1. Summary lines in a PDF statement are purchases

    /// `parse(text:)` keeps any line with a date and a number, and only the
    /// screenshot fallback skips summary lines (`isSummaryLine`). A PDF
    /// credit-card statement's "Statement Period", "Closing Balance" and
    /// "Minimum Payment Due" lines are listed as ticked purchases of $30,
    /// $1,234.56 and $35.00.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-1008-stmt-1", "PDF summary lines (period, closing balance, minimum payment) are read as purchases"))
    func pdfSummaryLinesAreNotPurchases() {
        let pdf = """
        Statement Period 01/09/2026 - 30/09/2026
        Closing Balance as at 30/09/2026 $1,234.56
        Payment Due Date 25/10/2026 Minimum Payment Due $35.00
        02/09/2026 WOOLWORTHS 3342 58.30
        03/09/2026 SEVEN SEEDS 5.50
        """
        #expect(StatementImport.reader(for: pdf) == .text)
        let spend = StatementImport.parse(statement: pdf).rows.filter { $0.kind == .spend }
        #expect(spend.count == 2)
        #expect(spend.reduce(Decimal(0)) { $0 + $1.amount } == money("63.80"))
        #expect(!spend.contains { $0.detail.lowercased().contains("balance") })
        #expect(!spend.contains { $0.detail.lowercased().contains("minimum payment") })
        #expect(!spend.contains { $0.detail.lowercased().contains("statement period") })
    }

    // MARK: 2. Quoted thousands send a CSV to the text reader

    /// `reader(for:)` counts every comma on a line, including the ones inside
    /// quoted cells ("1,141.70"). A Debit/Credit CSV whose balance crosses
    /// $1,000 has uneven counts, so it goes to the free-text reader, where an
    /// unsigned number is spending: the $3,200 salary in the Credit column is
    /// a ticked purchase and every shop name carries commas and the balance.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-1008-stmt-2", "reader(for:) counts commas inside quotes; a CSV with quoted thousands is read as text"))
    func aCSVWithQuotedThousandsIsStillACSV() {
        let csv = """
        Date,Description,Debit,Credit,Balance
        01/09/2026,WOOLWORTHS 3342,58.30,,"1,141.70"
        02/09/2026,SEVEN SEEDS,5.50,,"1,136.20"
        03/09/2026,RENT PAYMENT,"1,000.00",,136.20
        04/09/2026,KMART BURWOOD,22.00,,114.20
        05/09/2026,COLES CARLTON,40.00,,74.20
        06/09/2026,SALARY ACME PTY LTD,,"3,200.00","3,274.20"
        07/09/2026,MYKI TOPUP,20.00,,"3,254.20"
        08/09/2026,ALDI BRUNSWICK,30.00,,"3,224.20"
        09/09/2026,BP CARLTON,60.00,,"3,164.20"
        """
        #expect(StatementImport.reader(for: csv) == .csv)
        let rows = StatementImport.parse(statement: csv).rows
        let spend = rows.filter { $0.kind == .spend }
        #expect(!spend.contains { $0.detail.contains("SALARY") })
        #expect(spend.reduce(Decimal(0)) { $0 + $1.amount } == money("1235.80"))
        #expect(rows.first?.detail == "WOOLWORTHS 3342")
    }

    // MARK: 3. Decimal commas in a PDF or screenshot

    /// The ";" CSV fix (S3) taught `signedAmount` decimal commas, but
    /// `lastAmount` (PDF text and screenshots) still only knows "." for
    /// cents. "CARREFOUR 12,50" is booked as 50.00, "-8,20" as 8.00 and
    /// "1.234,50" as 50.00.
    @Test(.bug(id: "hunt-1008-stmt-3", "lastAmount reads 12,50 as 50 and -8,20 as 8 in PDF and screenshot text"))
    func decimalCommasInTextAreRead() {
        let rows = StatementImport.rows(fromText: """
        01/09/2026 CARREFOUR PARIS 12,50
        02/09/2026 MONOPRIX -8,20
        03/09/2026 LIDL BERLIN 1.234,50
        04/09/2026 EDEKA HAMBURG -1.234,56
        """)
        #expect(rows.count == 4)
        #expect(rows.map(\.amount) == [money("12.50"), money("8.20"), money("1234.50"), money("1234.56")])
        #expect(rows.allSatisfy { !$0.detail.contains(",") })
        // Unchanged: dot cents and comma thousands, with a balance after.
        let au = StatementImport.rows(fromText: "05/09/2026 RENT PAYMENT 1,234.50 2,451.70")
        #expect(au.map(\.amount) == [money("1234.50")])
        #expect(au.first?.detail.hasPrefix("RENT PAYMENT") == true)
    }

    // MARK: 3b. Lakh-grouped rupees (S4)

    /// "1,23,456.00" is how India writes 123,456.00. A CSV cell with it was
    /// skipped, and the text reader read "₹1,23,456.00" as ₹1.
    @Test(.bug(id: "hunt-1008-S4", "lakh amounts are skipped in a CSV and read as ₹1 in text"))
    func lakhAmountsAreRead() {
        let csv = StatementImport.parse(csv: """
        Date,Description,Amount
        01/09/2026,FLIPKART BENGALURU,"-1,23,456.00"
        02/09/2026,SWIGGY,-450.00
        """)
        #expect(csv.skipped == 0)
        #expect(csv.rows.map(\.amount) == [money("123456.00"), money("450.00")])
        #expect(csv.rows.first?.kind == .spend)

        let text = StatementImport.rows(fromText: """
        01/09/2026 FLIPKART BENGALURU ₹1,23,456.00
        02/09/2026 CROMA MUMBAI 12,34,567.50
        """)
        #expect(text.map(\.amount) == [money("123456.00"), money("1234567.50")])
        #expect(text.first?.currency == "INR")
        #expect(text.map(\.detail) == ["FLIPKART BENGALURU", "CROMA MUMBAI"])
    }

    // MARK: 4. A Currency column is ignored

    /// Revolut and Wise export the amount and its currency in separate
    /// columns. `layout(for:)` has no currency column, so a EUR card payment
    /// has no currency and `save` books it in the home currency: EUR 12.50
    /// becomes A$12.50 (or S$12.50), one for one.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-1008-stmt-4", "a CSV Currency column is ignored; foreign rows are booked in the home currency"))
    func aCurrencyColumnIsRead() {
        let revolut = """
        Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
        CARD_PAYMENT,Current,2026-09-01 10:00:00,2026-09-02 10:00:00,Carrefour,-12.50,0.00,EUR,COMPLETED,100.00
        CARD_PAYMENT,Current,2026-09-03 18:30:00,2026-09-04 09:00:00,Tesco,-8.00,0.00,GBP,COMPLETED,50.00
        """
        let rows = StatementImport.rows(fromCSV: revolut)
        #expect(rows.count == 2)
        #expect(rows.first?.amount == money("12.50"))
        #expect(rows.first?.currency == "EUR")
        #expect(rows.last?.currency == "GBP")
    }

    // MARK: 5. A number at the start of a shop name becomes the year

    /// On a statement with year-less dates ("27 Sep"), a shop name starting
    /// with digits is read as the year. "29 Sep 1300 SMILES" fails as year
    /// 1300, then the "Sep 13" + "00" pattern dates it 13 Sep 2000;
    /// "30 Sep 99 BIKES" is dated 30 Sep 1999. Both fall out of every month's
    /// total.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-1008-stmt-5", "a year-less line whose shop starts with digits takes them as the year"))
    func aShopNameStartingWithDigitsIsNotTheYear() {
        let rows = StatementImport.rows(fromText: """
        27 Sep WOOLWORTHS 3342 58.30
        29 Sep 1300 SMILES DENTAL 120.00
        30 Sep 99 BIKES RICHMOND 45.00
        """, today: date("2026-10-03"))
        #expect(rows.count == 3)
        #expect(rows.map { ymd($0.date) } == ["2026-09-27", "2026-09-29", "2026-09-30"])
    }

    // MARK: 6. "2 hours ago" in a Wallet list

    /// For a purchase made today, Wallet's list shows how long ago it was
    /// (from memory; no real Wallet screenshot is in the repo). In
    /// `groupedByDay` that line is not a day, and `lastAmount` reads the "2"
    /// as money: a ticked $2.00 purchase called "hours ago", and today's
    /// coffee is filed under the next day line, yesterday.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-1008-stmt-6", "Wallet's '2 hours ago' is read as a $2 purchase and today's row takes yesterday's date"))
    func aWalletRowFromTodayIsReadAsToday() {
        let rows = StatementImport.rows(fromText: """
        Latest Transactions
        Seven Seeds Coffee $5.50
        Carlton VIC
        2 hours ago
        Woolworths $58.30
        Richmond VIC
        Yesterday
        """, today: date("2026-10-03", "15:00"))
        #expect(rows.map(\.detail) == ["Seven Seeds Coffee", "Woolworths"])
        #expect(rows.map(\.amount) == [money("5.50"), money("58.30")])
        #expect(rows.first.map { ymd($0.date) } == "2026-10-03")
    }

    // MARK: 7. Credits in a PDF statement's Credit column

    /// A PDF statement with Debit, Credit and Balance columns loses the
    /// columns in its text. `lastAmount` treats an amount with no sign as
    /// spending, so the salary and the JB Hi-Fi refund are ticked purchases,
    /// though the balance on the same line goes up. The balance is also left
    /// in every shop name. The right rule is a design call (the balance
    /// movement says which way the money went).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-1008-stmt-7", "a PDF credit with no CR or + is a purchase even when the balance goes up"))
    func aPDFCreditIsNotAPurchase() {
        let rows = StatementImport.rows(fromText: """
        01 Sep 2026 OPENING BALANCE $2,451.70 CR
        02 Sep 2026 WOOLWORTHS 3342 58.30 $2,393.40 CR
        03 Sep 2026 SALARY ACME PTY LTD 3,200.00 $5,593.40 CR
        04 Sep 2026 SEVEN SEEDS 5.50 $5,587.90 CR
        05 Sep 2026 REFUND JB HI-FI 199.00 $5,786.90 CR
        """)
        let spend = rows.filter { $0.kind == .spend }
        #expect(spend.map(\.amount) == [money("58.30"), money("5.50")])
        #expect(!spend.contains { $0.detail.contains("SALARY") || $0.detail.contains("REFUND") })
        #expect(spend.allSatisfy { !$0.detail.contains("$") })
    }

    // MARK: 8. Re-importing after a long flight

    /// Statement rows are saved at noon on the phone's clock, and a re-import
    /// is only a re-send on the same calendar day. Imported in Melbourne,
    /// then again in New York, noon 1 Sep AEST is 31 Aug in New York, so
    /// every row of the overlapping statement is added a second time.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-1008-stmt-8", "a statement re-imported after a 14-hour time-zone move doubles every row"))
    func reimportingInAnotherTimeZoneDoesNotDouble() throws {
        let melbourne = try #require(TimeZone(identifier: "Australia/Melbourne"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = newYork
        var mel = Calendar(identifier: .gregorian)
        mel.timeZone = melbourne

        let csv = "Date,Description,Amount\n01/09/2026,SEVEN SEEDS COFFEE CARLTON,-5.50"
        let first = try #require(StatementImport.rows(fromCSV: csv, calendar: mel).first)
        let again = try #require(StatementImport.rows(fromCSV: csv, calendar: ny).first)

        let saved = Deduper.Candidate(date: first.date, merchant: first.detail, amount: first.amount,
                                      currency: "AUD", card: .nab, source: .csv, seenIn: [.csv])
        let reimport = Deduper.Candidate(date: again.date, merchant: again.detail, amount: again.amount,
                                         currency: "AUD", card: .nab, source: .csv)
        #expect(Deduper.match(reimport, in: [saved], calendar: ny) == 0)
    }

    // MARK: 9. US card statements with month/day dates

    /// US card statements print "09/28" with no year. `firstDate` needs a
    /// year for a numeric date, so no line has a date, the day-header
    /// fallback finds none either, and the import says "No purchases found"
    /// with nothing counted as unreadable.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-1008-stmt-9", "numeric dates with no year (09/28) are never read; a US card statement imports nothing"))
    func monthDayDatesWithNoYearAreRead() {
        let parsed = StatementImport.parse(text: """
        09/28 STARBUCKS STORE 12345 SEATTLE WA 5.75
        09/29 AMAZON.COM 24.99
        09/30 SHELL OIL 57444 45.10
        """, today: date("2026-10-03"))
        #expect(parsed.rows.count == 3)
        #expect(parsed.rows.map { ymd($0.date) } == ["2026-09-28", "2026-09-29", "2026-09-30"])
    }
}
