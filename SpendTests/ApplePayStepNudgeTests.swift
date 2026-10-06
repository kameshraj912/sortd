import Testing
import Foundation
@testable import Spend

/// `ApplePayStepNudge`: the reminder to finish Apple Pay logging (6 Oct 2026).
struct ApplePayStepNudgeTests {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)
    typealias Stage = ApplePayStepNudge.Stage
    typealias Plan = ApplePayStepNudge.Plan

    @Test func theStageFollowsWhatIsLeft() {
        #expect(Stage(status: .notConnected, saysBuilt: false) == .notSetUp)
        #expect(Stage(status: .notConnected, saysBuilt: true) == .notSetUp)
        #expect(Stage(status: .shortcutReached(when), saysBuilt: false) == .stepThreeLeft)
        #expect(Stage(status: .shortcutReached(when), saysBuilt: true) == nil)
        #expect(Stage(status: .tapNeedsCheck(date: when), saysBuilt: false) == nil)
        let tap = ApplePayStatus.tapLogged(date: when, merchant: "Seven Seeds", amount: 4.5, currency: "AUD")
        #expect(Stage(status: tap, saysBuilt: false) == nil)
    }

    /// No reminder before setup is finished, none without permission, and
    /// none once logging works.
    @Test func noReminderUnlessSetUpAllowedAndLeftUndone() {
        #expect(ApplePayStepNudge.plan(stage: .notSetUp, pendingStage: nil, setupDone: false, authorized: true) == .clear)
        #expect(ApplePayStepNudge.plan(stage: .notSetUp, pendingStage: nil, setupDone: true, authorized: false) == .clear)
        #expect(ApplePayStepNudge.plan(stage: nil, pendingStage: .notSetUp, setupDone: true, authorized: true) == .clear)
        #expect(ApplePayStepNudge.plan(stage: .notSetUp, pendingStage: nil, setupDone: true, authorized: true) == .schedule(.notSetUp))
    }

    /// Leaving the app again does not push the reminder further out; a new
    /// stage (steps 1 and 2 done) rewrites it with the new words.
    @Test func leavingAgainKeepsTheReminderUnlessTheStageMoved() {
        #expect(ApplePayStepNudge.plan(stage: .notSetUp, pendingStage: .notSetUp, setupDone: true, authorized: true) == .leave)
        #expect(ApplePayStepNudge.plan(stage: .stepThreeLeft, pendingStage: .notSetUp, setupDone: true, authorized: true) == .schedule(.stepThreeLeft))
    }

    @Test func theReminderOpensTheSetupPage() {
        let target = Router.target(for: URL(string: ApplePayStepNudge.url)!)
        #expect(target?.name == "applepay")
        #expect(ApplePayStepNudge.ids.count == ApplePayStepNudge.delays.count)
        #expect(ApplePayStepNudge.delays == [24 * 3600, 3 * 24 * 3600])
        for stage in [Stage.notSetUp, .stepThreeLeft] {
            #expect(!stage.title.isEmpty && !stage.body.isEmpty)
            #expect(!stage.body.contains("Apple Pay") || stage == .notSetUp)
        }
    }
}
