import Foundation
import AuthenticationServices
import CryptoKit
import DeviceCheck
import Observation
import Security

// Optional sign-in with Apple or Google (overhaul sub-spec 4). Sortd has no
// server, so an account holds nothing: it is an identity for support and one
// PostHog person. The ID (Apple `user`, Google `sub`) lives in this phone's
// Keychain and never syncs. Deleting the account asks the provider to cancel
// the sign-in and a stateless Worker (docs/specs/2026-09-25-account-worker.md)
// to delete the PostHog person. A job the network could not carry is queued
// in `accountPendingDeletes` as hashes only and retried at the next launch
// (the same pattern as `GoogleAuth.retryPendingRevokes`). An Apple revoke is
// never queued: it needs a fresh authorization code, which lives five minutes.
//
// The Sign in with Apple capability needs the paid developer account, so the
// account screen ships behind the SORTD_SIGNIN compile flag (off in both
// configs; see AccountSettingsView.swift). Everything in this file compiles
// regardless, so the tests (fakes only) run everywhere.

enum AccountProvider: String, Codable, Sendable, CaseIterable {
    case apple, google

    var name: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}

/// Who is signed in: the provider's stable subject and, when they shared
/// it, the email. Apple only sends the email on the first sign-in.
struct Account: Codable, Equatable, Sendable {
    let provider: AccountProvider
    let subject: String
    let email: String?

    /// "r•••@example.com": enough to recognise, not enough to copy.
    var maskedEmail: String? {
        guard let email, let at = email.firstIndex(of: "@") else { return nil }
        let first = email[email.startIndex]
        return "\(first)•••\(email[at...])"
    }
}

enum AccountError: LocalizedError, Equatable {
    case cancelled
    /// Could not be reached now; the store queues the job and retries.
    case offline
    /// The provider answered without a usable ID.
    case noIdentity
    /// The Worker or the provider said no for good (a 502, a used code, a
    /// different account). Never retried; the text is shown to the user.
    case rejected(String)
    /// App Attest is not available here (simulator, some devices).
    case notSupported
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .offline: "Sortd couldn't reach the server. It will try again next time you open the app."
        case .noIdentity: "Sign-in didn't finish. Please try again."
        case .rejected(let text): text
        case .notSupported: "This device can't prove it is running Sortd, so the server was not asked. " + WorkerRevoker.appleManualSteps
        case .server(let text): text
        }
    }
}

// MARK: - Protocols (fakes in tests)

/// Apple's sheet or Google's page; returns the account or throws.
@MainActor
protocol IdentityProvider {
    func signIn() async throws -> Account
}

/// Where the signed-in account is kept. Per device: never synchronizable.
@MainActor
protocol AccountKeychain {
    func load() throws -> Account?
    func save(_ account: Account) throws
    func delete() throws
}

/// Cancels the sign-in with the provider and deletes the PostHog person.
/// `offline` means "queue it and retry"; any other error drops the job.
@MainActor
protocol AccountRevoker {
    func revoke(_ account: Account) async throws
    func deletePerson(hash: String) async throws
    /// A revoke queued earlier. The queue keeps no subject or email, only
    /// the provider and sha256(subject). Optional: a fake leaves it out.
    func revoke(queued provider: AccountProvider, subjectHash: String) async throws
}

extension AccountRevoker {
    /// For conformers without a queued path (the test fakes): the same
    /// call with a placeholder account that carries the subject hash.
    func revoke(queued provider: AccountProvider, subjectHash: String) async throws {
        try await revoke(Account(provider: provider, subject: subjectHash, email: nil))
    }
}

/// The analytics identity: `identify` with the hash, `reset` on the way
/// out. The events are optional; a spy in tests leaves them out.
@MainActor
protocol IdentitySink {
    func identify(_ hash: String)
    func reset()
    func signedIn(provider: AccountProvider)
    func signedOut()
}

extension IdentitySink {
    func signedIn(provider: AccountProvider) {}
    func signedOut() {}
}

/// Asks the provider whether the sign-in still stands (Apple: Settings ›
/// Apple Account › Sign in with Apple › stop using).
@MainActor
protocol CredentialStateChecker {
    func isRevoked(_ account: Account) async -> Bool
}

