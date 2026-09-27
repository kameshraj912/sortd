import Testing
import Foundation
@testable import Spend

/// `CardBook.noteUnmatchedDigits` / `assign`: settling unknown last-4 digits
/// from a receipt or bank alert onto Raj's cards (spec 2026-09-27, part of
/// "Which card?"). `EmailSyncTests` covers the same rule wired through
/// `EmailSync.importRecords`.
@MainActor
struct CardDigitsAssignmentTests {
    private func book(_ cards: [CardInfo] = []) -> CardBook {
        let b = CardBook(defaults: UserDefaults(suiteName: "card-digits-\(UUID().uuidString)")!)
        cards.forEach(b.upsert)
        return b
    }

    @Test func oneActiveCardSettlesUnmatchedDigitsWithNoPrompt() {
        let b = book([CardInfo(name: "NAB Debit", shortName: "NAB")])
        let nab = b.cards[0].card
        #expect(b.noteUnmatchedDigits("1234") == nab)
        #expect(b.info(nab)?.last4 == ["1234"])
    }

    @Test func oneActiveCardAlreadyHoldingTheDigitsChangesNothing() {
        var nab = CardInfo(name: "NAB Debit", shortName: "NAB")
        nab.last4 = ["1234"]
        let b = book([nab])
        #expect(b.noteUnmatchedDigits("1234") == b.cards[0].card)
        #expect(b.info(b.cards[0].card)?.last4 == ["1234"])
    }

    @Test func twoOrMoreActiveCardsDoNotGuess() {
        let b = book([CardInfo(name: "NAB Debit", shortName: "NAB"), CardInfo(name: "SC Debit", shortName: "SC")])
        #expect(b.noteUnmatchedDigits("1234") == nil)
        #expect(b.cards.allSatisfy { $0.last4.isEmpty })
    }

    @Test func noActiveCardsDoNothing() {
        let b = book()
        #expect(b.noteUnmatchedDigits("1234") == nil)
    }

    @Test func assignSavesTheDigitsOnceOnThePickedCard() {
        let b = book([CardInfo(name: "NAB Debit", shortName: "NAB"), CardInfo(name: "SC Debit", shortName: "SC")])
        let nab = b.cards[0].card
        b.assign("1234", to: nab)
        b.assign("1234", to: nab)   // answering twice never duplicates
        #expect(b.info(nab)?.last4 == ["1234"])
    }

    @Test func assignOnAnUnknownCardDoesNothing() {
        let b = book()
        b.assign("1234", to: .nab)   // no such card in this book
        #expect(b.cards.isEmpty)
    }
}
