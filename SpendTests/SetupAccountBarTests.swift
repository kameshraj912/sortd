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
