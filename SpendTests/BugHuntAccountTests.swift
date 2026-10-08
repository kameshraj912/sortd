import Testing
import Foundation
import SwiftData
import CryptoKit
import DeviceCheck
import AuthenticationServices
@testable import Spend

// Bug hunt 3 Oct 2026, area account-sync-safety. Each test was written to fail
// on the code of that day. All are fixed (docs/BugHunt-2026-10-03-fixes-c.md)
// and run in the normal suite.
// Reuses `FakeCloudBackupStore` and `FakeBackupKeyStore` from CloudBackupTests.

// MARK: - Fakes (this file's own)

private final class HuntAccountKeychain: AccountKeychain {
    var stored: Account?
    func load() throws -> Account? { stored }
    func save(_ a: Account) throws { stored = a }
    func delete() throws { stored = nil }
}

private final class HuntSink: IdentitySink {
    func identify(_ hash: String) {}
    func reset() {}
}

private final class HuntChecker: CredentialStateChecker {
    func isRevoked(_ a: Account) async -> Bool { false }
}

/// Answers each Worker request from a script of (status, body).
private final class HuntTransport {
    var script: [(Int, String)]
    var requests: [URLRequest] = []
    init(_ script: [(Int, String)]) { self.script = script }
    func call(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = script.isEmpty ? (500, "") : script.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class HuntAttester: AppAttester {
    var error: Error?
    nonisolated init() {}
    var isSupported: Bool { true }
    func attest(clientDataHash: Data) async throws -> (keyID: String, attestation: Data) {
        if let error { throw error }
        return ("key-1", Data("att".utf8))
    }
}

/// A CloudKit stand-in whose save can be held mid-upload.
private final class HeldCloudStore: CloudBackupStore {
    var saved: (blob: Data, modified: Date)?
    var holdNextSave = false
    var parked: CheckedContinuation<Void, Never>?

    func save(_ blob: Data, modified: Date) async throws {
        if holdNextSave {
            holdNextSave = false
            await withCheckedContinuation { parked = $0 }
        }
        saved = (blob, modified)
    }
    func fetch() async throws -> (blob: Data, modified: Date)? { saved }
    func delete() async throws { saved = nil }
    func release() { parked?.resume(); parked = nil }
}

/// A wait that ends only when the test opens it.
private final class HuntGate {
    private var parked: CheckedContinuation<Void, Never>?
    private var open = false
    func wait() async {
        if open { return }
        await withCheckedContinuation { parked = $0 }
    }
    func release() {
        open = true
        parked?.resume()
        parked = nil
    }
}

@MainActor
struct BugHuntAccountTests {
    static let workerURL = URL(string: "https://account.example")!
    static let google = Account(provider: .google, subject: "10769150350006150715113082367", email: "raj@example.org")
    static let apple = Account(provider: .apple, subject: "001234.abcdef", email: nil)

    private func context() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func scratch() -> (UserDefaults, String) {
        let name = "bughunt-account-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return (d, name)
    }

    private func log(_ ctx: ModelContext, _ merchant: String, _ amount: Decimal, minutes: Double) throws {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60),
                                 merchant: merchant, amount: amount, currency: "AUD",
                                 card: .other, source: .manual)
        _ = try TransactionLogger.log(p, in: ctx)
    }

    private let clock: () -> Date = { Date(timeIntervalSince1970: 1_790_500_000) }

    private func revoker(_ transport: HuntTransport, attester: HuntAttester? = nil,
                         appleCode: @escaping @MainActor (Account) async throws -> WorkerRevoker.AppleCode = { _ in
                             throw AccountError.cancelled
                         }) -> WorkerRevoker {
        WorkerRevoker(url: Self.workerURL, deps: WorkerRevoker.Dependencies(
            transport: { try await transport.call($0) },
            attester: attester ?? HuntAttester(),
            appleCode: appleCode,
            googleRevoke: {},
            clientID: "com.kameshraj.sortd"))
    }

    private func accountStore(_ revoker: AccountRevoker, defaults: UserDefaults) -> AccountStore {
        AccountStore(keychain: HuntAccountKeychain(), revoker: revoker, sink: HuntSink(), checker: HuntChecker(),
                     defaults: defaults, salt: "bughunt-salt")
    }

    // MARK: iCloud backup