/// App Attest: proves to the Worker that a real copy of Sortd is calling.
@MainActor
protocol AppAttester {
    var isSupported: Bool { get }
    func attest(clientDataHash: Data) async throws -> (keyID: String, attestation: Data)
}

// MARK: - Store

@MainActor @Observable
final class AccountStore {
    /// Delete jobs that haven't reached the provider or the Worker yet.
    static let pendingDeletesKey = "accountPendingDeletes"

    private(set) var current: Account?

    private let keychain: AccountKeychain
    private let revoker: AccountRevoker
    private let sink: IdentitySink
    private let checker: CredentialStateChecker
    private let defaults: UserDefaults
    private let salt: String
    private var retrying = false

    init(keychain: AccountKeychain, revoker: AccountRevoker, sink: IdentitySink,
         checker: CredentialStateChecker, defaults: UserDefaults, salt: String) {
        self.keychain = keychain
        self.revoker = revoker
        self.sink = sink
        self.checker = checker
        self.defaults = defaults
        self.salt = salt
        current = try? keychain.load()
    }

    /// The app's store. The salt is the fixed analytics one, so the account
    /// hash and PostHog's distinct id are the same string on every phone.
    static let shared = AccountStore(keychain: KeychainAccountStore(),
                                     revoker: WorkerRevoker.fromBundle(),
                                     sink: AnalyticsIdentitySink(),
                                     checker: AppleCredentialChecker(),
                                     defaults: .standard,
                                     salt: Analytics.accountSalt)

    /// sha256(salt + provider + subject), 64 lowercase hex characters. The
    /// one function PostHog's id uses too; never the email or the raw subject.
    nonisolated static func hash(salt: String, provider: AccountProvider, subject: String) -> String {
        Analytics.distinctId(salt: salt, provider: provider.rawValue, subject: subject)
    }

