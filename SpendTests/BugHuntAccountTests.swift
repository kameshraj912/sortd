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
