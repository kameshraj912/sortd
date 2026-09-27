import Testing
import Foundation
@testable import Spend

/// The unmatched-card-digits queue (`PendingCardDigits`) and the "Which
/// card?" prompt rule (`CardDigitsPrompt`), pure apart from `UserDefaults`
/// (spec 2026-09-27).
struct PendingCardDigitsTests {
    private func suite() -> UserDefaults { UserDefaults(suiteName: "pending-card-digits-\(UUID().uuidString)")! }

    @Test func addsAndDedupes() {
        var queue: [String] = []
        queue = PendingCardDigits.adding("1234", to: queue)
        queue = PendingCardDigits.adding("1234", to: queue)
        #expect(queue == ["1234"])
    }

    @Test func capsAtFiveDroppingTheOldest() {
        var queue: [String] = []
        for d in ["1111", "2222", "3333", "4444", "5555", "6666"] {
            queue = PendingCardDigits.adding(d, to: queue)
        }
        #expect(queue == ["2222", "3333", "4444", "5555", "6666"])
        #expect(queue.count == PendingCardDigits.cap)
    }

    @Test func removingDropsOnlyThatOne() {
        let queue = ["1111", "2222", "3333"]
        #expect(PendingCardDigits.removing("2222", from: queue) == ["1111", "3333"])
        #expect(PendingCardDigits.removing("9999", from: queue) == queue)
    }

    @Test func noteThenClearRoundTripThroughDefaults() {
        let d = suite()
        #expect(PendingCardDigits.load(from: d).isEmpty)
        PendingCardDigits.note("1234", defaults: d)
        PendingCardDigits.note("5678", defaults: d)
        #expect(PendingCardDigits.load(from: d) == ["1234", "5678"])
        PendingCardDigits.clear("1234", defaults: d)
        #expect(PendingCardDigits.load(from: d) == ["5678"])
    }

    @Test func notingTheSameDigitsTwiceThroughDefaultsStillDedupes() {
        let d = suite()
        PendingCardDigits.note("1234", defaults: d)
        PendingCardDigits.note("1234", defaults: d)
        #expect(PendingCardDigits.load(from: d) == ["1234"])
    }
}

struct CardDigitsPromptTests {
    @Test func showsWithTwoOrMoreActiveCardsAndSomethingQueued() {
        #expect(CardDigitsPrompt.shouldShow(queue: ["1234"], activeCardCount: 2, duringSetup: false, duringIntro: false))
        #expect(CardDigitsPrompt.shouldShow(queue: ["1234"], activeCardCount: 3, duringSetup: false, duringIntro: false))
    }

    @Test func hidesWithNothingQueued() {
        #expect(!CardDigitsPrompt.shouldShow(queue: [], activeCardCount: 2, duringSetup: false, duringIntro: false))
    }

    @Test func hidesWithFewerThanTwoActiveCards() {
        #expect(!CardDigitsPrompt.shouldShow(queue: ["1234"], activeCardCount: 1, duringSetup: false, duringIntro: false))
        #expect(!CardDigitsPrompt.shouldShow(queue: ["1234"], activeCardCount: 0, duringSetup: false, duringIntro: false))
    }

    @Test func hidesDuringSetupOrTheIntro() {
        #expect(!CardDigitsPrompt.shouldShow(queue: ["1234"], activeCardCount: 2, duringSetup: true, duringIntro: false))
        #expect(!CardDigitsPrompt.shouldShow(queue: ["1234"], activeCardCount: 2, duringSetup: false, duringIntro: true))
    }
}
