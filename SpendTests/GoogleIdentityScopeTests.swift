import Testing
@testable import Spend

/// The identity-only Google sign-in (sub-spec 4) must ask for exactly
/// `openid email`, never `gmail.readonly`. `GoogleAuth.scopes` is the
/// existing Gmail-connect scope list and stays `["openid", "email",
/// "https://www.googleapis.com/auth/gmail.readonly"]`; this pins a
/// separate `GoogleAuth.identityScopes` constant for the identity request,
/// which does not exist yet and must be added by swift-builder.
struct GoogleIdentityScopeTests {

    @Test func identityScopesAreExactlyOpenIDAndEmail() {
        #expect(GoogleAuth.identityScopes == ["openid", "email"])
    }

    @Test func identityScopesNeverAskForGmailReadonly() {
        #expect(!GoogleAuth.identityScopes.contains("https://www.googleapis.com/auth/gmail.readonly"))
    }

    @Test func gmailConnectScopesAreUnchangedByTheIdentityAddition() {
        #expect(GoogleAuth.scopes == ["openid", "email", "https://www.googleapis.com/auth/gmail.readonly"])
    }
}
