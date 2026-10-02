import Foundation
import CryptoKit
import SwiftData
import UIKit

// The iCloud feature ships behind the SORTD_ICLOUD compile flag, which is off
// in both configs until the paid developer enrolment clears and the iCloud
// capability is on the App ID. Without it, an unsigned or free-team build has
// no iCloud entitlement and `CKContainer.default()` would abort at run time,
// so the Settings section, the save hook, the scene-phase backup and the
// Delete All Data step are all compiled out. To turn it on: Xcode > Spend
// target > Build Settings > Active Compilation Conditions > add SORTD_ICLOUD
// to Debug and Release. `CloudBackup` itself always compiles, so its tests
// (fakes only) run everywhere.

/// Where the encrypted backup blob lives. The real one is a CloudKit record in
/// the user's private database (`CloudKitBackupStore`); tests use a fake.
@MainActor
protocol CloudBackupStore: AnyObject {
    func save(_ blob: Data, modified: Date) async throws
    func fetch() async throws -> (blob: Data, modified: Date)?
    func delete() async throws
}

/// Where the encryption key lives. The real one is a synchronizable Keychain
/// item (`KeychainBackupKeyStore`), so iCloud Keychain carries it to the next
/// phone; tests use a fake.
@MainActor
protocol BackupKeyStore: AnyObject {
    func load() throws -> SymmetricKey?
    func save(_ key: SymmetricKey) throws
    func delete() throws
}

enum CloudBackupError: Error, Equatable, LocalizedError {
    /// A backup exists but this phone has no key for it (iCloud Keychain
    /// hasn't brought it over yet, or it was lost). A new key is never made
    /// while a backup exists: that would lock the old one for ever.
    case noKey
    /// Not a Sortd backup, or the key doesn't open it.
    case corrupt
    case quotaExceeded
    case rateLimited(retryAfter: TimeInterval)
    case notSignedIn
    /// This phone has never backed up or restored, and iCloud already holds
    /// a backup (from the old phone). Backing up now would write over it.
    case restoreFirst

    /// Plain words for the status line in Settings.
    var errorDescription: String? {
        switch self {
        case .noKey:
            "The backup key hasn't arrived from iCloud Keychain yet. Try again later."
        case .corrupt:
            "The iCloud backup can't be read."
        case .quotaExceeded:
            "iCloud is full. Backup is paused."
        case .rateLimited(let seconds):
            "Trying again in \(Int(seconds.rounded(.up))) s"
        case .notSignedIn:
            "Not signed in to iCloud. Sign in from the Settings app to back up."
        case .restoreFirst:
            "There's already a backup in iCloud. Restore it first, so it isn't written over."
        }
    }
}

/// An encrypted copy of the existing backup file (`Backup.Snapshot`) in the
/// user's own iCloud, so losing the phone doesn't lose every purchase.
///
/// The blob is AES-GCM encrypted on the phone. The key lives in iCloud
/// Keychain, never in the record, so neither Apple nor we can read it. Restore
/// reuses `Backup.restore`, the same path the file import takes.
@MainActor
@Observable
final class CloudBackup {
    static let shared = CloudBackup(store: CloudKitBackupStore(), keys: KeychainBackupKeyStore())

    nonisolated static let enabledKey = "cloudBackupEnabled"
    nonisolated static let lastKey = "cloudBackupLast"
    /// Delete All Data could not reach iCloud: delete the copy at the next launch.
    nonisolated static let deletePendingKey = "cloudBackupDeletePending"
    /// When that delete was queued. The retry leaves alone a backup made
    /// after this moment: it is a new, wanted one, not the copy that Delete
    /// All Data meant to remove.
    nonisolated static let deleteQueuedAtKey = "cloudBackupDeleteQueuedAt"
    /// This iPhone wrote the iCloud copy (a backup, not only a restore), so
    /// Delete All Data deletes it even with the switch off. Cleared when the
    /// copy is deleted.
    nonisolated static let backedUpHereKey = "cloudBackupFromThisPhone"
    /// Automatic backups run at most this often.
    nonisolated static let minimumGap: TimeInterval = 10 * 60
    /// A save on the store waits this long for more saves before backing up.
    nonisolated static let debounce: Duration = .seconds(5)

    enum Status: Equatable {
        case idle, backingUp, restoring, paused(CloudBackupError), failed(String)

