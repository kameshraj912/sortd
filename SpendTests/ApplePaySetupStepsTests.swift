import Testing
import Foundation
@testable import Spend

/// `ApplePaySetupSteps.ticked` for every `ApplePayStatus` (`applepay-guide`
/// rewrite, 27 Sep 2026). Pure, so no `ModelContext` is needed — a
/// `Transaction` for `.tapLogged`/`.tapNeedsCheck` can be described without
/// ever being inserted anywhere.
struct ApplePaySetupStepsTests {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func notConnectedTicksNoStep() {
        let t = ApplePaySetupSteps.ticked(for: .notConnected)
        #expect(!t.addShortcut)
        #expect(!t.runAndAllow)
        #expect(!t.turnOnAutomation)
    }

    @Test func shortcutReachedTicksTheFirstTwoStepsOnly() {
        let t = ApplePaySetupSteps.ticked(for: .shortcutReached(when))
        #expect(t.addShortcut)
        #expect(t.runAndAllow)
        #expect(!t.turnOnAutomation)
    }

    @Test func aLoggedTapTicksAllThreeSteps() {
        let status = ApplePayStatus.tapLogged(date: when, merchant: "Seven Seeds",
                                              amount: Decimal(string: "4.50")!, currency: "AUD")
        let t = ApplePaySetupSteps.ticked(for: status)
        #expect(t.addShortcut)
        #expect(t.runAndAllow)
        #expect(t.turnOnAutomation)
    }

    /// A tap that needs a check still proves the automation was on — it's
    /// the shop or amount that was blank, not the connection.
    @Test func aTapThatNeedsACheckStillTicksAllThreeSteps() {
        let t = ApplePaySetupSteps.ticked(for: .tapNeedsCheck(date: when))
        #expect(t.addShortcut)
        #expect(t.runAndAllow)
        #expect(t.turnOnAutomation)
    }
}
