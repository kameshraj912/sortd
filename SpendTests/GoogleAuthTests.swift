import Testing
@testable import Spend

/// Delete All asks Google again for revokes that failed earlier (offline) and
/// were saved to try again.
@MainActor
struct GoogleAuthTests {

    @Test func deleteAllRetriesRevokesAnEarlierAttemptCouldNotReach() {
        #expect(GoogleAuth.pendingTokens("old-1\nold-2") == ["old-1", "old-2"])
    }

    @Test func eachTokenIsRevokedOnce() {
        #expect(GoogleAuth.pendingTokens("b\n\na\nb\nc") == ["b", "a", "c"])
    }

    @Test func nothingPendingIsFine() {
        #expect(GoogleAuth.pendingTokens(nil).isEmpty)
        #expect(GoogleAuth.pendingTokens("").isEmpty)
    }
}