    /// sha256 of the subject alone, for the queue: enough to tell two
    /// accounts apart, not enough to name one.
    nonisolated static func subjectHash(_ subject: String) -> String {
        SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Runs the provider's sheet. A cancel throws `AccountError.cancelled`
    /// and leaves nothing behind.
    func signIn(with provider: IdentityProvider) async throws {
        let account = try await provider.signIn()
        try keychain.save(account)
        current = account
        sink.identify(Self.hash(salt: salt, provider: account.provider, subject: account.subject))
        sink.signedIn(provider: account.provider)
        log.info("account: signed in with \(account.provider.rawValue, privacy: .public)")
    }

    /// Forgets the ID on this phone. Purchases stay. Says `signed_out`
    /// under the old id, then resets.
    func signOut() {
        guard current != nil else { return }
        sink.signedOut()
        forgetLocally()
        sink.reset()
        log.info("account: signed out")
    }

    /// Resets the analytics id first (nothing may be sent under the person
    /// about to be deleted, so no `signed_out`), then asks the provider to
    /// cancel the sign-in and the Worker to delete the PostHog person, then
    /// forgets the account here. Jobs the network could not carry are
    /// queued, hash included, and retried at the next launch. Returns what
    /// could not be done for good, in words for the user.
    @discardableResult
    func deleteAccount() async -> [String] {
        guard let account = current else { return [] }
        let hash = Self.hash(salt: salt, provider: account.provider, subject: account.subject)
        let subjectHash = Self.subjectHash(account.subject)
        sink.reset()
        var failed: [PendingDelete] = []
        var problems: [String] = []
        do {
            try await revoker.revoke(account)
        } catch {
            sort(error, job: PendingDelete(kind: .revoke, provider: account.provider, subjectHash: subjectHash, hash: hash),
                 failed: &failed, problems: &problems)
        }
        do {
            try await revoker.deletePerson(hash: hash)
        } catch {
            sort(error, job: PendingDelete(kind: .person, provider: account.provider, subjectHash: subjectHash, hash: hash),
                 failed: &failed, problems: &problems)
        }
        forgetLocally()
        // Behind any jobs an earlier delete left, never over them.
        queue(pending + failed)
        log.info("account: deleted, \(failed.count, privacy: .public) job(s) queued, \(problems.count, privacy: .public) dropped")
        return problems
    }

    /// Delete All Data: the PostHog person goes too, so its delete is
    /// queued (and sent by the caller's retry, or at the next launch). The
    /// sign-in itself is not cancelled; the user may sign in again.
    func signOutForDeleteAll() {
        guard let account = current else { return }
        let hash = Self.hash(salt: salt, provider: account.provider, subject: account.subject)
        sink.reset()
        forgetLocally()
        queue(pending + [PendingDelete(kind: .person, provider: account.provider,
                                       subjectHash: Self.subjectHash(account.subject), hash: hash)])
        log.info("account: signed out for Delete All, person delete queued")
    }

    /// Runs `work` (the Delete All defaults wipe) and puts the queue back
    /// afterwards, so a delete that had not reached the Worker survives.
    func preservePendingDeletes(across work: () -> Void) {
        let kept = pending
        work()
        queue(kept)
    }

    /// Tries the delete jobs that failed before. Called at launch. Only the
    /// jobs that succeed (or are dropped) leave the queue: a delete that
    /// happens while this runs keeps its own jobs.
    func retryPendingDeletes() async {
        guard !retrying else { return }
        retrying = true
        defer { retrying = false }
        let jobs = pending
        guard !jobs.isEmpty else { return }
        var stillOffline: [PendingDelete] = []
        var problems: [String] = []
        for job in jobs {
            do {
                switch job.kind {
                case .revoke: try await revoker.revoke(queued: job.provider, subjectHash: job.subjectHash)
                case .person: try await revoker.deletePerson(hash: job.hash)
                }
            } catch {
                sort(error, job: job, failed: &stillOffline, problems: &problems)
            }
        }
        let done = Set(jobs).subtracting(stillOffline)
        queue(pending.filter { !done.contains($0) })
    }

    /// Signed in, but the provider says the sign-in was withdrawn: sign out
    /// quietly. Unknown or unreachable counts as still valid.
    func checkCredentialAtLaunch() async {
        guard let account = current else { return }
        if await checker.isRevoked(account) {
            signOut()
            log.notice("account: the \(account.provider.rawValue, privacy: .public) sign-in was withdrawn, signed out")
        }
    }

    // MARK: Private

    private func forgetLocally() {
        current = nil
        try? keychain.delete()
    }

    /// `offline` keeps the job for a retry; a cancel drops it quietly;
    /// anything else drops it and keeps the reason for the user.
    private func sort(_ error: Error, job: PendingDelete, failed: inout [PendingDelete], problems: inout [String]) {
        switch error as? AccountError {
        case .offline:
            failed.append(job)
            log.notice("account: \(job.kind.rawValue, privacy: .public) job could not be sent, queued")
        case .cancelled:
            log.notice("account: \(job.kind.rawValue, privacy: .public) job cancelled, dropped")
        default:
            problems.append(error.localizedDescription)
            log.error("account: \(job.kind.rawValue, privacy: .public) job dropped (\(error.localizedDescription, privacy: .public))")
        }
    }

    private var pending: [PendingDelete] {
        (defaults.array(forKey: Self.pendingDeletesKey) as? [String] ?? []).compactMap(PendingDelete.init(encoded:))
    }

    private func queue(_ jobs: [PendingDelete]) {
        if jobs.isEmpty {
            defaults.removeObject(forKey: Self.pendingDeletesKey)
        } else {
            defaults.set(jobs.map(\.encoded), forKey: Self.pendingDeletesKey)
        }
    }

    /// One queued job, stored as a JSON string in the defaults array.
    /// Hashes only: never the subject, never the email.
    struct PendingDelete: Codable, Hashable {
        enum Kind: String, Codable { case revoke, person }
        let kind: Kind
        let provider: AccountProvider
        let subjectHash: String
        let hash: String

        var encoded: String {
            String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
        }

        init(kind: Kind, provider: AccountProvider, subjectHash: String, hash: String) {
            self.kind = kind
            self.provider = provider
            self.subjectHash = subjectHash
            self.hash = hash
        }

        init?(encoded: String) {
            guard let job = try? JSONDecoder().decode(PendingDelete.self, from: Data(encoded.utf8)) else { return nil }
            self = job
        }
    }
}

// MARK: - App implementations

/// A generic-password item in its own service, this device only. Not in
/// `Keychain` (the Gmail tokens' service): `Keychain.deleteAll()` is the
/// Delete All wipe, and the account is signed out on its own path.
@MainActor
final class KeychainAccountStore: AccountKeychain {
    private static let service = "com.kameshraj.spend.account"
    private static let item = "identity"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: Self.item]
    }

    func load() throws -> Account? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw AccountError.server("Keychain read failed (\(status)).") }
        return try JSONDecoder().decode(Account.self, from: data)
    }

    func save(_ account: Account) throws {
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = try JSONEncoder().encode(account)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw AccountError.server("Keychain write failed (\(status)).") }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.server("Keychain delete failed (\(status)).") }
    }
}

