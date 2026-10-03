import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt 3 Oct 2026, fixed on `fix-hunt-a`: The statement import's card (S5).
/// Each test failed before its fix. Helpers: `HuntA`.
@MainActor
struct BugHuntFixesAImportTests {

    private func store() throws -> ModelContext { try HuntA.store() }
    private func date(_ ymd: String, _ hm: String = "12:00") -> Date { HuntA.date(ymd, hm) }
    private func money(_ s: String) -> Decimal { HuntA.money(s) }
    private func calendar(_ id: Calendar.Identifier, _ zone: TimeZone = .current) -> Calendar { HuntA.calendar(id, zone) }
    private func ymd(_ d: Date?) -> String? { HuntA.ymd(d) }

    // MARK: S5. The import's card is not silently the first card

    private func book(_ cards: [CardInfo]) -> CardBook {
        let name = "bughunt-fixes-a-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let book = CardBook(defaults: defaults)
        book.replaceAll(cards)
        return book
    }

    private let nab = CardInfo(id: "hunt-nab", name: "NAB Visa Debit", shortName: "NAB", bank: "NAB",
                               last4: ["4821"], walletWords: ["nab"])
    private let anz = CardInfo(id: "hunt-anz", name: "ANZ Access Visa", shortName: "ANZ", bank: "ANZ",
                               last4: ["7730"], walletWords: ["anz"])

    @Test func aStatementThatNamesNoCardIsNotFiledUnderTheFirstCard() {
        let two = book([nab, anz])
        #expect(two.statementCard(in: "Date,Amount,Description\n01/09/2026,-5.50,SEVEN SEEDS COFFEE CARLTON") == .other)
        // Named by its bank or its card digits on top: that card.
        #expect(two.statementCard(in: "ANZ Access Advantage\nStatement 1 Sep to 30 Sep 2026\n01/09 SEVEN SEEDS 5.50") == anz.card)
        #expect(two.statementCard(in: "Card ending 7730\n01/09/2026,-5.50,SEVEN SEEDS") == anz.card)
        // With one card there is nothing to confuse.
        #expect(book([nab]).statementCard(in: "Date,Amount,Description\n01/09/2026,-5.50,SEVEN SEEDS") == nab.card)
    }

    /// With "Card not known" the statement row finds the ANZ tap and is not doubled.
    @Test func aStatementRowWithNoCardMergesWithTheTapOnAnyCard() throws {
        let ctx = try store()
        _ = try TransactionLogger.log(IncomingPurchase(date: date("2026-09-01", "09:14"), merchant: "Seven Seeds",
                                                       amount: money("5.50"), currency: "AUD", card: anz.card, source: .tap), in: ctx)
        let rows = StatementImport.rows(fromCSV: "Date,Amount,Description\n01/09/2026,-5.50,SEVEN SEEDS COFFEE CARLTON")
        let saved = StatementImport.save(rows.map { var r = $0; r.currency = "AUD"; return r },
                                         card: book([nab, anz]).statementCard(in: "Date,Amount,Description"), in: ctx)
        #expect(saved.merged == 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    // MARK: S4. Screenshots that put the day on its own line

    /// Apple Wallet's card list: the day sits under each purchase. Synthetic
    /// OCR-style text (no real Wallet screenshot in the repo). 3 Oct 2026 is a
    /// Saturday, so "Thursday" is 1 Oct.
    @Test func aWalletListTakesTheDayUnderEachPurchase() {
        let rows = StatementImport.rows(fromText: """
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
        """, today: date("2026-10-03"))
        #expect(rows.map(\.detail) == ["Seven Seeds Coffee", "Woolworths", "Kmart Burwood"])
        #expect(rows.map { ymd($0.date) } == ["2026-10-02", "2026-10-01", "2026-09-26"])
        #expect(rows.allSatisfy { $0.kind == .spend })
    }

    /// A bank app: day headers above the purchases, and the balance on top
    /// (synthetic OCR-style text). The balance is not a purchase.
    @Test func aBankAppListTakesTheDayAboveAndSkipsTheBalance() {
        let parsed = StatementImport.parse(text: """
        Everyday Account
        Available balance $1,234.56
        Today
        Uber Eats -$31.40
        Yesterday
        Woolworths Richmond -$58.30
        Fri 25 Sep
        Seven Seeds Coffee -$5.50
        """, today: date("2026-10-03"))
        #expect(parsed.rows.map(\.detail) == ["Uber Eats", "Woolworths Richmond", "Seven Seeds Coffee"])
        #expect(parsed.rows.map { ymd($0.date) } == ["2026-10-03", "2026-10-02", "2026-09-25"])
        #expect(parsed.skipped == 0)
    }

    /// Unchanged: a statement whose lines carry their own date is read the
    /// old way, and a line with an amount but no date is still not a row.
    @Test func aStatementWithDatedLinesIsReadAsBefore() {
        let rows = StatementImport.rows(fromText: """
        Opening balance 1,234.00
        01/09/2026 WOOLWORTHS 3342 58.30
        02/09/2026 SEVEN SEEDS 5.50
        Closing balance 1,170.20
        """, today: date("2026-10-03"))
        #expect(rows.map(\.detail) == ["WOOLWORTHS 3342", "SEVEN SEEDS"])
    }
}
