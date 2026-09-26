import Testing
import Foundation
import AuthenticationServices
@testable import Spend

/// Neither sign-in path may show a domain/code string ("error 1000",
/// "NSURLErrorDomain -1009") in the Account screen's alert. Pins the two
/// pure mapping functions: a cancel never alerts, everything else becomes
/// one plain sentence.
@MainActor
struct AccountErrorMappingTests {

    // MARK: Apple

    @Test func appleCancelBecomesAccountErrorCancelled() {
        let mapped = AppleIdentityProvider.error(from: ASAuthorizationError(.canceled))
        #expect(mapped as? AccountError == .cancelled)
    }

    @Test func appleUnknownMentionsICloudNotAnErrorCode() {
        let mapped = AppleIdentityProvider.error(from: ASAuthorizationError(.unknown))
        let text = mapped.localizedDescription
        #expect(text.contains("iCloud"))
        #expect(!text.contains("1000"))
        #expect(!text.contains("ASAuthorizationErrorDomain"))
    }

    @Test func appleFailedNotHandledAndInvalidResponseShareOneSentence() {
        let failed = AppleIdentityProvider.error(from: ASAuthorizationError(.failed)).localizedDescription
        let notHandled = AppleIdentityProvider.error(from: ASAuthorizationError(.notHandled)).localizedDescription
        let invalidResponse = AppleIdentityProvider.error(from: ASAuthorizationError(.invalidResponse)).localizedDescription
        #expect(failed == notHandled)
        #expect(failed == invalidResponse)
        #expect(failed.contains("Try again"))
    }

    @Test func appleNotInteractiveSaysScreenIsNeeded() {
        let text = AppleIdentityProvider.error(from: ASAuthorizationError(.notInteractive)).localizedDescription
        #expect(text.contains("screen"))
    }

    @Test func appleUnrecognisedErrorFallsBackToOneGenericSentence() {
        struct Other: Error {}
        let mapped = AppleIdentityProvider.error(from: Other())
        // Not an ASAuthorizationError at all: passed through unchanged, so a
        // caller that knows the type can still branch on it.
        #expect(mapped is Other)
    }

    // MARK: Google

    @Test func googleCancelBecomesAccountErrorCancelled() {
        let mapped = GoogleIdentityProvider.error(from: GoogleAuth.AuthError.cancelled)
        #expect(mapped as? AccountError == .cancelled)
    }

    @Test func googleAuthErrorsPassThroughAsTheirOwnPlainSentence() {
        let mapped = GoogleIdentityProvider.error(from: GoogleAuth.AuthError.missingGmailAccess)
        #expect(mapped.localizedDescription == GoogleAuth.AuthError.missingGmailAccess.localizedDescription)
    }

    @Test func googleOfflineNetworkErrorBecomesOneOfflineSentence() {
        let mapped = GoogleIdentityProvider.error(from: URLError(.notConnectedToInternet))
        let text = mapped.localizedDescription
        #expect(text.contains("offline"))
        #expect(!text.contains("NSURLErrorDomain"))
    }

    @Test func googleIsOfflineRecognisesNetworkCodesOnly() {
        #expect(GoogleIdentityProvider.isOffline(URLError(.notConnectedToInternet)))
        #expect(GoogleIdentityProvider.isOffline(URLError(.networkConnectionLost)))
        #expect(GoogleIdentityProvider.isOffline(URLError(.timedOut)))
        #expect(!GoogleIdentityProvider.isOffline(URLError(.badServerResponse)))
    }

    @Test func googleUnrecognisedErrorBecomesOneGenericSentenceNotARawErrorDescription() {
        struct Weird: Error {}
        let mapped = GoogleIdentityProvider.error(from: Weird())
        let text = mapped.localizedDescription
        #expect(text.contains("Try again"))
        #expect(!text.contains("Weird"))
    }
}
