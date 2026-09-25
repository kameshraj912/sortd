import Foundation
import AuthenticationServices
import Observation
import Security

// Optional sign-in with Apple or Google (overhaul sub-spec 4). Sortd has no
// server, so an account holds nothing: it is an identity for support and one
// PostHog person. The ID (Apple `user`, Google `sub`) lives in this phone's
// Keychain and never syncs. Deleting the account asks the provider to cancel
// the sign-in and a stateless Worker to delete the PostHog person; if either
// cannot be reached the job is queued in `accountPendingDeletes` and retried
// at the next launch (the same pattern as `GoogleAuth.retryPendingRevokes`).
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
    case offline
    /// The provider answered without a usable ID.
    case noIdentity
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .offline: "Sortd couldn't reach the server. It will try again next time you open the app."
        case .noIdentity: "Sign-in didn't finish. Please try again."
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
/// Throws when it cannot reach whatever it needs; the store queues the job.
@MainActor
protocol AccountRevoker {
    func revoke(_ account: Account) async throws
    func deletePerson(hash: String) async throws
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

    /// Forgets the ID on this phone. Purchases stay.
    func signOut() {
        guard current != nil else { return }
        forgetLocally()
        log.info("account: signed out")
    }

    /// Cancels the sign-in with the provider and deletes the PostHog person,
    /// then forgets the account here. The provider and the Worker are asked
    /// first, with the hash made now; whatever cannot be reached is queued
    /// (hash included, never recomputed) and retried at the next launch.
    func deleteAccount() async {
        guard let account = current else { return }
        let hash = Self.hash(salt: salt, provider: account.provider, subject: account.subject)
        var jobs = [PendingDelete.revoke(account), .person(hash)]
        await run(&jobs)
        forgetLocally()
        // Behind any jobs an earlier delete left, never over them.
        queue(pending + jobs)
        log.info("account: deleted, \(jobs.count, privacy: .public) job(s) still pending")
    }

    /// Tries the delete jobs that failed before. Called at launch.
    func retryPendingDeletes() async {
        var jobs = pending
        guard !jobs.isEmpty else { return }
        await run(&jobs)
        queue(jobs)
    }

    /// Signed in, but the provider says the sign-in was withdrawn: sign out
    /// quietly. Unknown or unreachable counts as still valid.
    func checkCredentialAtLaunch() async {
        guard let account = current else { return }
        if await checker.isRevoked(account) {
            forgetLocally()
            log.notice("account: the \(account.provider.rawValue, privacy: .public) sign-in was withdrawn, signed out")
        }
    }

    // MARK: Private

    private func forgetLocally() {
        sink.signedOut()
        current = nil
        try? keychain.delete()
        sink.reset()
    }

    /// Runs each job, keeping only the ones that failed.
    private func run(_ jobs: inout [PendingDelete]) async {
        var failed: [PendingDelete] = []
        for job in jobs {
            do {
                switch job {
                case .revoke(let account): try await revoker.revoke(account)
                case .person(let hash): try await revoker.deletePerson(hash: hash)
                }
            } catch {
                log.notice("account: delete job failed, queued (\(error.localizedDescription, privacy: .public))")
                failed.append(job)
            }
        }
        jobs = failed
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
    enum PendingDelete: Codable, Equatable {
        case revoke(Account)
        case person(String)

        var encoded: String {
            String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
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

/// The stateless revoke Worker (its own spec, not in this repo yet). With no
/// URL in the build every call throws `offline`, so the store keeps the job
/// queued until a build with a Worker retries it. Google sign-ins are
/// cancelled by `GoogleAuth` directly, which has its own retry list.
///
/// Request shape is provisional until the Worker spec is approved: JSON
/// `{"action":"revoke","provider":…,"subject":…}` and
/// `{"action":"delete_person","hash":…}`.
@MainActor
final class WorkerRevoker: AccountRevoker {
    let url: URL?

    init(url: URL?) { self.url = url }

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

    func revoke(_ account: Account) async throws {
        switch account.provider {
        case .google:
            await GoogleAuth.revokeIdentity()
        case .apple:
            try await post(["action": "revoke", "provider": account.provider.rawValue, "subject": account.subject])
        }
    }

    func deletePerson(hash: String) async throws {
        try await post(["action": "delete_person", "hash": hash])
    }

    private func post(_ body: [String: String]) async throws {
        guard let url else { throw AccountError.offline }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 20
        let response: URLResponse
        do {
            (_, response) = try await GoogleAuth.session.data(for: req)
        } catch {
            throw AccountError.offline
        }
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            throw AccountError.offline
        }
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

/// Sign in with Apple through `ASAuthorizationController`, email scope
/// only. The SwiftUI `SignInWithAppleButton` runs the same controller
/// itself; its result goes through `account(from:)` and `error(from:)`.
@MainActor
final class AppleIdentityProvider: NSObject, IdentityProvider,
                                   ASAuthorizationControllerDelegate,
                                   ASAuthorizationControllerPresentationContextProviding {
    /// The delegate is called by the system on whatever thread it likes;
    /// the box takes the callback and hands the result to the waiting
    /// caller once. A `let` of a Sendable type, so nonisolated code can read it.
    nonisolated private final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Account, Error>?
        func wait(_ c: CheckedContinuation<Account, Error>) {
            lock.lock(); continuation = c; lock.unlock()
        }
        func resume(_ result: Result<Account, Error>) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(with: result)
        }
    }

    private let pending = Pending()
    private var controller: ASAuthorizationController?

    func signIn() async throws -> Account {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        defer { self.controller = nil }
        return try await withCheckedThrowingContinuation { cont in
            pending.wait(cont)
            controller.performRequests()
        }
    }

    /// The Apple ID credential as an account, or nil when it is not one.
    nonisolated static func account(from authorization: ASAuthorization) -> Account? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return nil }
        return Account(provider: .apple, subject: credential.user, email: credential.email)
    }

    /// A cancel in Apple's sheet as `AccountError.cancelled`; the rest as is.
    nonisolated static func error(from error: Error) -> Error {
        if let e = error as? ASAuthorizationError, e.code == .canceled { return AccountError.cancelled }
        return error
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let result: Result<Account, Error> = Self.account(from: authorization).map { .success($0) } ?? .failure(AccountError.noIdentity)
        pending.resume(result)
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        pending.resume(.failure(Self.error(from: error)))
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.compactMap(\.keyWindow).first { return window }
            return ASPresentationAnchor(windowScene: scenes[0])
        }
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