    /// After Delete All Data on a phone that only restored, the in-memory
    /// `lastBackup` survives the defaults wipe, so the restore-first guard is
    /// skipped and the next backup writes over the other phone's iCloud copy.
    @Test func deleteAllOnARestoredPhoneStillRefusesToOverwriteTheOtherPhonesBackup() async throws {
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()   // one iCloud Keychain, shared by both phones

        // Phone A: three purchases, backed up.
        let ctxA = try context()
        try log(ctxA, "Woolworths", 58.30, minutes: 0)
        try log(ctxA, "Coles", 12.00, minutes: 10)
        try log(ctxA, "Aldi", 7.45, minutes: 20)
        let phoneA = CloudBackup(store: cloudStore, keys: keys, defaults: scratch().0, clock: clock)
        phoneA.isEnabled = true
        try await phoneA.backUpNow(from: ctxA)

        // Phone B: restores during setup, switch off.
        let ctxB = try context()
        let (defaultsB, nameB) = scratch()
        let phoneB = CloudBackup(store: cloudStore, keys: keys, defaults: defaultsB, clock: clock)
        #expect(try await phoneB.restore(into: ctxB, mode: .merge) == 3)

        // Phone B: Delete All Data, as `DataReset.deleteEverything` does it.
        // Only restored here, so the iCloud copy is (rightly) left alone.
        #expect(!phoneB.deletesCloudCopyOnReset)
        phoneB.isEnabled = false
        try ctxB.delete(model: Transaction.self)
        try ctxB.delete(model: MerchantRule.self)
        try ctxB.save()
        defaultsB.removePersistentDomain(forName: nameB)

        // Same session: setup again, backup on, one new purchase, Back Up Now.
        phoneB.isEnabled = true
        try log(ctxB, "7-Eleven", 4.20, minutes: 90)
        await #expect(throws: CloudBackupError.restoreFirst) {
            try await phoneB.backUpNow(from: ctxB)
        }

        // Phone A's three purchases must still be what iCloud holds.
        let key = try #require(try keys.load())
        let plain = try CloudBackup.decrypt(try #require(cloudStore.saved).blob, with: key)
        #expect(Backup.contents(of: plain)?.purchases == 3)
    }

    /// D3: an iPhone whose last backup is older than the iCloud copy (another
    /// iPhone wrote it since) must not write over it. It restores first, then
    /// its backup holds both phones' purchases.
    @Test func anOlderPhoneDoesNotWriteOverANewerICloudCopy() async throws {
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let t0 = clock()

        // Old phone: one purchase, backed up at t0.
        let ctxA = try context()
        try log(ctxA, "Woolworths", 58.30, minutes: 0)
        let phoneA = CloudBackup(store: cloudStore, keys: keys, defaults: scratch().0, clock: { t0 })
        phoneA.isEnabled = true
        try await phoneA.backUpNow(from: ctxA)

        // New phone, same iCloud: restores, adds Coles, backs up a day later.
        let ctxB = try context()
        let phoneB = CloudBackup(store: cloudStore, keys: keys, defaults: scratch().0,
                                 clock: { t0.addingTimeInterval(86_400) })
        #expect(try await phoneB.restore(into: ctxB, mode: .merge) == 1)
        try log(ctxB, "Coles", 20.00, minutes: 30)
        phoneB.isEnabled = true
        try await phoneB.backUpNow(from: ctxB)

        // The old phone saves something and tries to back up.
        try log(ctxA, "Aldi", 7.45, minutes: 10)
        await #expect(throws: CloudBackupError.newerInCloud) {
            try await phoneA.backUpNow(from: ctxA)
        }
        let key = try #require(try keys.load())
        let kept = try CloudBackup.decrypt(try #require(cloudStore.saved).blob, with: key)
        #expect(Backup.contents(of: kept)?.purchases == 2, "the newer copy was written over")

        // After restoring what the other phone added, it may back up again.
        #expect(try await phoneA.restore(into: ctxA, mode: .merge) == 1)
        try await phoneA.backUpNow(from: ctxA)
        let merged = try CloudBackup.decrypt(try #require(cloudStore.saved).blob, with: key)
        #expect(Backup.contents(of: merged)?.purchases == 3)
    }

    /// Turning backup off and choosing "Delete iCloud Copy" while an upload is
    /// still running: the delete finishes first, then the upload lands and the
    /// copy is back in iCloud.
    @Test func deleteICloudCopyDuringAnUploadLeavesNoCopy() async throws {
        let cloudStore = HeldCloudStore()
        let keys = FakeBackupKeyStore()
        let ctx = try context()
        try log(ctx, "Woolworths", 58.30, minutes: 0)
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch().0, clock: clock)
        cloud.isEnabled = true
        try await cloud.backUpNow(from: ctx)

        // A second backup starts and is mid-upload.
        try log(ctx, "Coles", 12.00, minutes: 30)
        cloudStore.holdNextSave = true
        let upload = Task { try? await cloud.backUpNow(from: ctx) }
        while cloudStore.parked == nil { await Task.yield() }

        // Switch off, then "Delete iCloud Copy" in the alert.
        cloud.isEnabled = false
        try await cloud.deleteCloudCopy()
        #expect(cloudStore.saved == nil)

        cloudStore.release()
        await upload.value

        #expect(cloudStore.saved == nil)
        #expect(cloud.lastBackup == nil)
    }

