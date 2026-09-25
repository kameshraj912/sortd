import Testing
import Foundation
import SwiftData
@testable import Spend

// MARK: - Fakes

private final class FakeIdentityProvider: IdentityProvider {
    let result: Result<Account, Error>
    init(_ result: Result<Account, Error>) { self.result = result }
    func signIn() async throws -> Account {
        switch result {
        case .success(let a): return a
        case .failure(let e): throw e
        }
    }
}

private final class FakeAccountKeychain: AccountKeychain {
    var stored: Account?
    func load() throws -> Account? { stored }
    func save(_ a: Account) throws { stored = a }
    func delete() throws { stored = nil }
}

private final class FakeAccountRevoker: AccountRevoker {
    var revokeCount = 0
    var deletePersonCount = 0
    var lastDeletePersonHash: String?
    var shouldFail = false
    func revoke(_ a: Account) async throws {
        if shouldFail { throw AccountError.offline }
        revokeCount += 1
    }
    func deletePerson(hash: String) async throws {
        if shouldFail { throw AccountError.offline }
        deletePersonCount += 1
        lastDeletePersonHash = hash
    }
}

private final class FakeIdentitySink: IdentitySink {
    var identifyCount = 0
    var resetCount = 0
    var lastHash: String?
    func identify(_ hash: String) { identifyCount += 1; lastHash = hash }
    func reset() { resetCount += 1 }
}

private final class FakeCredentialStateChecker: CredentialStateChecker {
    var revoked = false
    func isRevoked(_ a: Account) async -> Bool { revoked }
}

/// Optional sign-in with Apple or Google as identity only: no server of ours
/// except a stateless revoke Worker. Pins `AccountStore`'s sign-in, sign-out,
/// delete and pending-delete-retry behaviour against fakes for every protocol.
@MainActor
struct AccountStoreTests {

    private func makeStore(keychain: FakeAccountKeychain = FakeAccountKeychain(),
                            revoker: FakeAccountRevoker = FakeAccountRevoker(),
                            sink: FakeIdentitySink = FakeIdentitySink(),
                            checker: FakeCredentialStateChecker = FakeCredentialStateChecker(),
                            defaults: UserDefaults,
                            salt: String = "test-salt") -> AccountStore {
        AccountStore(keychain: keychain, revoker: revoker, sink: sink, checker: checker,
                     defaults: defaults, salt: salt)
    }

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func signInWithFakeAppleProviderSavesAccountAndIdentifiesOnce() async throws {
        let keychain = FakeAccountKeychain()
        let sink = FakeIdentitySink()
        let defaults = freshDefaults("account-signin")
        let store = makeStore(keychain: keychain, sink: sink, defaults: defaults)
        let account = Account(provider: .apple, subject: "A", email: nil)
        let provider = FakeIdentityProvider(.success(account))

        try await store.signIn(with: provider)

        #expect(store.current?.subject == "A")
        #expect(keychain.stored == account)
        #expect(sink.identifyCount == 1)
        #expect(sink.lastHash == AccountStore.hash(salt: "test-salt", provider: .apple, subject: "A"))
    }

    @Test func hashIsSixtyFourLowercaseHexAndHidesTheSubjectAndEmail() {
        let hash = AccountStore.hash(salt: "test-salt", provider: .apple, subject: "A")
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(!hash.contains("A"))
        #expect(!hash.contains("@"))
    }

    @Test func hashIsStableAcrossInstallsWithTheSameSalt() {
        let hash1 = AccountStore.hash(salt: "same-salt", provider: .apple, subject: "A")
        let hash2 = AccountStore.hash(salt: "same-salt", provider: .apple, subject: "A")
        #expect(hash1 == hash2)
    }

    @Test func hashDiffersByProvider() {
        let appleHash = AccountStore.hash(salt: "same-salt", provider: .apple, subject: "A")
        let googleHash = AccountStore.hash(salt: "same-salt", provider: .google, subject: "A")
        #expect(appleHash != googleHash)
    }

    @Test func signOutClearsAccountAndKeychainAndResetsSinkOnce() async throws {
        let keychain = FakeAccountKeychain()
        let sink = FakeIdentitySink()
        let defaults = freshDefaults("account-signout")
        let store = makeStore(keychain: keychain, sink: sink, defaults: defaults)
        let provider = FakeIdentityProvider(.success(Account(provider: .apple, subject: "A", email: nil)))
        try await store.signIn(with: provider)

        store.signOut()

        #expect(store.current == nil)
        #expect(keychain.stored == nil)
        #expect(sink.resetCount == 1)
    }

