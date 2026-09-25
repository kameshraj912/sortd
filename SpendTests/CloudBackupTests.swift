import Testing
import SwiftData
import Foundation
import CryptoKit
@testable import Spend

// MARK: - The contract this file pins
//
// `CloudBackup` wraps the existing `Backup.data(in:defaults:)` /
// `Backup.restore(_:mode:into:defaults:)` (see `Spend/Services/Backup.swift`)
// behind two small protocols, so nothing here touches CloudKit or the real
// Keychain:
//
//   protocol CloudBackupStore: AnyObject {
//       func save(_ blob: Data, modified: Date) async throws
//       func fetch() async throws -> (blob: Data, modified: Date)?
//       func delete() async throws
//   }
//   protocol BackupKeyStore: AnyObject {
//       func load() throws -> SymmetricKey?
//       func save(_ key: SymmetricKey) throws
//       func delete() throws
//   }
//   enum CloudBackupError: Error, Equatable {
//       case noKey, corrupt, quotaExceeded, rateLimited(retryAfter: TimeInterval), notSignedIn
//   }
//   @MainActor @Observable final class CloudBackup {
//       // The spec's init has no way to isolate UserDefaults between tests
//       // (`store:`/`keys:`/`clock:` only). Backup.swift's own functions all
//       // take a `defaults:` parameter for exactly this reason, so this file
//       // pins the same shape: `init(store:keys:defaults: UserDefaults = .standard,
//       // clock: () -> Date = { Date() })`. Flag this to Raj if it should
//       // change back to `.standard` only.
//       init(store: CloudBackupStore, keys: BackupKeyStore,
//            defaults: UserDefaults = .standard, clock: @escaping () -> Date = { Date() })
//       var isEnabled: Bool { get set }        // UserDefaults "cloudBackupEnabled", default false
//       private(set) var lastBackup: Date?      // UserDefaults "cloudBackupLast"
//       private(set) var status: Status
//       enum Status: Equatable { case idle, backingUp, restoring, paused(CloudBackupError), failed(String) }
//       func backUpNow(from context: ModelContext) async throws
//       func restore(into context: ModelContext, mode: Backup.Mode) async throws -> Int
//       func deleteCloudCopy() async throws
//       static func encrypt(_ plain: Data, with key: SymmetricKey) throws -> Data
//       static func decrypt(_ blob: Data, with key: SymmetricKey) throws -> Data
//   }
//
// `Backup.Mode` (not `Backup.RestoreMode`) is the real restore-mode enum in
// `Spend/Services/Backup.swift:192`; `Backup.data(in:defaults:)` is the real
// export function (`Backup.swift:162`), and `Backup.restore(_:mode:into:defaults:)`
// returns `Backup.Result` whose `.added` is the row count (`Backup.swift:200,229`).

/// An in-memory stand-in for the CloudKit record. Never touches the network.
final class FakeCloudBackupStore: CloudBackupStore {
    var saved: (blob: Data, modified: Date)?
    var deleteCount = 0
    var saveError: Error?
    var fetchError: Error?

    func save(_ blob: Data, modified: Date) async throws {
        if let e = saveError { throw e }
        saved = (blob, modified)
    }

    func fetch() async throws -> (blob: Data, modified: Date)? {
        if let e = fetchError { throw e }
        return saved
    }

    func delete() async throws {
        deleteCount += 1
        saved = nil
    }
}

/// An in-memory stand-in for iCloud Keychain. Never touches the Keychain.
final class FakeBackupKeyStore: BackupKeyStore {
    var key: SymmetricKey?
    var saveCount = 0
    var deleteCount = 0

    func load() throws -> SymmetricKey? { key }

    func save(_ k: SymmetricKey) throws {
        key = k
        saveCount += 1
    }

    func delete() throws {
        deleteCount += 1
        key = nil
    }
}

