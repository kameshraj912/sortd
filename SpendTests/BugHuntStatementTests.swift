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