/// The stateless account Worker, to docs/specs/2026-09-25-account-worker.md:
/// `POST /v1/challenge` binds a challenge to the route and the exact body,
/// App Attest signs that challenge, and the action route gets the body with
/// the three `X-Attest-*` headers. With no URL in the build every call
/// throws `offline`, so the store keeps the job queued until a build with a
/// Worker retries it.
///
/// Apple: a fresh authorization code is needed each time (re-authenticate
/// at delete), so a failure after that is `rejected` with Apple's manual
/// steps, never queued. Google needs no Worker: `GoogleAuth` revokes from
/// the phone, with its own retry list. The Google grant is one per account,
/// so when Gmail is connected for the same address the identity token is
/// forgotten locally and the grant is left alone.
@MainActor
final class WorkerRevoker: AccountRevoker {
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// A fresh Sign in with Apple: which Apple user answered, and the code.
    struct AppleCode {
        let user: String
        let code: String
    }

    struct Dependencies {
        var transport: Transport
        var attester: AppAttester
        /// Asks Apple again and returns the single-use code.
        var appleCode: @MainActor (Account) async throws -> AppleCode
        /// Emails of the Gmail accounts connected for receipts.
        var connectedGmail: @MainActor () -> [String]
        var googleRevoke: @MainActor () async -> Void
        var clientID: String

        static var live: Dependencies {
            Dependencies(
                transport: { req in
                    let (data, response) = try await GoogleAuth.session.data(for: req)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    return (data, http)
                },
                attester: DeviceAppAttester(),
                appleCode: { _ in
                    let auth = try await AppleIdentityProvider().authorize()
                    guard let code = auth.authorizationCode else { throw AccountError.rejected(appleManualSteps) }
                    return AppleCode(user: auth.account.subject, code: code)
                },
                connectedGmail: { GmailSync.accounts.map(\.email) },
                googleRevoke: { await GoogleAuth.revokeIdentity() },
                clientID: Bundle.main.bundleIdentifier ?? "com.kameshraj.spend")
        }
    }

    nonisolated static let appleManualSteps = "Apple couldn't be asked to cancel the sign-in. To stop Sortd using your Apple Account: Settings › your name › Sign in with Apple › Sortd › Stop Using."
    nonisolated static let wrongAppleAccount = "That's a different Apple Account. Sortd is signed in with another one, so nothing was cancelled."

    let url: URL?
    private let deps: Dependencies

    init(url: URL?, deps: Dependencies? = nil) {
        self.url = url
        self.deps = deps ?? .live
    }

