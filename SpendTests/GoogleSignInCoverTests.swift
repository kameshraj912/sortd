import Testing
import Foundation
@testable import Spend

/// Google's sign-in sheet makes the scene inactive. The privacy cover must
/// not show then: on the phone it landed on top of the sheet and ended the
/// sign-in as cancelled after about a second. `SystemPrompt.active` is set
/// for the whole sheet and released on every way out.
@MainActor
struct GoogleSignInCoverTests {
    /// Reads the flag while the (fake) sheet is up.
    private final class Seen { var activeDuringSheet: Bool? }

    @Test func coverIsHeldOffWhileTheGoogleSheetIsUpAndReleasedAfterIt() async throws {
        let prompt = SystemPrompt(linger: .zero)
        let seen = Seen()
        let auth = GoogleAuth(webSession: { url, scheme in
            seen.activeDuringSheet = prompt.active
            // Google's redirect: the state echoed back, plus a code.
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            return URL(string: "\(scheme):/oauth2redirect?code=abc&state=\(state)")!
        }, prompt: prompt)
        #expect(!prompt.active)

        let (code, verifier) = try await auth.authorize(scopes: GoogleAuth.scopes)

        #expect(code == "abc")
        #expect(!verifier.isEmpty)
        #expect(seen.activeDuringSheet == true)
        await settle(prompt)
        #expect(!prompt.active)
    }

    @Test func coverComesBackAfterACancelledSheet() async {
        let prompt = SystemPrompt(linger: .zero)
        let seen = Seen()
        let auth = GoogleAuth(webSession: { _, _ in
            seen.activeDuringSheet = prompt.active
            throw GoogleAuth.AuthError.cancelled
        }, prompt: prompt)

        await #expect(throws: GoogleAuth.AuthError.cancelled) {
            try await auth.authorize(scopes: GoogleAuth.scopes)
        }

        #expect(seen.activeDuringSheet == true)
        await settle(prompt)
        #expect(!prompt.active)
    }

    @Test func coverComesBackWhenTheRedirectIsBad() async {
        let prompt = SystemPrompt(linger: .zero)
        let auth = GoogleAuth(webSession: { _, scheme in
            URL(string: "\(scheme):/oauth2redirect?code=abc&state=wrong")!
        }, prompt: prompt)

        await #expect(throws: GoogleAuth.AuthError.noCode) {
            try await auth.authorize(scopes: GoogleAuth.scopes)
        }

        await settle(prompt)
        #expect(!prompt.active)
    }

    @Test func twoSheetsAtOnceKeepTheCoverOffUntilBothClose() async {
        let prompt = SystemPrompt(linger: .zero)
        prompt.begin()
        prompt.begin()
        prompt.end()
        await settle(prompt, expecting: true)
        #expect(prompt.active)
        prompt.end()
        await settle(prompt)
        #expect(!prompt.active)
    }

    /// `end()` drops the flag a moment later, on the main queue: wait for it.
    private func settle(_ prompt: SystemPrompt, expecting: Bool = false) async {
        for _ in 0..<200 where prompt.active != expecting {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