/// Encrypted iCloud backup: `CloudBackup.encrypt`/`decrypt`, and the
/// `CloudBackup` object that saves/restores the existing `Backup.Snapshot`
/// format through a fake `CloudBackupStore` and `BackupKeyStore`.
@MainActor
struct CloudBackupTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "cloudbackup-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @discardableResult
    private func log(_ context: ModelContext, _ merchant: String, _ amount: Decimal,
                     minutes: Double) throws -> Transaction {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60),
                                 merchant: merchant, amount: amount, currency: "AUD",
                                 card: .other, source: .email)
        return try TransactionLogger.log(p, in: context).transaction
    }

    private let fixedClock: () -> Date = { Date(timeIntervalSince1970: 1_790_500_000) }

    // MARK: Encrypt / decrypt

    @Test func encryptThenDecryptRoundTripsBytes() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("hello, Sortd".utf8)
        let blob = try CloudBackup.encrypt(plain, with: key)
        let back = try CloudBackup.decrypt(blob, with: key)
        #expect(back == plain)
    }

    @Test func decryptWithTheWrongKeyThrowsCorrupt() throws {
        let right = SymmetricKey(size: .bits256)
        let wrong = SymmetricKey(size: .bits256)
        let blob = try CloudBackup.encrypt(Data("secret".utf8), with: right)
        #expect(throws: CloudBackupError.corrupt) {
            try CloudBackup.decrypt(blob, with: wrong)
        }
    }

    @Test func aBlobWithoutTheMagicPrefixThrowsCorrupt() throws {
        let key = SymmetricKey(size: .bits256)
        let junk = Data("not a Sortd backup at all".utf8)
        #expect(throws: CloudBackupError.corrupt) {
            try CloudBackup.decrypt(junk, with: key)
        }
    }

    @Test func theBlobNeverContainsThePlaintext() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("ZzQuantumMerchant café".utf8)
        let blob = try CloudBackup.encrypt(plain, with: key)
        #expect(blob.range(of: Data("ZzQuantumMerchant".utf8)) == nil)
    }

    @Test func twoEncryptionsOfTheSameDataDiffer() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("same bytes every time".utf8)
        let a = try CloudBackup.encrypt(plain, with: key)
        let b = try CloudBackup.encrypt(plain, with: key)
        #expect(a != b)
    }

    // MARK: backUpNow

    @Test func firstBackUpNowCreatesAKeyWhenNoneExistsAndSavesIt() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let ctx = try store()
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)

        #expect(keys.key == nil)
        try await cloud.backUpNow(from: ctx)
        #expect(keys.key != nil)
        #expect(keys.saveCount == 1)
    }

    @Test func backUpNowWithThreePurchasesSavesABlobThatRestoresToTheSameRows() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let source = try store()
        try log(source, "Woolworths", 58.30, minutes: 0)
        try log(source, "Seven Seeds", 5.50, minutes: 60)
        try log(source, "DBS Orchard", 22.10, minutes: 120)

        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        try await cloud.backUpNow(from: source)

        let saved = try #require(cloudStore.saved)
        let key = try #require(try keys.load())
        let plain = try CloudBackup.decrypt(saved.blob, with: key)

        let dest = try store()
        let result = try Backup.restore(plain, mode: .merge, into: dest, defaults: scratch())
        #expect(result.added == 3)
    }

    @Test func theBlobNeverContainsAMerchantsPlaintext() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let ctx = try store()
        try log(ctx, "ZzQuantumMerchant", 12.00, minutes: 0)

        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        try await cloud.backUpNow(from: ctx)

        let saved = try #require(cloudStore.saved)
        let needle = Data("ZzQuantumMerchant".utf8)
        #expect(saved.blob.range(of: needle) == nil)
    }

    @Test func lastBackupIsSetToTheClockTimeAndPersistedAcrossInstances() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let defaults = scratch()
        let ctx = try store()

        let first = CloudBackup(store: cloudStore, keys: keys, defaults: defaults, clock: fixedClock)
        try await first.backUpNow(from: ctx)
        #expect(first.lastBackup == fixedClock())

        let second = CloudBackup(store: cloudStore, keys: keys, defaults: defaults, clock: fixedClock)
        #expect(second.lastBackup == fixedClock())
    }

    // MARK: restore

    @Test func restoreIntoAnEmptyContextAddsExactlyTheRowsAndReturnsTheCount() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let source = try store()
        try log(source, "Woolworths", 58.30, minutes: 0)
        try log(source, "Coles", 12.00, minutes: 60)

        let backer = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        try await backer.backUpNow(from: source)

        let dest = try store()
        let restorer = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        let added = try await restorer.restore(into: dest, mode: .merge)

        #expect(added == 2)
        #expect(try dest.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    @Test func restoringTwiceAddsNothingTheSecondTime() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let source = try store()
        try log(source, "Woolworths", 58.30, minutes: 0)

        let backer = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        try await backer.backUpNow(from: source)

        let dest = try store()
        let restorer = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        let first = try await restorer.restore(into: dest, mode: .merge)
        let second = try await restorer.restore(into: dest, mode: .merge)

        #expect(first == 1)
        #expect(second == 0)
        #expect(try dest.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    @Test func restoreWhenTheStoreHasNothingReturnsZeroAndDoesNotThrow() async throws {
        let keys = FakeBackupKeyStore()
        keys.key = SymmetricKey(size: .bits256)
        let cloudStore = FakeCloudBackupStore()
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)

        let dest = try store()
        let added = try await cloud.restore(into: dest, mode: .merge)
        #expect(added == 0)
    }

    @Test func restoreWithNoKeyThrowsNoKeyAndStatusIsPaused() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        cloudStore.saved = (Data("whatever".utf8), fixedClock())
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)

        let dest = try store()
        await #expect(throws: CloudBackupError.noKey) {
            try await cloud.restore(into: dest, mode: .merge)
        }
        #expect(cloud.status == .paused(.noKey))
    }

    // MARK: Failure status

    @Test func aStoreThatThrowsQuotaExceededLeavesStatusPausedAndLastBackupUnchanged() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        cloudStore.saveError = CloudBackupError.quotaExceeded
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        let ctx = try store()

        await #expect(throws: CloudBackupError.quotaExceeded) {
            try await cloud.backUpNow(from: ctx)
        }
        #expect(cloud.status == .paused(.quotaExceeded))
        #expect(cloud.lastBackup == nil)
    }

    @Test func aStoreThatThrowsRateLimitedLeavesStatusPausedWithTheRetryTime() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        cloudStore.saveError = CloudBackupError.rateLimited(retryAfter: 30)
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        let ctx = try store()

        await #expect(throws: CloudBackupError.rateLimited(retryAfter: 30)) {
            try await cloud.backUpNow(from: ctx)
        }
        #expect(cloud.status == .paused(.rateLimited(retryAfter: 30)))
    }

    // MARK: isEnabled / delete

    @Test func isEnabledPersists() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let defaults = scratch()

        let first = CloudBackup(store: cloudStore, keys: keys, defaults: defaults, clock: fixedClock)
        #expect(first.isEnabled == false)
        first.isEnabled = true

        let second = CloudBackup(store: cloudStore, keys: keys, defaults: defaults, clock: fixedClock)
        #expect(second.isEnabled == true)
    }

    @Test func turningIsEnabledOffDoesNotDeleteTheCloudCopy() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let ctx = try store()
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)

        cloud.isEnabled = true
        try await cloud.backUpNow(from: ctx)
        cloud.isEnabled = false

        #expect(cloudStore.deleteCount == 0)
        #expect(cloudStore.saved != nil)
    }

    @Test func deleteCloudCopyCallsTheStoresDeleteAndClearsLastBackup() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let ctx = try store()
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)

        try await cloud.backUpNow(from: ctx)
        #expect(cloud.lastBackup != nil)

        try await cloud.deleteCloudCopy()
        #expect(cloudStore.deleteCount == 1)
        #expect(cloud.lastBackup == nil)
    }

    @Test func theKeyStoreIsNeverAskedToDeleteOnBackupOrRestore() async throws {
        let keys = FakeBackupKeyStore()
        let cloudStore = FakeCloudBackupStore()
        let source = try store()
        try log(source, "Woolworths", 58.30, minutes: 0)

        let backer = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        try await backer.backUpNow(from: source)

        let dest = try store()
        _ = try await backer.restore(into: dest, mode: .merge)

        #expect(keys.deleteCount == 0)
    }
}
