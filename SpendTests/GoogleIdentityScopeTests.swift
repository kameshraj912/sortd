import Testing
@testable import Spend

/// "Continue with Google" asks for exactly `openid email`: who the person is
/// and nothing else. No Gmail scope, ever (Gmail was removed on 2 Oct 2026).
struct GoogleIdentityScopeTests {

    @Test func scopesAreExactlyOpenIDAndEmail() {
        #expect(GoogleAuth.scopes == ["openid", "email"])
    }

    @Test func scopesNeverAskForAnythingFromGmail() {
        #expect(!GoogleAuth.scopes.contains { $0.contains("googleapis.com") })
    }
}
