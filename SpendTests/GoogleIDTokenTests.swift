import Testing
import Foundation
@testable import Spend

/// The identity-only Google sign-in reads the ID token without a signature
/// check (it came straight from Google's token endpoint over TLS), so the
/// claims that can be checked are: `aud` is our client, `iss` is Google,
/// and `exp` is in the future.
struct GoogleIDTokenTests {
    static let clientID = "36410288175-test.apps.googleusercontent.com"
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func token(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        return "eyJhbGciOiJSUzI1NiJ9." + payload.base64URL + ".signature"
    }

    private func valid(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var claims: [String: Any] = [
            "iss": "https://accounts.google.com",
            "aud": Self.clientID,
            "sub": "10769150350006150715113082367",
            "email": "raj@example.com",
            "exp": Self.now.timeIntervalSince1970 + 3600,
        ]
        for (k, v) in overrides { claims[k] = v }
        return claims
    }

    @Test func aGoodTokenGivesTheSubjectAndEmail() throws {
        let account = try GoogleAuth.identity(fromIDToken: token(valid()), clientID: Self.clientID, now: Self.now)
        #expect(account == Account(provider: .google, subject: "10769150350006150715113082367", email: "raj@example.com"))
    }

    @Test func theBareIssuerIsAcceptedToo() throws {
        let account = try GoogleAuth.identity(fromIDToken: token(valid(["iss": "accounts.google.com"])),
                                              clientID: Self.clientID, now: Self.now)
        #expect(account.provider == .google)
    }

    @Test func anAudienceListThatNamesUsIsAccepted() throws {
        let account = try GoogleAuth.identity(fromIDToken: token(valid(["aud": ["other", Self.clientID]])),
                                              clientID: Self.clientID, now: Self.now)
        #expect(account.subject == "10769150350006150715113082367")
    }

    @Test func aTokenForAnotherClientIsRefused() {
        #expect(throws: GoogleAuth.AuthError.providerFailed) {
            try GoogleAuth.identity(fromIDToken: token(valid(["aud": "someone-else"])), clientID: Self.clientID, now: Self.now)
        }
    }

    @Test func aTokenFromAnotherIssuerIsRefused() {
        #expect(throws: GoogleAuth.AuthError.providerFailed) {
            try GoogleAuth.identity(fromIDToken: token(valid(["iss": "https://evil.example"])), clientID: Self.clientID, now: Self.now)
        }
    }

    @Test func anExpiredTokenIsRefused() {
        #expect(throws: GoogleAuth.AuthError.providerFailed) {
            try GoogleAuth.identity(fromIDToken: token(valid(["exp": Self.now.timeIntervalSince1970 - 1])),
                                    clientID: Self.clientID, now: Self.now)
        }
    }

    @Test func aTokenWithoutExpiryOrSubjectIsRefused() {
        var noExp = valid()
        noExp.removeValue(forKey: "exp")
        #expect(throws: GoogleAuth.AuthError.providerFailed) {
            try GoogleAuth.identity(fromIDToken: token(noExp), clientID: Self.clientID, now: Self.now)
        }
        #expect(throws: GoogleAuth.AuthError.providerFailed) {
            try GoogleAuth.identity(fromIDToken: token(valid(["sub": ""])), clientID: Self.clientID, now: Self.now)
        }
    }

    @Test func junkIsRefused() {
        #expect(throws: GoogleAuth.AuthError.providerFailed) {
            try GoogleAuth.identity(fromIDToken: "not.a.jwt", clientID: Self.clientID, now: Self.now)
        }
    }

    @Test func theEmailIsOptional() throws {
        var noEmail = valid()
        noEmail.removeValue(forKey: "email")
        let account = try GoogleAuth.identity(fromIDToken: token(noEmail), clientID: Self.clientID, now: Self.now)
        #expect(account.email == nil)
    }
}
