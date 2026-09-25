import Testing
import Foundation
@testable import Spend

// MARK: - Fakes (this file's own; the contract fakes live in AccountStoreTests)

private final class ProviderFake: IdentityProvider {
    let account: Account
    init(_ account: Account) { self.account = account }
    func signIn() async throws -> Account { account }
}

private final class KeychainFake: AccountKeychain {
    var stored: Account?
    func load() throws -> Account? { stored }
    func save(_ a: Account) throws { stored = a }
    func delete() throws { stored = nil }
}

/// One list shared by the sink and the revoker, so a test can pin the
/// order of calls across both.
private final class CallLog {
    var calls: [String] = []
}

private final class LoggingSink: IdentitySink {
    let log: CallLog
    init(_ log: CallLog) { self.log = log }
    var resetCount = 0
    func identify(_ hash: String) { log.calls.append("identify") }
    func reset() { resetCount += 1; log.calls.append("reset") }
    func signedIn(provider: AccountProvider) { log.calls.append("signedIn") }
    func signedOut() { log.calls.append("signedOut") }
}

/// Throws `error` from both calls when set; otherwise counts. `gate` makes
/// the next `deletePerson` wait until the test resumes it.
private final class RevokerFake: AccountRevoker {
    let log: CallLog?
    init(log: CallLog? = nil) { self.log = log }
    var error: AccountError?
    var revokeCount = 0
    var deletePersonCount = 0
    var hashes: [String] = []
    var blockNextPersonDelete = false
    var gate: CheckedContinuation<Void, Never>?

    func revoke(_ a: Account) async throws {
        if let error { throw error }
        revokeCount += 1
        log?.calls.append("revoke")
    }

    func deletePerson(hash: String) async throws {
        if let error { throw error }
        if blockNextPersonDelete {
            blockNextPersonDelete = false
            await withCheckedContinuation { gate = $0 }
        }
        deletePersonCount += 1
        hashes.append(hash)
        log?.calls.append("deletePerson")
    }
}

private final class CheckerFake: CredentialStateChecker {
    func isRevoked(_ a: Account) async -> Bool { false }
}

/// Review fixes on sub-spec 4: what the pending-delete queue may hold, the
/// order of sink calls, the queue across a Delete All wipe, and a retry
/// that overlaps a new delete.
@MainActor
struct AccountStoreReviewTests {
    static let salt = "review-salt"
    static let account = Account(provider: .apple, subject: "001234.abcdef", email: "raj@example.com")
    static var hash: String { AccountStore.hash(salt: salt, provider: .apple, subject: account.subject) }