    /// A rate-limited backup retries after iCloud's wait even when backup was
    /// switched off during that wait ("Keep It"), so one more upload happens
    /// after "Backups have stopped".
    @Test func aRateLimitRetryDoesNotUploadOnceBackupIsSwitchedOff() async throws {
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let ctx = try context()
        try log(ctx, "Woolworths", 58.30, minutes: 0)
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch().0, clock: clock)
        let gate = HuntGate()
        cloud.sleep = { _ in await gate.wait() }
        cloud.isEnabled = true

        cloudStore.saveError = CloudBackupError.rateLimited(retryAfter: 30)
        await #expect(throws: CloudBackupError.rateLimited(retryAfter: 30)) {
            try await cloud.backUpNow(from: ctx)
        }
        cloudStore.saveError = nil

        // The user turns backup off and keeps the copy.
        cloud.isEnabled = false

        let retry = try #require(cloud.retry)
        gate.release()
        await retry.value

        #expect(cloudStore.saved == nil)
    }

    // MARK: Delete Account

    /// App Attest failing with `serverUnavailable` (Apple says: try again
    /// later) is not treated as offline, so the PostHog delete is dropped for
    /// good instead of queued, and the user sees a raw DeviceCheck error.
    @Test func anAppAttestServerOutageQueuesThePersonDelete() async throws {
        let transport = HuntTransport([(200, #"{"challenge":"chal-1"}"#)])
        let attester = HuntAttester()
        attester.error = DCError(.serverUnavailable)
        let (defaults, _) = scratch()
        let store = accountStore(revoker(transport, attester: attester), defaults: defaults)
        try await store.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))

        let problems = await store.deleteAccount().problems

        #expect((defaults.array(forKey: AccountStore.pendingDeletesKey) as? [String] ?? []).count == 1)
        #expect(problems.isEmpty)
    }

    /// Any other App Attest refusal is plain words too, not DeviceCheck's own text.
    @Test func anAppAttestRefusalIsShownInPlainWords() async throws {
        let transport = HuntTransport([(200, #"{"challenge":"chal-1"}"#)])
        let attester = HuntAttester()
        attester.error = DCError(.invalidKey)
        let (defaults, _) = scratch()
        let store = accountStore(revoker(transport, attester: attester), defaults: defaults)
        try await store.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))

        let result = await store.deleteAccount()

        #expect(result.problems == [WorkerRevoker.usageRecordNotDeleted])
        #expect((defaults.array(forKey: AccountStore.pendingDeletesKey) as? [String] ?? []).isEmpty)
    }

    /// A Worker refusal reaches the user as the Worker's machine code: the
    /// alert reads "posthog_auth".
    @Test func aWorkerRefusalIsShownInPlainWordsNotAsACode() async throws {
        let transport = HuntTransport([(200, #"{"challenge":"chal-1"}"#), (502, #"{"error":"posthog_auth"}"#)])
        let (defaults, _) = scratch()
        let store = accountStore(revoker(transport), defaults: defaults)
        try await store.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))

        let problems = await store.deleteAccount().problems

        #expect(problems.count == 1)
        #expect(problems.allSatisfy { !$0.contains("_") && $0.contains(" ") })
    }

    /// Delete Account with Apple: when Apple's confirm sheet fails (offline,
    /// no iCloud) the alert says "Try again in a moment", but the account is
    /// already forgotten, so there is nothing to try again; Apple's manual
    /// steps are never shown and the sign-in stays active.
    @Test func aFailedAppleConfirmSheetGivesTheManualSteps() async throws {
        let r = revoker(HuntTransport([]), appleCode: { _ in
            throw AppleIdentityProvider.error(from: ASAuthorizationError(.failed))
        })

        await #expect(throws: AccountError.rejected(WorkerRevoker.appleManualSteps)) {
            try await r.revoke(Self.apple)
        }
    }

    // MARK: Sign Out

    /// Sign Out after Continue with Google leaves the Google token in the
    /// Keychain; the next Google sign-in overwrites it, so that grant can
    /// never be cancelled from Sortd.
    @Test func signOutFromGoogleForgetsTheGoogleToken() async throws {
        let tokenKey = "google-identity-token"   // GoogleAuth.identityTokenKey (private)
        defer { Keychain.delete(tokenKey) }
        Keychain.set("1//old-google-refresh-token", for: tokenKey)
        try #require(Keychain.get(tokenKey) != nil)

        let (defaults, _) = scratch()
        let store = accountStore(revoker(HuntTransport([])), defaults: defaults)
        try await store.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))

        store.signOut()

        #expect(store.current == nil)
        #expect(Keychain.get(tokenKey) == nil)
        // Not just forgotten: the grant is on the revoke list, so Google still cancels it.
        #expect(GoogleAuth.pendingTokens(Keychain.get("google-revoke-pending")).contains("1//old-google-refresh-token"))
    }
}

