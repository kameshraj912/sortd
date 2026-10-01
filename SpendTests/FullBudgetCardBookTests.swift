import Testing
import Foundation
@testable import Spend

/// Adding, removing and re-adding cards in `CardBook`.
@MainActor
@Suite struct FullBudgetCardBookTests {
    private func book() -> CardBook {
        CardBook(defaults: UserDefaults(suiteName: "FullBudgetCardBookTests.\(UUID().uuidString)")!)
    }

    private func card(_ id: String, _ name: String, last4: [String] = [], words: [String] = []) -> CardInfo {
        CardInfo(id: id, name: name, shortName: name, bank: "NAB", currency: "AUD", country: "AU",
                 last4: last4, walletWords: words)
    }

    /// Fixing a typo by removing a card (it has purchases, so it is only
    /// archived) and adding it again with the same last 4: a receipt with
    /// those digits must go to the new, visible card. `card(last4:)` looks
    /// through archived cards too, and finds the old hidden one first.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a removed (archived) card still claims its last 4 ahead of the card added to replace it"))
    func aReplacementCardWithTheSameDigitsGetsTheReceipts() {
        let b = book()
        let old = card("old", "NAB Debit", last4: ["4821"])
        b.upsert(old)
        b.remove(old, hasPurchases: true)
        let new = card("new", "NAB Debit", last4: ["4821"])
        b.upsert(new)
        #expect(b.active.map(\.id) == ["new"])
        #expect(b.card(last4: "4821") == new.card, "receipt went to \(String(describing: b.card(last4: "4821")?.rawValue))")
    }

    @Test func aCardWithPurchasesIsArchivedNotDeleted() {
        let b = book()
        let a = card("a", "Card A")
        b.upsert(a)
        b.remove(a, hasPurchases: true)
        #expect(b.active.isEmpty)
        #expect(b.info(a.card)?.archived == true)
    }

    @Test func aCardWithNoPurchasesIsDeleted() {
        let b = book()
        let a = card("a", "Card A")
        b.upsert(a)
        b.remove(a, hasPurchases: false)
        #expect(b.info(a.card) == nil)
    }

    @Test func twoCardsWithTheSameNameStayTwoCards() {
        let b = book()
        b.upsert(card("a", "NAB Debit", last4: ["1111"]))
        b.upsert(card("b", "NAB Debit", last4: ["2222"]))
        #expect(b.active.count == 2)
        #expect(b.card(last4: "1111")?.rawValue == "a")
        #expect(b.card(last4: "2222")?.rawValue == "b")
    }

    @Test func aWalletNameWithDigitsPicksTheRightOfTwoSameBankCards() {
        let b = book()
        b.upsert(card("a", "NAB Debit", last4: ["1111"], words: ["nab"]))
        b.upsert(card("b", "NAB Debit 2", last4: ["2222"], words: ["nab"]))
        #expect(b.match("NAB Visa Debit ••2222").rawValue == "b")
    }

    @Test func oneActiveCardTakesUnmatchedDigitsAndTwoDoNot() {
        let b = book()
        b.upsert(card("a", "Card A"))
        #expect(b.noteUnmatchedDigits("9999")?.rawValue == "a")
        #expect(b.info(Card(rawValue: "a"))?.last4 == ["9999"])
        b.upsert(card("b", "Card B"))
        #expect(b.noteUnmatchedDigits("8888") == nil)
    }
}
