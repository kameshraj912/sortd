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