    /// `ACCOUNT_WORKER_URL` from Info.plist (Config.xcconfig / Secrets.xcconfig).
    static func fromBundle() -> WorkerRevoker {
        let text = (Bundle.main.object(forInfoDictionaryKey: "ACCOUNT_WORKER_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "//" is a comment in an xcconfig, so a URL that lost its scheme is
        // a broken line, not a Worker.
        let url = text.contains("://") ? URL(string: text) : nil
        if url == nil { log.notice("account: no Worker URL (ACCOUNT_WORKER_URL is empty), deletes are queued") }
        return WorkerRevoker(url: url)
    }

    /// Gmail is connected for this same Google account: revoking the
    /// identity token would cancel that grant too.
    nonisolated static func keepsGmail(_ account: Account, connected: [String]) -> Bool {
        guard account.provider == .google, let email = account.email?.lowercased() else { return false }
        return connected.contains { $0.lowercased() == email }
    }

    func revoke(_ account: Account) async throws {
        switch account.provider {
        case .google:
            if Self.keepsGmail(account, connected: deps.connectedGmail()) {
                log.notice("account: Gmail is connected for this Google account, grant kept")
                GoogleAuth.forgetIdentityToken()
                return
            }
            await deps.googleRevoke()
        case .apple:
            // A cancel in Apple's sheet passes through as `cancelled`.
            let fresh = try await deps.appleCode(account)
            guard fresh.user == account.subject else { throw AccountError.rejected(Self.wrongAppleAccount) }
            do {
                try await post(route: "apple/revoke", body: ["client_id": deps.clientID, "authorization_code": fresh.code])
            } catch {
                // The code is single-use and lives five minutes: no retry can succeed.
                throw AccountError.rejected(Self.appleManualSteps)
            }
        }
    }

    func revoke(queued provider: AccountProvider, subjectHash: String) async throws {
        switch provider {
        case .google: await deps.googleRevoke()
        case .apple: throw AccountError.rejected(Self.appleManualSteps)
        }
    }

    func deletePerson(hash: String) async throws {
        try await post(route: "posthog/delete-person", body: ["distinct_id": hash])
    }

    // MARK: Worker calls

    /// Challenge, attest, act. `offline` for anything worth retrying (no
    /// URL, network, 429, 503), `rejected` for a 4xx or 502.
    private func post(route: String, body: [String: String]) async throws {
        guard let url else { throw AccountError.offline }
        guard deps.attester.isSupported else { throw AccountError.notSupported }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bodyData = try encoder.encode(body)
        let bodyHash = SHA256.hash(data: bodyData).map { String(format: "%02x", $0) }.joined()

        let (challengeData, challengeResponse) = try await send(
            url.appending(path: "v1/challenge"),
            body: try encoder.encode(["route": route, "body_sha256": bodyHash]), headers: [:])
        try Self.check(challengeResponse, data: challengeData)
        guard let json = try? JSONSerialization.jsonObject(with: challengeData) as? [String: Any],
              let challenge = json["challenge"] as? String, !challenge.isEmpty else {
            throw AccountError.offline
        }

        let (keyID, attestation) = try await deps.attester.attest(clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        let (data, response) = try await send(url.appending(path: "v1/" + route), body: bodyData, headers: [
            "X-Attest-Key-Id": keyID,
            "X-Attest-Object": attestation.base64EncodedString(),
            "X-Attest-Challenge": challenge,
        ])
        try Self.check(response, data: data)
    }

    private func send(_ url: URL, body: Data, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = body
        req.timeoutInterval = 20
        do {
            return try await deps.transport(req)
        } catch {
            throw AccountError.offline
        }
    }

    /// 2xx is done. 429 and 503 are the Worker's own "try later". 502 is
    /// Apple's or PostHog's no, and any other 4xx is ours: neither is retried.
    private static func check(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300: return
        case 429, 503: throw AccountError.offline
        default:
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw AccountError.rejected(code ?? "http_\(response.statusCode)")
        }
    }
}

/// App Attest through `DCAppAttestService`. A fresh key each time: the
/// Worker keeps nothing, so it cannot verify an assertion from an old one.
@MainActor
final class DeviceAppAttester: AppAttester {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func attest(clientDataHash: Data) async throws -> (keyID: String, attestation: Data) {
        let service = DCAppAttestService.shared
        let keyID = try await service.generateKey()
        let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        return (keyID, attestation)
    }
}

/// PostHog through the one door, `Analytics.shared`.
@MainActor
final class AnalyticsIdentitySink: IdentitySink {
    func identify(_ hash: String) { Analytics.shared.signedIn(hash: hash) }
    func reset() { Analytics.shared.signedOut() }
    func signedIn(provider: AccountProvider) {
        Analytics.shared.track(.signedIn, ["provider": .string(provider.rawValue)])
    }
    func signedOut() { Analytics.shared.track(.signedOut) }
}

/// Apple's credential state. Google has no equivalent without a server,
/// so a Google sign-in is never reported revoked.
@MainActor
final class AppleCredentialChecker: CredentialStateChecker {
    func isRevoked(_ account: Account) async -> Bool {
        guard account.provider == .apple else { return false }
        // Unreachable or unknown: keep the sign-in.
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: account.subject)
        return state == .revoked || state == .notFound
    }
}

// MARK: - Providers

/// What Apple's sheet returned: the account, and the single-use code the
/// Worker exchanges to revoke (nil when Apple sent none).
struct AppleAuthorization: Sendable {
    let account: Account
    let authorizationCode: String?
}

/// Sign in with Apple through `ASAuthorizationController`, email scope
/// only. The SwiftUI `SignInWithAppleButton` runs the same controller
/// itself; its result goes through `account(from:)` and `error(from:)`.
@MainActor
final class AppleIdentityProvider: NSObject, IdentityProvider, ASAuthorizationControllerDelegate {
    /// The delegate is called by the system on whatever thread it likes;
    /// the box takes the callback and hands the result to the waiting
    /// caller once. A `let` of a Sendable type, so nonisolated code can read it.
    nonisolated private final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<AppleAuthorization, Error>?
        func wait(_ c: CheckedContinuation<AppleAuthorization, Error>) {
            lock.lock(); continuation = c; lock.unlock()
        }
        func resume(_ result: Result<AppleAuthorization, Error>) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(with: result)
        }
    }

    /// Hands the system the window the sheet goes in. Made only when there
    /// is one; with none the controller picks for itself, so no code path
    /// has to invent a window.
    nonisolated private final class Anchor: NSObject, ASAuthorizationControllerPresentationContextProviding {
        let window: ASPresentationAnchor
        init(_ window: ASPresentationAnchor) { self.window = window }
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { window }
    }

    private let pending = Pending()
    private var controller: ASAuthorizationController?
    private var anchor: Anchor?

    func signIn() async throws -> Account {
        try await authorize().account
    }

    /// Apple's sheet; the account plus the code (for a revoke).
    func authorize() async throws -> AppleAuthorization {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.compactMap(\.keyWindow).first ?? scenes.first.map({ ASPresentationAnchor(windowScene: $0) }) {
            anchor = Anchor(window)
            controller.presentationContextProvider = anchor
        }
        self.controller = controller
        defer { self.controller = nil; anchor = nil }
        return try await withCheckedThrowingContinuation { cont in
            pending.wait(cont)
            controller.performRequests()
        }
    }

    /// The Apple ID credential as an account, or nil when it is not one.
    nonisolated static func account(from auth: ASAuthorization) -> Account? {
        authorization(from: auth)?.account
    }

    nonisolated static func authorization(from authorization: ASAuthorization) -> AppleAuthorization? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return nil }
        return AppleAuthorization(account: Account(provider: .apple, subject: credential.user, email: credential.email),
                                  authorizationCode: credential.authorizationCode.map { String(decoding: $0, as: UTF8.self) })
    }

    /// A cancel in Apple's sheet as `AccountError.cancelled`; the rest as is.
    nonisolated static func error(from error: Error) -> Error {
        if let e = error as? ASAuthorizationError, e.code == .canceled { return AccountError.cancelled }
        return error
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let result: Result<AppleAuthorization, Error> = Self.authorization(from: authorization).map { .success($0) }
            ?? .failure(AccountError.noIdentity)
        pending.resume(result)
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        pending.resume(.failure(Self.error(from: error)))
    }
}

/// Google identity only: `openid email`, never the Gmail scope.
@MainActor
final class GoogleIdentityProvider: IdentityProvider {
    func signIn() async throws -> Account {
        do {
            return try await GoogleAuth().signInForIdentity()
        } catch GoogleAuth.AuthError.cancelled {
            throw AccountError.cancelled
        }
    }
}

/// An account already in hand (the SwiftUI Apple button ran the sheet).
@MainActor
struct ResolvedIdentityProvider: IdentityProvider {
    let result: Result<Account, Error>
    func signIn() async throws -> Account { try result.get() }
}
