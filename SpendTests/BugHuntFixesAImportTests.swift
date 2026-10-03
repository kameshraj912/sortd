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
}
