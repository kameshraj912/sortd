import Foundation
import CryptoKit
import SwiftData
import UIKit

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
    /// hasn't brought it over yet, or it was lost).
    case noKey
    /// Not a Sortd backup, or the key doesn't open it.
    case corrupt
    case quotaExceeded
    case rateLimited(retryAfter: TimeInterval)
    case notSignedIn

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

    @ObservationIgnored private let store: CloudBackupStore
    @ObservationIgnored private let keys: BackupKeyStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// The last automatic try, pass or fail, so a failing store isn't hit on
    /// every save.
    @ObservationIgnored private var lastAttempt: Date?

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
    /// phone has none. Throws what went wrong and leaves `status` saying so.
    func backUpNow(from context: ModelContext) async throws {
        try await backUp(from: context, automatic: false)
    }

    /// The automatic path: only when the switch is on, not while paused or
    /// busy, at most once per ten minutes, and never an empty snapshot (a new
    /// phone must not write over the backup it is about to restore).
    func backUpIfDue(from context: ModelContext) async {
        guard isEnabled, !status.isBusy else { return }
        if case .paused = status { return }
        let now = clock()
        if let lastBackup, now.timeIntervalSince(lastBackup) < Self.minimumGap { return }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.minimumGap { return }
        lastAttempt = now
        try? await backUp(from: context, automatic: true)
    }

    /// Waits for the store to go quiet, then backs up if due. Called on
    /// every save of the main context, so a Gmail sync or a statement import
    /// ends in one backup, not one per purchase.
    func scheduleBackup(from context: ModelContext) {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await backUpIfDue(from: context)
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
            let key = try keyMakingOneIfNeeded()
            let blob = try Self.encrypt(try Backup.encode(snapshot), with: key)
            let now = clock()
            try await store.save(blob, modified: now)
            lastBackup = now
            status = .idle
        } catch {
            fail(with: error)
            throw error
        }
    }

    private func keyMakingOneIfNeeded() throws -> SymmetricKey {
        if let key = try keys.load() { return key }
        let key = SymmetricKey(size: .bits256)
        try keys.save(key)
        return key
    }

    // MARK: - Restoring

    /// Puts the iCloud copy back through `Backup.restore`. Returns how many
    /// purchases were added; 0 when there is no backup yet.
    func restore(into context: ModelContext, mode: Backup.Mode) async throws -> Int {
        status = .restoring
        do {
            guard let record = try await store.fetch() else {
                status = .idle
                return 0
            }
            guard let key = try keys.load() else { throw CloudBackupError.noKey }
            let plain = try Self.decrypt(record.blob, with: key)
            let result = try Backup.restore(plain, mode: mode, into: context, defaults: defaults)
            status = .idle
            return result.added
        } catch {
            fail(with: error)
            throw error
        }
    }

    /// What the iCloud copy holds, for the Replace warning. Nil when there
    /// is no backup.
    func contents() async throws -> Backup.Contents? {
        guard let record = try await store.fetch() else { return nil }
        guard let key = try keys.load() else { throw CloudBackupError.noKey }
        let plain = try Self.decrypt(record.blob, with: key)
        return Backup.contents(of: plain)
    }

    // MARK: - Deleting

    /// Removes the record from iCloud. The key stays: it is harmless on its
    /// own and the next backup reuses it.
    func deleteCloudCopy() async throws {
        do {
            try await store.delete()
            lastBackup = nil
            status = .idle
        } catch {
            fail(with: error)
            throw error
        }
    }

    // MARK: - Failure

    private func fail(with error: Error) {
        retry?.cancel()
        guard let known = error as? CloudBackupError else {
            status = .failed(error.localizedDescription)
            return
        }
        status = .paused(known)
        // iCloud said when to come back: do, and let the next save try again.
        if case .rateLimited(let seconds) = known {
            retry = Task {
                try? await Task.sleep(for: .seconds(max(seconds, 1)))
                guard !Task.isCancelled, status == .paused(known) else { return }
                status = .idle
                lastAttempt = nil
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