// MARK: - Bug hunt 8 Oct 2026 (appended; the tests above are the fixed 3 Oct ones)
//
// Each test below was written to fail on the code of 8 Oct 2026. They are
// tagged `.knownBug` and run only with `scripts/test.sh --known-bugs`.

/// App Attest "not supported", for a device that cannot attest.
private final class HuntUnsupportedAttester: AppAttester {
    nonisolated init() {}
    var isSupported: Bool { false }
    func attest(clientDataHash: Data) async throws -> (keyID: String, attestation: Data) {
        throw AccountError.notSupported
    }
}

extension BugHuntAccountTests {
    private static let challengeReply = (200, #"{"challenge":"chal-1"}"#)

    private func queued(_ defaults: UserDefaults) -> [String] {
        defaults.array(forKey: AccountStore.pendingDeletesKey) as? [String] ?? []
    }

    /// A 5xx that is not the Worker's own JSON reply (a Cloudflare edge error
    /// page, a Worker exception as 500 `internal`) is treated like a 502 "no
    /// for good": the person delete is dropped and the user is told to email
    /// support, instead of being queued and retried like a 503.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "account-1008-1", "WorkerRevoker.check: an edge 5xx or a 500 drops the delete for good"))
    func anEdgeErrorPageQueuesThePersonDeleteInsteadOfDroppingIt() async throws {
        // Cloudflare's own error page: HTML, no {"error": ...} code.
        let edge = HuntTransport([Self.challengeReply, (502, "<html><body><h1>502 Bad Gateway</h1>cloudflare</body></html>")])
        let (defaultsA, _) = scratch()
        let storeA = accountStore(revoker(edge), defaults: defaultsA)
        try await storeA.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))
        let resultA = await storeA.deleteAccount()
        #expect(queued(defaultsA).count == 1, "an edge error page is not the Worker saying no: queue it")
        #expect(resultA.problems.isEmpty)

        // The Worker's own 500: an unexpected exception, worth a retry.
        let internalError = HuntTransport([Self.challengeReply, (500, #"{"error":"internal"}"#)])
        let (defaultsB, _) = scratch()
        let storeB = accountStore(revoker(internalError), defaults: defaultsB)
        try await storeB.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))
        let resultB = await storeB.deleteAccount()
        #expect(queued(defaultsB).count == 1, "a Worker 500 is not a refusal: queue it")
        #expect(resultB.problems.isEmpty)
    }

