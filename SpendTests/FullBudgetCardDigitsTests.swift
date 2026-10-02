import Testing
import Foundation
@testable import Spend

/// "Which card?" (`PendingCardDigits` / `CardDigitsPrompt`). Unmatched digits
/// are only ever queued while two or more cards are active
/// (`EmailSync`: `book.active.count >= 2`), and the prompt only ever shows
/// while two or more cards are still active (`CardDigitsPrompt.shouldShow`).
/// Nothing revisits the queue when a card is removed and the count drops to
/// one: the digits that were waiting for an answer are stuck forever — never
/// shown (shouldShow is now false), and never auto-assigned to the one
/// remaining card the way a fresh unmatched receipt would be
/// (`CardBook.noteUnmatchedDigits`, which only runs for new digits, not
/// ones already sitting in the queue).
@Suite struct FullBudgetCardDigitsTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "FullBudgetCardDigitsTests.\(UUID().uuidString)")!
    }

    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("unmatched card digits are stuck forever once removing a card drops the count to one"))
    func queuedDigitsAreResolvedAfterDroppingToOneCard() {
        let d = defaults()
        // Two cards were active when a receipt's last 4 matched neither.
        PendingCardDigits.note("4821", defaults: d)
        var queue = PendingCardDigits.load(from: d)
        #expect(CardDigitsPrompt.shouldShow(queue: queue, activeCardCount: 2,
                                            duringSetup: false, duringIntro: false))

        // Raj removes a card, leaving exactly one active card — the same
        // situation `noteUnmatchedDigits` would resolve immediately for a
        // brand new receipt.
        queue = PendingCardDigits.load(from: d)
        let stillPending = !queue.isEmpty
        let promptWillEverShowAgain = CardDigitsPrompt.shouldShow(queue: queue, activeCardCount: 1,
                                                                  duringSetup: false, duringIntro: false)

        // Expected: with one card left, the digits are either resolved to
        // it or at least still surfaced somehow — not silently abandoned.
        #expect(!(stillPending && !promptWillEverShowAgain),
                "digits are queued (\(queue)) but the prompt can never show again with one card active")
    }

    /// Regression: with two active cards throughout, the prompt behaves.
    @Test func promptShowsWithTwoActiveCardsOutsideSetupAndIntro() {
        let d = defaults()
        PendingCardDigits.note("1111", defaults: d)
        let queue = PendingCardDigits.load(from: d)
        #expect(CardDigitsPrompt.shouldShow(queue: queue, activeCardCount: 2,
                                            duringSetup: false, duringIntro: false))
        #expect(!CardDigitsPrompt.shouldShow(queue: queue, activeCardCount: 2,
                                             duringSetup: true, duringIntro: false))
        #expect(!CardDigitsPrompt.shouldShow(queue: queue, activeCardCount: 2,
                                             duringSetup: false, duringIntro: true))
    }

    /// The queue caps at 5, oldest out first, so the newest unknown card
    /// always gets a turn.
    @Test func theQueueCapsAtFiveDroppingTheOldest() {
        var queue: [String] = []
        for digits in ["1111", "2222", "3333", "4444", "5555", "6666"] {
            queue = PendingCardDigits.adding(digits, to: queue)
        }
        #expect(queue.count == 5)
        #expect(!queue.contains("1111"))
        #expect(queue.contains("6666"))
    }
}
