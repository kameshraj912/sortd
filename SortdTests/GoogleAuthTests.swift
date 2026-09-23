import Testing
@testable import Sortd

/// Delete All asks Google to cancel every token Sortd still holds, including
/// ones whose revoke failed earlier (offline) and were saved to try again.
@MainActor
struct GoogleAuthTests {

    @Test func deleteAllAlsoRevokesTokensAnEarlierDisconnectCouldNotReach() {
        let tokens = GoogleAuth.tokensToRevoke(accounts: ["live-1"], pending: "old-1\nold-2")
        #expect(tokens == ["live-1", "old-1", "old-2"])
    }

    @Test func eachTokenIsRevokedOnce() {
        let tokens = GoogleAuth.tokensToRevoke(accounts: ["a", "b"], pending: "b\n\na\nc")
        #expect(tokens == ["a", "b", "c"])
    }

    @Test func nothingPendingIsFine() {
        #expect(GoogleAuth.tokensToRevoke(accounts: [], pending: nil).isEmpty)
        #expect(GoogleAuth.tokensToRevoke(accounts: ["a"], pending: "") == ["a"])
    }
}