    /// Delete All Data while signed in with Google: `DataReset.deleteEverything`
    /// runs `GoogleAuth.revokePending()`, `Keychain.deleteAll()`, then
    /// `signOutForDeleteAll()` (DataControlsView.swift:115-122). The identity
    /// token is wiped by `deleteAll` before anything puts it on the revoke
    /// list, so the Google grant stays live for good with no handle left to
    /// cancel it. Sign Out (fixed 3 Oct, A5) moves the token to the list first.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "account-1008-2", "Delete All Data with Google signed in leaves the Google grant on, token gone"))
    func deleteAllWhileSignedInWithGoogleKeepsTheGrantOnTheRevokeList() async throws {
        let tokenKey = "google-identity-token"   // GoogleAuth.identityTokenKey (private)
        let pendingKey = "google-revoke-pending" // GoogleAuth.pendingKey (private)
        defer { Keychain.delete(tokenKey); Keychain.delete(pendingKey) }
        Keychain.set("1//delete-all-google-refresh-token", for: tokenKey)
        try #require(Keychain.get(tokenKey) != nil)

        let (defaults, _) = scratch()
        let store = accountStore(revoker(HuntTransport([])), defaults: defaults)
        try await store.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))

        // The same three steps, in the same order, as DataReset.deleteEverything.
        GoogleAuth.revokePending()
        Keychain.deleteAll()
        store.signOutForDeleteAll()

        #expect(store.current == nil)
        #expect(Keychain.get(tokenKey) == nil)
        #expect(GoogleAuth.pendingTokens(Keychain.get(pendingKey)).contains("1//delete-all-google-refresh-token"),
                "the grant must be on the revoke list, as Sign Out leaves it")
    }

    /// Delete Account with Apple: the person confirms with a different Apple
    /// Account. The alert says "nothing was cancelled", yet the sign-in is
    /// forgotten and the usage record deleted, so there is no second try with
    /// the right Apple ID and the grant can only be stopped by hand.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "account-1008-3", "a wrong Apple Account at the confirm sheet signs out and deletes the record anyway"))
    func aWrongAppleAccountAtTheConfirmSheetLeavesTheSignInInPlace() async throws {
        let transport = HuntTransport([Self.challengeReply, (204, "")])
        let r = revoker(transport, appleCode: { _ in
            WorkerRevoker.AppleCode(user: "009999.someone-else", code: "c0de")
        })
        let (defaults, _) = scratch()
        let store = accountStore(r, defaults: defaults)
        try await store.signIn(with: ResolvedIdentityProvider(result: .success(Self.apple)))

        let result = await store.deleteAccount()

        #expect(result.problems == [WorkerRevoker.wrongAppleAccount])
        #expect(store.current == Self.apple, "\"nothing was cancelled\": stay signed in so the right Apple ID can be used")
        #expect(transport.requests.isEmpty, "the usage record was deleted although the delete was refused")
    }

    /// A device that cannot attest (App Attest unsupported) with a Google
    /// account: the one problem shown is Apple's "Sign in with Apple › Stop
    /// Using" steps, which have nothing to do with a Google sign-in or with
    /// the usage record that was not deleted.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "account-1008-4", "AccountError.notSupported shows Apple's manual steps to a Google user"))
    func anUnsupportedDeviceDoesNotShowAppleStepsToAGoogleUser() async throws {
        let r = WorkerRevoker(url: Self.workerURL, deps: WorkerRevoker.Dependencies(
            transport: { _ in throw URLError(.badServerResponse) },
            attester: HuntUnsupportedAttester(),
            appleCode: { _ in throw AccountError.cancelled },
            googleRevoke: {},
            clientID: "com.kameshraj.sortd"))
        let (defaults, _) = scratch()
        let store = accountStore(r, defaults: defaults)
        try await store.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))

        let problems = await store.deleteAccount().problems

        #expect(problems.count == 1)
        #expect(problems.allSatisfy { !$0.contains("Sign in with Apple") && !$0.contains("Apple Account") },
                "a Google user and a usage record: no Apple steps")
    }

    /// A delete queued offline is refused for good at the next launch (502
    /// `posthog_auth`): `retryPendingDeletes` drops it and throws the reason
    /// away. The person was never told anything (offline queues without a
    /// notice), so the usage record stays and nobody knows.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "account-1008-5", "retryPendingDeletes drops a refused job with no word to the user"))
    func aQueuedDeleteRefusedAtRetryIsNotDroppedInSilence() async throws {
        let (defaults, _) = scratch()
        let offline = WorkerRevoker(url: Self.workerURL, deps: WorkerRevoker.Dependencies(
            transport: { _ in throw URLError(.notConnectedToInternet) },
            attester: HuntAttester(),
            appleCode: { _ in throw AccountError.cancelled },
            googleRevoke: {},
            clientID: "com.kameshraj.sortd"))
        let first = accountStore(offline, defaults: defaults)
        try await first.signIn(with: ResolvedIdentityProvider(result: .success(Self.google)))
        let result = await first.deleteAccount()
        #expect(result.problems.isEmpty)
        #expect(queued(defaults).count == 1)

        // Next launch, online: the Worker says no for good.
        let launch = accountStore(revoker(HuntTransport([Self.challengeReply, (502, #"{"error":"posthog_auth"}"#)])),
                                  defaults: defaults)
        await launch.retryPendingDeletes()

        #expect(queued(defaults).count == 1,
                "until the person can be told, a refused job must not vanish from the queue")
    }

    /// Restore hits iCloud's rate limit: the status line says "Trying again in
    /// 30 s", but no retry is scheduled (a restore has no context to retry
    /// with), and the `.paused` status blocks every automatic backup for the
    /// rest of the session, long after the 30 s have passed.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "account-1008-6", "a rate-limited restore pauses automatic backups for the whole session"))
    func aRateLimitedRestoreDoesNotBlockBackupsForTheSession() async throws {
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let ctx = try context()
        var now = Date(timeIntervalSince1970: 1_790_500_000)
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch().0, clock: { now })
        cloud.sleep = { _ in }
        cloud.isEnabled = true
        try log(ctx, "Woolworths", 58.30, minutes: 0)
        try await cloud.backUpNow(from: ctx)

        // iCloud asks for a 30 s wait while a restore fetches the record.
        cloudStore.fetchError = CloudBackupError.rateLimited(retryAfter: 30)
        _ = try? await cloud.restore(into: ctx, mode: .merge)
        #expect(cloud.status == .paused(.rateLimited(retryAfter: 30)))
        cloudStore.fetchError = nil

        // A quarter of an hour later a purchase is logged: the gap has passed
        // and iCloud is fine again.
        now = now.addingTimeInterval(15 * 60)
        try log(ctx, "Coles", 12.00, minutes: 30)
        await cloud.backUpIfDue(from: ctx)

        let key = try #require(keys.key)
        let plain = try CloudBackup.decrypt(try #require(cloudStore.saved).blob, with: key)
        #expect(Backup.contents(of: plain)?.purchases == 2, "the backup is still paused on a 30 s limit that ended long ago")
        #expect(cloud.status == .idle)
    }
}

extension BugHuntAccountTests {
    /// Backup switched off, "Delete iCloud Copy" hits iCloud's rate limit:
    /// `deleteCloudCopy` calls `fail(with:context: nil)`, so no retry is set
    /// and `.paused(.rateLimited)` is never cleared. Switching backup back on
    /// does not clear it either, so no automatic backup runs for the rest of
    /// the session. Same root cause as account-1008-6.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "account-1008-6b", "a rate-limited Delete iCloud Copy blocks automatic backups after switching back on"))
    func aRateLimitedCopyDeleteDoesNotBlockBackupsAfterSwitchingBackOn() async throws {
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let ctx = try context()
        var now = Date(timeIntervalSince1970: 1_790_500_000)
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch().0, clock: { now })
        cloud.sleep = { _ in }
        cloud.isEnabled = true
        try log(ctx, "Woolworths", 58.30, minutes: 0)
        try await cloud.backUpNow(from: ctx)

        // Switch off, pick "Delete iCloud Copy"; iCloud asks for a 30 s wait.
        cloud.isEnabled = false
        cloudStore.deleteError = CloudBackupError.rateLimited(retryAfter: 30)
        _ = try? await cloud.deleteCloudCopy()
        cloudStore.deleteError = nil

        // A quarter of an hour later: switch back on and log a purchase.
        now = now.addingTimeInterval(15 * 60)
        cloud.isEnabled = true
        try log(ctx, "Coles", 12.00, minutes: 30)
        await cloud.backUpIfDue(from: ctx)

        let key = try #require(keys.key)
        let plain = try CloudBackup.decrypt(try #require(cloudStore.saved).blob, with: key)
        #expect(Backup.contents(of: plain)?.purchases == 2, "backup is back on, but still paused on a 30 s limit")
        #expect(cloud.status == .idle)
    }
}
