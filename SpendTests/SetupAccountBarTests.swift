import Testing
import Foundation
@testable import Spend

/// Setup's sign-in step must never leave a signed-in person without a button.
/// On TestFlight 1.0 (2) the bar was empty once signed in: after Sign in with
/// Apple the step did not move on, and Back to the step had no way forward.
struct SetupAccountBarTests {
    @Test func signedOutShowsTheSignInButtons() {
        #expect(SetupFlow.accountBar(signedIn: false) == .signIn)
    }

    @Test func signedInAlwaysHasContinue() {
        #expect(SetupFlow.accountBar(signedIn: true) == .continueOn)
    }

    /// The bar in `OnboardingView` is drawn from `SetupFlow.accountBar`, and
    /// the Continue case moves forward. Source scan, like `BudgetChipFormatTests`.
    @Test func onboardingDrawsTheBarFromTheRule() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Spend/Views/OnboardingView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(source.contains("switch SetupFlow.accountBar(signedIn: accountSignedInAs != nil)"))
        #expect(source.contains("case .continueOn:\n                        primaryButton(\"Continue\") { go(1) }"))
    }
}

/// Skip for Now on the cards and Apple Pay steps (11 Oct 2026). Those steps
/// are never "untouched", so the skip went out as `setup_step_completed`
/// with `skipped: false`, and the Apple Pay funnel's `locked_continue` also
/// came from the cards step. Source scan, like `onboardingDrawsTheBarFromTheRule`.
struct SetupSkipForNowTests {
    private func onboardingSource() throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Spend/Views/OnboardingView.swift")
        return try String(contentsOf: file, encoding: .utf8)
    }

    @Test func skipForNowIsCountedAsASkippedStep() throws {
        let source = try onboardingSource()
        #expect(source.contains("usedSkip = true\n            go(1, skipped: true)"))
        #expect(source.contains("stepDone(step, skipped: skipped || (newFlow && untouched(step)))"))
    }

    @Test func lockedContinueIsAnApplePayActionOnlyOnTheApplePayStep() throws {
        let source = try onboardingSource()
        #expect(source.contains("if step == .applePay {\n                    ApplePaySetupSteps.trackAction(\"locked_continue\""))
    }
}