    private func defaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: "review-\(name)")!
        d.removePersistentDomain(forName: "review-\(name)")
        return d
    }

    private func store(keychain: KeychainFake? = nil, revoker: RevokerFake,
                       sink: LoggingSink, defaults: UserDefaults) -> AccountStore {
        AccountStore(keychain: keychain ?? KeychainFake(), revoker: revoker, sink: sink, checker: CheckerFake(),
                     defaults: defaults, salt: Self.salt)
    }

    private func queued(_ defaults: UserDefaults) -> [String] {
        defaults.array(forKey: AccountStore.pendingDeletesKey) as? [String] ?? []
    }

    // MARK: (1) the queue never holds the email or the subject

    @Test func offlineDeleteQueuesHashesOnlyNeverTheEmailOrSubject() async throws {
        let defaults = defaults(#function)
        let revoker = RevokerFake()
        revoker.error = .offline
        let s = store(revoker: revoker, sink: LoggingSink(CallLog()), defaults: defaults)
        try await s.signIn(with: ProviderFake(Self.account))

        await s.deleteAccount()

        let raw = queued(defaults).joined(separator: "\n")
        #expect(queued(defaults).count == 2)
        #expect(!raw.contains("001234.abcdef"))
        #expect(!raw.contains("raj@"))
        #expect(!raw.contains("example.com"))
        #expect(raw.contains(Self.hash))
    }

    // MARK: (3) sink order

    @Test func signOutSendsSignedOutThenResets() async throws {
        let log = CallLog()
        let s = store(revoker: RevokerFake(log: log), sink: LoggingSink(log), defaults: defaults(#function))
        try await s.signIn(with: ProviderFake(Self.account))
        #expect(log.calls == ["identify", "signedIn"])

        s.signOut()

        #expect(log.calls == ["identify", "signedIn", "signedOut", "reset"])
    }

    @Test func deleteResetsFirstThenRevokesAndDeletesThePersonWithNoSignedOutEvent() async throws {
        let log = CallLog()
        let s = store(revoker: RevokerFake(log: log), sink: LoggingSink(log), defaults: defaults(#function))
        try await s.signIn(with: ProviderFake(Self.account))
        log.calls = []

        await s.deleteAccount()

        #expect(log.calls == ["reset", "revoke", "deletePerson"])
    }

    // MARK: (2) the queue survives the Delete All wipe

    @Test func pendingDeletesSurviveADefaultsWipeWhenWrapped() async throws {
        let name = "review-\(#function)"
        let defaults = defaults(#function)
        let revoker = RevokerFake()
        revoker.error = .offline
        let s = store(revoker: revoker, sink: LoggingSink(CallLog()), defaults: defaults)
        try await s.signIn(with: ProviderFake(Self.account))
        await s.deleteAccount()
        let before = queued(defaults)
        #expect(before.count == 2)

        s.preservePendingDeletes { defaults.removePersistentDomain(forName: name) }

        #expect(queued(defaults) == before)
    }

    // MARK: (7) Delete All queues the person delete when signed in

    @Test func signOutForDeleteAllQueuesThePersonDeleteAndForgetsLocally() async throws {
        let defaults = defaults(#function)
        let keychain = KeychainFake()
        let revoker = RevokerFake()
        let sink = LoggingSink(CallLog())
        let s = store(keychain: keychain, revoker: revoker, sink: sink, defaults: defaults)
        try await s.signIn(with: ProviderFake(Self.account))

        s.signOutForDeleteAll()

        #expect(s.current == nil)
        #expect(keychain.stored == nil)
        #expect(sink.resetCount == 1)
        #expect(revoker.revokeCount == 0)
        #expect(queued(defaults).count == 1)
        #expect(queued(defaults).joined().contains(Self.hash))

        await s.retryPendingDeletes()

        #expect(revoker.revokeCount == 0)
        #expect(revoker.deletePersonCount == 1)
        #expect(revoker.hashes == [Self.hash])
        #expect(queued(defaults).isEmpty)
    }

    @Test func signOutForDeleteAllDoesNothingWhenSignedOut() {
        let defaults = defaults(#function)
        let sink = LoggingSink(CallLog())
        let s = store(revoker: RevokerFake(), sink: sink, defaults: defaults)

        s.signOutForDeleteAll()

        #expect(queued(defaults).isEmpty)
        #expect(sink.resetCount == 0)
    }

    // MARK: (6) only "offline" is retried

    @Test func aRejectedJobIsDroppedWithItsMessageNotQueued() async throws {
        let defaults = defaults(#function)
        let revoker = RevokerFake()
        revoker.error = .rejected("Apple said no.")
        let s = store(revoker: revoker, sink: LoggingSink(CallLog()), defaults: defaults)
        try await s.signIn(with: ProviderFake(Self.account))

        let problems = await s.deleteAccount()

        #expect(s.current == nil)
        #expect(queued(defaults).isEmpty)
        #expect(problems == ["Apple said no.", "Apple said no."])
    }

    @Test func aCancelledJobIsDroppedQuietly() async throws {
        let defaults = defaults(#function)
        let revoker = RevokerFake()
        revoker.error = .cancelled
        let s = store(revoker: revoker, sink: LoggingSink(CallLog()), defaults: defaults)
        try await s.signIn(with: ProviderFake(Self.account))

        let problems = await s.deleteAccount()

        #expect(s.current == nil)
        #expect(queued(defaults).isEmpty)
        #expect(problems.isEmpty)
    }

    // MARK: (8) a retry in flight does not overwrite a new delete's jobs

    @Test func aDeleteDuringARetryKeepsItsJobsAndTheRetriedOnesGo() async throws {
        let defaults = defaults(#function)
        // A: deleted offline earlier, both jobs queued.
        let offline = RevokerFake()
        offline.error = .offline
        let a = store(revoker: offline, sink: LoggingSink(CallLog()), defaults: defaults)
        try await a.signIn(with: ProviderFake(Self.account))
        await a.deleteAccount()
        #expect(queued(defaults).count == 2)

        // Next launch: the retry runs and stalls inside deletePerson.
        let gated = RevokerFake()
        gated.blockNextPersonDelete = true
        let launch = store(revoker: gated, sink: LoggingSink(CallLog()), defaults: defaults)
        let retry = Task { await launch.retryPendingDeletes() }
        while gated.gate == nil { await Task.yield() }

        // Meanwhile B signs in and deletes, offline.
        let b = store(revoker: offline, sink: LoggingSink(CallLog()), defaults: defaults)
        let accountB = Account(provider: .google, subject: "b-subject", email: nil)
        try await b.signIn(with: ProviderFake(accountB))
        await b.deleteAccount()
        #expect(queued(defaults).count == 4)

        gated.gate?.resume()
        await retry.value

        let hashB = AccountStore.hash(salt: Self.salt, provider: .google, subject: "b-subject")
        #expect(gated.revokeCount == 1)
        #expect(gated.deletePersonCount == 1)
        #expect(queued(defaults).count == 2)
        #expect(queued(defaults).allSatisfy { $0.contains(hashB) })
        #expect(!queued(defaults).joined().contains(Self.hash))
    }
}
