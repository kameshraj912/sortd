import Testing
import Foundation
@testable import Spend

/// Connecting Gmail: the account is listed the moment Google says yes, and
/// a first sync that fails keeps it listed with a plain retry (a sync, not
/// another Google sign-in). These test the model steps `connect` and
/// `syncAccounts` use; the real sign-in and inbox need a device.
@MainActor
struct GmailConnectTests {
    @Test func signInListsTheAccountBeforeTheFirstSyncRuns() {
        let list = GmailSync.registering("a@b.com", in: [])
        #expect(list.map(\.email) == ["a@b.com"])
        #expect(list[0].lastSync == nil)
        // Connecting the same inbox again does not list it twice.
        #expect(GmailSync.registering("a@b.com", in: list).count == 1)
    }

    @Test func aFailedFirstSyncKeepsTheAccountAndRetriesWithoutSigningInAgain() {
        var account = GmailSync.registering("a@b.com", in: [])[0]
        let error = URLError(.notConnectedToInternet)

        GmailSync.recordFailure(error, on: &account)
        let failure = SyncFailure.from(error)

        #expect(account.email == "a@b.com")
        #expect(account.lastSync == nil)
        #expect(account.lastResult != nil)
        #expect(!failure.needsSignIn)
        #expect(!GmailSync.retryBySigningIn(failure, accounts: [account]))
    }

    @Test func expiredAccessRetriesBySigningIn() {
        let account = GmailSync.registering("a@b.com", in: [])[0]
        let failure = SyncFailure.from(GoogleAuth.AuthError.noRefreshToken)
        #expect(failure.needsSignIn)
        #expect(GmailSync.retryBySigningIn(failure, accounts: [account]))
        // No account at all: the only way forward is a sign-in.
        let offline = SyncFailure.from(URLError(.notConnectedToInternet))
        #expect(GmailSync.retryBySigningIn(offline, accounts: []))
    }

    /// Closing Google's sheet used to send the Connect sheet back to idle
    /// with no word, as if nothing had been tapped.
    @Test func aCancelledSignInSaysSoAndOffersAnotherGo() {
        let failure = SyncFailure.from(GoogleAuth.AuthError.cancelled)
        #expect(failure.kind == .cancelled)
        #expect(failure.message == "Sign-in was cancelled. Try again.")
        #expect(failure.retryTitle == "Try Again")
        // Try Again means another sign-in, even with an inbox already listed.
        let listed = GmailSync.registering("a@b.com", in: [])
        #expect(GmailSync.retryBySigningIn(failure, accounts: listed))
    }

    @Test func aCancelledSignInDoesNotNagOnHome() {
        let s = SyncStatus()
        let job = s.begin(quiet: false)
        s.update(.failed(SyncFailure.from(GoogleAuth.AuthError.cancelled)), job: job)
        #expect(s.title == "Sign-in was cancelled. Try again.")
        #expect(!s.showsOnHome)
        // Other sign-in failures still do.
        s.update(.failed(SyncFailure.from(GoogleAuth.AuthError.missingGmailAccess)), job: job)
        #expect(s.showsOnHome)
    }

    @Test func aStoppedSyncIsNotAFailure() {
        var account = GmailSync.registering("a@b.com", in: [])[0]
        GmailSync.recordFailure(CancellationError(), on: &account)
        #expect(account.lastResult == nil)
    }
}