        /// What to say under the switch. Nil when there's nothing to say.
        var message: String? {
            switch self {
            case .idle: nil
            case .backingUp: "Backing up…"
            case .restoring: "Restoring…"
            case .paused(let error): error.errorDescription
            case .failed(let reason): reason
            }
        }

        var isBusy: Bool { self == .backingUp || self == .restoring }
    }

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }
    private(set) var lastBackup: Date? {
        didSet { defaults.set(lastBackup, forKey: Self.lastKey) }
    }
    private(set) var status: Status = .idle
    var isDeletePending: Bool { defaults.bool(forKey: Self.deletePendingKey) }
    /// See `backedUpHereKey`.
    var backedUpFromThisPhone: Bool { defaults.bool(forKey: Self.backedUpHereKey) }

    @ObservationIgnored private let store: CloudBackupStore
    @ObservationIgnored private let keys: BackupKeyStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    /// Every wait goes through here so tests can stand in for the clock:
    /// the debounce after a save, the catch-up at the end of the ten-minute
    /// cap, and the wait iCloud asks for after a rate limit.
    @ObservationIgnored var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// The debounce after a save. Readable so a test can await it.
    @ObservationIgnored private(set) var pending: Task<Void, Never>?
    /// A backup skipped by the ten-minute cap, to run when the cap ends.
    @ObservationIgnored private(set) var catchUp: Task<Void, Never>?
    /// The wait iCloud asked for after a rate limit, then one more try.
    @ObservationIgnored private(set) var retry: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// The last automatic try, pass or fail, so a failing store isn't hit on
    /// every save.
    @ObservationIgnored private var lastAttempt: Date?
    /// The store changed since the last backup, so a catch-up is worth it.
    @ObservationIgnored private var dirty = false

    init(store: CloudBackupStore, keys: BackupKeyStore,
         defaults: UserDefaults = .standard, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.keys = keys
        self.defaults = defaults
        self.clock = clock
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        lastBackup = defaults.object(forKey: Self.lastKey) as? Date
    }

    // MARK: - Backing up

    /// Encrypts a fresh snapshot and saves it, making the key first if this
    /// phone has none and iCloud is empty. Throws what went wrong and leaves
    /// `status` saying so.
    func backUpNow(from context: ModelContext) async throws {
        try await backUp(from: context, automatic: false)
    }

    /// The automatic path: only when the switch is on, not while paused or
    /// busy, at most once per ten minutes (a skipped one runs when the cap
    /// ends), and never an empty snapshot.
    func backUpIfDue(from context: ModelContext) async {
        guard isEnabled, !status.isBusy else { return }
        if case .paused = status { return }
        let now = clock()
        let since = [lastBackup, lastAttempt].compactMap { $0 }.map { now.timeIntervalSince($0) }.min()
        if let since, since < Self.minimumGap {
            scheduleCatchUp(in: Self.minimumGap - since, from: context)
            return
        }
        lastAttempt = now
        try? await backUp(from: context, automatic: true)
    }

    /// Waits for the store to go quiet, then backs up if due. Called on
    /// every save of the main context, so a Gmail sync or a statement import
    /// ends in one backup, not one per purchase.
    func scheduleBackup(from context: ModelContext) {
        guard isEnabled else { return }
        dirty = true
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await self.sleep(Self.debounce)
            guard !Task.isCancelled else { return }
            await self.backUpIfDue(from: context)
        }
    }

    private func scheduleCatchUp(in seconds: TimeInterval, from context: ModelContext) {
        guard catchUp == nil else { return }
        catchUp = Task { [weak self] in
            guard let self else { return }
            defer { self.catchUp = nil }
            try? await self.sleep(.seconds(max(seconds, 1)))
            guard !Task.isCancelled else { return }
            // Nothing changed since the last backup: nothing to catch up.
            guard self.dirty else { return }
            await self.backUpIfDue(from: context)
        }
    }

    /// Backs up after every save to the store (a logged tap, an import, an
    /// edit), the same hook `WidgetBridge` uses, so CloudKit never sits
    /// inside `TransactionLogger`. Call once at launch.
    static func watchSaves() {
        NotificationCenter.default.addObserver(forName: ModelContext.didSave,
                                               object: SpendStore.container.mainContext, queue: .main) { _ in
            MainActor.assumeIsolated { shared.scheduleBackup(from: SpendStore.container.mainContext) }
        }
    }

    /// On the way to the background: back up now if due, with the few extra
    /// seconds iOS grants so the upload isn't cut off mid-way.
    func backUpOnBackground(from context: ModelContext) {
        guard isEnabled, backgroundTask == .invalid else { return }
        pending?.cancel()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "cloud-backup") {
            MainActor.assumeIsolated { self.endBackgroundTask() }
        }
        Task {
            await backUpIfDue(from: context)
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func backUp(from context: ModelContext, automatic: Bool) async throws {
        status = .backingUp
        do {
            let snapshot = try Backup.snapshot(in: context, defaults: defaults)
            if automatic, snapshot.transactions.isEmpty {
                status = .idle
                return
            }
            let key = try await usableKey()
            // JSON, then AES, off the main thread: a long history takes a moment.
            let keyData = key.withUnsafeBytes { Data($0) }
            let blob = try await Task.detached(priority: .utility) {
                try Self.encrypt(try Backup.encode(snapshot), with: SymmetricKey(data: keyData))
            }.value
            let now = clock()
            try await store.save(blob, modified: now)
            // This upload took the place of the copy an earlier Delete All
            // Data was still waiting to delete: nothing is left to delete,
            // and the next launch must not delete this new one.
            clearPendingDelete()
            defaults.set(true, forKey: Self.backedUpHereKey)
            lastBackup = now
            dirty = false
            status = .idle
        } catch {
            fail(with: error, context: context)
            throw error
        }
    }

    /// The key to encrypt with. Two rules keep an old backup safe:
    /// a phone that has never backed up or restored must restore first if
    /// iCloud holds a backup; and a new key is only ever made when iCloud is
    /// empty, since a new key would lock the old backup for ever.
    private func usableKey() async throws -> SymmetricKey {
        let existing = try keys.load()
        if lastBackup == nil || existing == nil {
            if try await store.fetch() != nil {
                throw lastBackup == nil ? CloudBackupError.restoreFirst : CloudBackupError.noKey
            }
        }
        if let existing { return existing }
        let key = SymmetricKey(size: .bits256)
        try keys.save(key)
        return key
    }

    // MARK: - Restoring

    /// Puts the iCloud copy back through `Backup.restore`. Returns how many
    /// purchases were added; 0 when there is no backup yet.
    func restore(into context: ModelContext, mode: Backup.Mode) async throws -> Int {
        try await restoreIfPresent(into: context, mode: mode) ?? 0
    }

    /// Like `restore`, but nil when iCloud has no backup, so the screen can
    /// say so without a second download.
    func restoreIfPresent(into context: ModelContext, mode: Backup.Mode) async throws -> Int? {
        status = .restoring
        do {
            guard let record = try await store.fetch() else {
                status = .idle
                return nil
            }
            let plain = try await decrypted(record.blob)
            let result = try Backup.restore(plain, mode: mode, into: context, defaults: defaults)
            // This phone now holds what iCloud holds: backups may proceed.
            lastBackup = record.modified
            status = .idle
            return result.added
        } catch {
            fail(with: error, context: nil)
            throw error
        }
    }

    /// What the iCloud copy holds, for the Replace warning. Nil when there
    /// is no backup.
    func contents() async throws -> Backup.Contents? {
        guard let record = try await store.fetch() else { return nil }
        return Backup.contents(of: try await decrypted(record.blob))
    }

    private func decrypted(_ blob: Data) async throws -> Data {
        guard let key = try keys.load() else { throw CloudBackupError.noKey }
        let keyData = key.withUnsafeBytes { Data($0) }
        return try await Task.detached(priority: .userInitiated) {
            try Self.decrypt(blob, with: SymmetricKey(data: keyData))
        }.value
    }

    /// The Replace confirmation for the iCloud copy: `Backup.replaceWarning`
    /// when the copy could be read, plain words when it couldn't.
    nonisolated static func replaceWarning(contents: Backup.Contents?, purchasesHere: Int) -> (title: String, message: String) {
        guard let contents else {
            return ("Replace this iPhone's data with the iCloud backup?",
                    "Everything on this iPhone will be replaced. This can't be undone.")
        }
        return Backup.replaceWarning(backup: contents, purchasesHere: purchasesHere)
    }

    // MARK: - Deleting

    /// Removes the record from iCloud. The key stays: it is harmless on its
    /// own and the next backup reuses it.
    func deleteCloudCopy() async throws {
        do {
            try await store.delete()
            defaults.removeObject(forKey: Self.backedUpHereKey)
            lastBackup = nil
            status = .idle
        } catch {
            fail(with: error, context: nil)
            throw error
        }
    }

    /// Delete All Data: the switch goes off and the iCloud copy goes too
    /// (called when `deletesCloudCopyOnReset`, switch on or not). If
    /// iCloud can't be reached now, the delete is remembered and
    /// `retryPendingDelete` finishes it at the next launch.
    func deleteCloudCopyAfterReset() async {
        isEnabled = false
        pending?.cancel()
        catchUp?.cancel()
        queuePendingDelete()
        await retryPendingDelete()
    }

    private func queuePendingDelete() {
        defaults.set(true, forKey: Self.deletePendingKey)
        defaults.set(clock(), forKey: Self.deleteQueuedAtKey)
    }

    private func clearPendingDelete() {
        defaults.removeObject(forKey: Self.deletePendingKey)
        defaults.removeObject(forKey: Self.deleteQueuedAtKey)
    }

    /// Whether Delete All Data must delete the iCloud copy: whenever this
    /// iPhone may have written one, whatever the switch says. On; or off but
    /// this iPhone backed up before (a copy kept with "Keep It" when backup
    /// was turned off); or an earlier delete is still pending. A copy that is
    /// already gone deletes as a no-op. Only restored here, never backed up:
    /// that copy is another iPhone's live backup and is left alone.
    nonisolated static func deletesCloudCopyOnReset(switchOn: Bool, backedUpHere: Bool, deletePending: Bool) -> Bool {
        switchOn || backedUpHere || deletePending
    }

    /// Delete All Data, before anything is wiped: whether the iCloud copy
    /// must go too.
    var deletesCloudCopyOnReset: Bool {
        Self.deletesCloudCopyOnReset(switchOn: isEnabled, backedUpHere: backedUpFromThisPhone, deletePending: isDeletePending)
    }

    func retryPendingDelete() async {
        guard isDeletePending else { return }
        do {
            // A copy saved after the delete was queued is a new backup the
            // person wanted (made from this iPhone or another), not the one
            // Delete All Data meant to remove: leave it. A delete queued
            // before this check existed has no time and deletes as before.
            if let queued = defaults.object(forKey: Self.deleteQueuedAtKey) as? Date {
                let record: (blob: Data, modified: Date)?
                do {
                    record = try await store.fetch()
                } catch CloudBackupError.corrupt {
                    record = nil   // unreadable: still delete it
                }
                if let record, record.modified > queued {
                    clearPendingDelete()
                    return
                }
            }
            try await deleteCloudCopy()
            clearPendingDelete()
        } catch {
            // Still pending; the next launch tries again.
        }
    }

    // MARK: - Failure

    private func fail(with error: Error, context: ModelContext?) {
        retry?.cancel()
        guard let known = error as? CloudBackupError else {
            status = .failed(error.localizedDescription)
            return
        }
        status = .paused(known)
        // iCloud said when to come back: wait that long, then try once more.
        if case .rateLimited(let seconds) = known, let context {
            retry = Task { [weak self] in
                guard let self else { return }
                try? await self.sleep(.seconds(max(seconds, 1)))
                guard !Task.isCancelled, self.status == .paused(known) else { return }
                self.status = .idle
                self.lastAttempt = nil
                try? await self.backUp(from: context, automatic: true)
            }
        }
    }

    // MARK: - Encryption

    /// The first bytes of every blob, so a stray file is refused before
    /// decryption is even tried.
    nonisolated static let magic = Data("SBK1".utf8)

    /// `magic` + AES-GCM combined (nonce, ciphertext, tag). A fresh nonce
    /// each time, so two backups of the same data never look alike.
    nonisolated static func encrypt(_ plain: Data, with key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw CloudBackupError.corrupt }
        return magic + combined
    }

    nonisolated static func decrypt(_ blob: Data, with key: SymmetricKey) throws -> Data {
        guard blob.count > magic.count, blob.prefix(magic.count) == magic else {
            throw CloudBackupError.corrupt
        }
        do {
            let box = try AES.GCM.SealedBox(combined: blob.dropFirst(magic.count))
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CloudBackupError.corrupt
        }
    }
}