    @Test func signOutLeavesPurchaseCountUnchanged() async throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let purchase = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000), merchant: "Woolworths",
                                         amount: 10, currency: "AUD", card: .other, source: .email, platform: nil)
        _ = try TransactionLogger.log(purchase, in: context)
        let before = try context.fetch(FetchDescriptor<Transaction>()).count

        let defaults = freshDefaults("account-signout-purchases")
        let store = makeStore(defaults: defaults)
        let provider = FakeIdentityProvider(.success(Account(provider: .apple, subject: "A", email: nil)))
        try await store.signIn(with: provider)
        store.signOut()

        let after = try context.fetch(FetchDescriptor<Transaction>()).count
        #expect(after == before)
    }

    @Test func deleteAccountWithSucceedingRevokerClearsEverythingAndCallsEachOnce() async throws {
        let keychain = FakeAccountKeychain()
        let revoker = FakeAccountRevoker()
        let sink = FakeIdentitySink()
        let defaults = freshDefaults("account-delete-success")
        let store = makeStore(keychain: keychain, revoker: revoker, sink: sink, defaults: defaults)
        let account = Account(provider: .apple, subject: "A", email: nil)
        try await store.signIn(with: FakeIdentityProvider(.success(account)))
        let expectedHash = AccountStore.hash(salt: "test-salt", provider: .apple, subject: "A")

        await store.deleteAccount()

        #expect(keychain.stored == nil)
        #expect(sink.resetCount == 1)
        #expect(revoker.revokeCount == 1)
        #expect(revoker.deletePersonCount == 1)
        #expect(revoker.lastDeletePersonHash == expectedHash)
        #expect((defaults.array(forKey: "accountPendingDeletes") ?? []).isEmpty)
    }

    @Test func deleteAccountWithOfflineRevokerQueuesBothJobsAndRetriesAtNextLaunch() async throws {
        let keychain = FakeAccountKeychain()
        let revoker = FakeAccountRevoker()
        revoker.shouldFail = true
        let sink = FakeIdentitySink()
        let defaults = freshDefaults("account-delete-offline")
        let store = makeStore(keychain: keychain, revoker: revoker, sink: sink, defaults: defaults)
        let account = Account(provider: .apple, subject: "A", email: nil)
        try await store.signIn(with: FakeIdentityProvider(.success(account)))

        await store.deleteAccount()

        #expect(store.current == nil)
        #expect(keychain.stored == nil)
        let queued = defaults.array(forKey: "accountPendingDeletes") as? [String] ?? []
        #expect(queued.count == 2)

        revoker.shouldFail = false
        let store2 = makeStore(keychain: keychain, revoker: revoker, sink: sink, defaults: defaults)
        await store2.retryPendingDeletes()

        #expect(revoker.revokeCount == 1)
        #expect(revoker.deletePersonCount == 1)
        #expect((defaults.array(forKey: "accountPendingDeletes") ?? []).isEmpty)
    }

    @Test func checkCredentialAtLaunchSignsOutQuietlyWhenRevoked() async throws {
        let keychain = FakeAccountKeychain()
        let sink = FakeIdentitySink()
        let checker = FakeCredentialStateChecker()
        checker.revoked = true
        let defaults = freshDefaults("account-credential-revoked")
        let store = makeStore(keychain: keychain, sink: sink, checker: checker, defaults: defaults)
        try await store.signIn(with: FakeIdentityProvider(.success(Account(provider: .apple, subject: "A", email: nil))))

        await store.checkCredentialAtLaunch()

        #expect(store.current == nil)
        #expect(keychain.stored == nil)
        #expect(sink.resetCount == 1)
    }

    @Test func cancelledProviderLeavesNoAccountAndNeverIdentifies() async throws {
        let keychain = FakeAccountKeychain()
        let sink = FakeIdentitySink()
        let defaults = freshDefaults("account-cancelled")
        let store = makeStore(keychain: keychain, sink: sink, defaults: defaults)
        let provider = FakeIdentityProvider(.failure(AccountError.cancelled))

        await #expect(throws: AccountError.cancelled) {
            try await store.signIn(with: provider)
        }

        #expect(store.current == nil)
        #expect(keychain.stored == nil)
        #expect(sink.identifyCount == 0)
    }
}
