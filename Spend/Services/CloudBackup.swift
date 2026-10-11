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
    /// Which iCloud account the store is signed in to, as an opaque id. Nil
    /// when it can't be told (offline, no account). Optional: a fake leaves
    /// it out, and then no account switch is ever seen.
    func accountID() async -> String?
}

extension CloudBackupStore {
    func accountID() async -> String? { nil }
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
    /// iCloud holds a backup newer than anything this phone backed up or
    /// restored: another iPhone wrote it. Backing up now would write over it.
    case newerInCloud

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
            // Not "trying again": only an automatic backup tries again by
            // itself. A restore or a delete is the person's to tap again.
            "iCloud is busy. Try again in \(Int(seconds.rounded(.up))) s."
        case .notSignedIn:
            "Not signed in to iCloud. Sign in from the Settings app to back up."
        case .restoreFirst:
            "There's already a backup in iCloud. Restore it first, so it isn't written over."
        case .newerInCloud:
            "iCloud has a newer backup, made on another iPhone. Restore it first (Add What's Missing), so it isn't written over."
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
    /// The iCloud account (`CloudBackupStore.accountID`) this iPhone last
    /// backed up to or restored from. Another one now means the account was
    /// switched: what this iPhone knew about the copy is about the old one.
    nonisolated static let accountKey = "cloudBackupAccount"
    /// The iCloud account a pending delete was meant for, or `unknownAccount`.
    nonisolated static let deleteAccountKey = "cloudBackupDeleteAccount"
    /// A delete queued with no account known (offline, and this iPhone had
    /// never noted one). It only deletes from the account this iPhone last
    /// backed up to (`pendingDeleteMatches`).
    nonisolated static let unknownAccount = "unknown"
    /// This iPhone wrote the iCloud copy (a backup, not only a restore), so
    /// Delete All Data deletes it even with the switch off. Cleared when the
    /// copy is deleted.
    nonisolated static let backedUpHereKey = "cloudBackupFromThisPhone"
    /// The store changed since the last backup that reached iCloud: the backup
    /// is behind. Kept on disk so it survives a relaunch while offline.
    nonisolated static let behindKey = "cloudBackupBehind"
    /// Automatic backups run at most this often.
    nonisolated static let minimumGap: TimeInterval = 10 * 60
    /// How much newer iCloud's copy may look than this phone's last backup
    /// before it counts as another phone's (dates round-trip through CloudKit).
    nonisolated static let clockSlack: TimeInterval = 2
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
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if oldValue, !isEnabled { stopWaitingBackups() }
        }
    }
    private(set) var lastBackup: Date? {
        didSet { defaults.set(lastBackup, forKey: Self.lastKey) }
    }
    private(set) var status: Status = .idle
    /// Rows the last restore left out for a date that can't be right, so the
    /// restore message can say so.
    private(set) var lastRestoreBadDates = 0
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
    /// When iCloud's rate-limit wait ends. A `.paused(.rateLimited)` is over
    /// at this moment, whatever set it (a backup, a restore or a delete).
    @ObservationIgnored private var pausedUntil: Date?
    /// The launch's one try at a pending delete has run (`retryPendingDeleteAtLaunch`).
    @ObservationIgnored private var triedPendingDeleteThisLaunch = false
    /// `accountKey`, kept in memory too: Delete All Data wipes the defaults
    /// before it queues its delete, and the delete must still know the account.
    @ObservationIgnored private var knownAccount: String?
    /// A failed pending delete was reported this launch: once is enough.
    @ObservationIgnored private var reportedPendingDeleteFailure = false
    /// The store changed since the last backup, so a catch-up is worth it.
    private var dirty: Bool {
        get { defaults.bool(forKey: Self.behindKey) }
        set { defaults.set(newValue, forKey: Self.behindKey); behind = newValue }
    }
    /// `dirty`, readable by a screen (and redrawn when it changes).
    private(set) var behind = false
    /// Goes up each time Delete All Data starts. A backup notes it before it
    /// uploads; if it moved by the end, the upload holds wiped data and must
    /// not stay in iCloud.
    @ObservationIgnored private var resets = 0
    /// Counts saves seen by `scheduleBackup`. A backup notes it when it takes
    /// its snapshot; if it moved by the end of the upload, a purchase saved
    /// mid-upload isn't in this copy, so another backup is scheduled. (The
    /// save's own scheduled backup found this one busy and gave up.)
    @ObservationIgnored private var changes = 0

    init(store: CloudBackupStore, keys: BackupKeyStore,
         defaults: UserDefaults = .standard, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.keys = keys
        self.defaults = defaults
        self.clock = clock
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        lastBackup = defaults.object(forKey: Self.lastKey) as? Date
        behind = defaults.bool(forKey: Self.behindKey)
        knownAccount = defaults.string(forKey: Self.accountKey)
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
        if case .paused(let reason) = status {
            // iCloud's wait is over: the pause is too.
            guard case .rateLimited = reason, let until = pausedUntil, clock() >= until else { return }
            status = .idle
        }
        let now = clock()
        let since = [lastBackup, lastAttempt].compactMap { $0 }.map { now.timeIntervalSince($0) }.min()
        if let since, since < Self.minimumGap {
            scheduleCatchUp(in: Self.minimumGap - since, from: context)
            return
        }
        lastAttempt = now
        try? await backUp(from: context, automatic: true)
    }

    /// The switch went off: no backup that was only waiting (the debounce
    /// after a save, the ten-minute catch-up, iCloud's rate-limit wait) may
    /// run afterwards. A rate-limit pause ends with its wait, so a later
    /// switch-on is not blocked by it.
    private func stopWaitingBackups() {
        pending?.cancel()
        catchUp?.cancel()
        retry?.cancel()
        if case .paused(.rateLimited) = status { status = .idle }
    }

    /// Waits for the store to go quiet, then backs up if due. Called on
    /// every save of the main context, so a statement import
    /// ends in one backup, not one per purchase.
    func scheduleBackup(from context: ModelContext) {
        guard isEnabled else { return }
        dirty = true
        changes += 1
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
        let resetsAtStart = resets
        // The snapshot below is taken with no wait before it, so every save
        // counted after this line is missing from it.
        let changesAtSnapshot = changes
        status = .backingUp
        do {
            let snapshot = try Backup.snapshot(in: context, defaults: defaults)
            if automatic, snapshot.transactions.isEmpty {
                status = .idle
                dirty = false
                return
            }
            let key = try await usableKey()
            // JSON, then AES, off the main thread: a long history takes a moment.
            let keyData = key.withUnsafeBytes { Data($0) }
            let blob = try await Task.detached(priority: .utility) {
                try Self.encrypt(try Backup.encode(snapshot), with: SymmetricKey(data: keyData))
            }.value
            // Delete All Data started while this was being made: don't upload.
            guard resets == resetsAtStart else {
                status = .idle
                return
            }
            // The switch went off while this automatic backup was being made.
            if automatic, !isEnabled {
                status = .idle
                return
            }
            let now = clock()
            try await store.save(blob, modified: now)
            // Asked before the check below: no wait may come between it and
            // the pending delete being cleared.
            let account = await store.accountID()
            // Delete All Data started while this was uploading, and its delete
            // may already have run: take this copy out again (or leave the
            // delete pending for the next launch). Nothing here counts as
            // backed up.
            guard resets == resetsAtStart else {
                queuePendingDelete()
                await retryPendingDelete()
                status = .idle
                return
            }
            // This upload took the place of the copy an earlier Delete All
            // Data was still waiting to delete: nothing is left to delete,
            // and the next launch must not delete this new one. Not when that
            // copy is in another iCloud account: it is still there.
            if pendingDeleteMatches(account) { clearPendingDelete() }
            defaults.set(true, forKey: Self.backedUpHereKey)
            lastBackup = now
            dirty = false
            status = .idle
            // Saved while this was uploading: back that up too.
            if changes != changesAtSnapshot { scheduleBackup(from: context) }
        } catch {
            // A backup of wiped data failed: nothing to pause or retry.
            guard resets == resetsAtStart else {
                status = .idle
                throw error
            }
            fail(with: error, context: context)
            throw error
        }
    }

    /// The key to encrypt with. Two rules keep an old backup safe:
    /// a phone that has never backed up or restored must restore first if
    /// iCloud holds a backup; and a new key is only ever made when iCloud is
    /// empty, since a new key would lock the old backup for ever.
    private func usableKey() async throws -> SymmetricKey {
        await noticeAccountSwitch()
        let existing = try keys.load()
        // Delete All Data wipes the saved date but not this one in memory: a
        // phone that was wiped has never backed up, whatever it remembers.
        if lastBackup != nil, defaults.object(forKey: Self.lastKey) == nil { lastBackup = nil }
        if lastBackup == nil || existing == nil {
            if try await store.fetch() != nil {
                throw lastBackup == nil ? CloudBackupError.restoreFirst : CloudBackupError.noKey
            }
        } else if let last = lastBackup {
            // An unreadable copy is replaced by the backup, as before.
            let record: (blob: Data, modified: Date)?
            do { record = try await store.fetch() } catch CloudBackupError.corrupt { record = nil }
            if let record, record.modified > last.addingTimeInterval(Self.clockSlack) {
                // Another iPhone backed up after this one last did: a backup
                // now would write over its newer purchases.
                throw CloudBackupError.newerInCloud
            }
        }
        if let existing { return existing }
        let key = SymmetricKey(size: .bits256)
        try keys.save(key)
        return key
    }

    /// The phone is back online: try the backup that is behind, now. Skips
    /// the "tried a moment ago" pause (the last try failed because there was
    /// no connection), keeps the ten-minute cap after a backup that worked.
    func resumeAfterReconnect(from context: ModelContext) async {
        guard isEnabled, dirty else { return }
        lastAttempt = nil
        if case .failed = status { status = .idle }
        await backUpIfDue(from: context)
    }

    /// What the status line under the switch says. Offline with a backup
    /// waiting, it says so plainly instead of a failed upload.
    nonisolated static func statusLine(status: Status, isEnabled: Bool, isBehind: Bool, isOnline: Bool) -> String? {
        if isEnabled, isBehind, !isOnline, !status.isBusy { return waitingMessage }
        return status.message
    }

    nonisolated static let waitingMessage = "Waiting for a connection. Sortd will back up when you're online."

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
        lastRestoreBadDates = 0
        do {
            await noticeAccountSwitch()
            guard let record = try await store.fetch() else {
                status = .idle
                return nil
            }
            let plain = try await decrypted(record.blob)
            let result = try Backup.restore(plain, mode: mode, into: context, defaults: defaults)
            lastRestoreBadDates = result.badDates
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
        try await deleteCopy(showingFailure: true)
    }

    /// `showingFailure` false: the launch retry, which nobody is watching.
    /// A failure leaves the status line alone and is reported by the caller.
    private func deleteCopy(showingFailure: Bool) async throws {
        // A backup still uploading was started before this delete: it must
        // not put the copy back (it takes itself out again when it lands).
        resets += 1
        do {
            try await store.delete()
            defaults.removeObject(forKey: Self.backedUpHereKey)
            lastBackup = nil
            status = .idle
        } catch {
            if showingFailure { fail(with: error, context: nil) }
            throw error
        }
    }

    /// Delete All Data: the switch goes off and the iCloud copy goes too
    /// (called when `deletesCloudCopyOnReset`, switch on or not). If
    /// iCloud can't be reached now, the delete is remembered and
    /// `retryPendingDelete` finishes it at the next launch.
    func deleteCloudCopyAfterReset() async {
        // Any backup already running, even mid-upload, is now stale.
        resets += 1
        isEnabled = false
        pending?.cancel()
        catchUp?.cancel()
        retry?.cancel()
        queuePendingDelete()
        // Which iCloud account the copy to delete is in, so a later retry
        // never deletes another account's backup after a switch.
        if let account = await store.accountID() { defaults.set(account, forKey: Self.deleteAccountKey) }
        await retryPendingDelete()
    }

    private func queuePendingDelete() {
        defaults.set(true, forKey: Self.deletePendingKey)
        defaults.set(clock(), forKey: Self.deleteQueuedAtKey)
        let account = defaults.string(forKey: Self.accountKey) ?? knownAccount ?? Self.unknownAccount
        defaults.set(account, forKey: Self.deleteAccountKey)
    }

    /// Whether the pending delete is for the iCloud account signed in now.
    /// No account to compare (a store that can't tell, or a delete queued by
    /// an older build): yes, as before. Queued with the account unknown: only
    /// the account this iPhone last backed up to.
    private func pendingDeleteMatches(_ current: String?) -> Bool {
        guard let current, let meant = defaults.string(forKey: Self.deleteAccountKey) else { return true }
        if meant == Self.unknownAccount {
            return backedUpFromThisPhone && defaults.string(forKey: Self.accountKey) == current
        }
        return meant == current
    }

    private func clearPendingDelete() {
        defaults.removeObject(forKey: Self.deletePendingKey)
        defaults.removeObject(forKey: Self.deleteQueuedAtKey)
        defaults.removeObject(forKey: Self.deleteAccountKey)
    }

    /// iCloud is signed in to another account than the one this iPhone last
    /// backed up to or restored from. Everything known about "the copy" was
    /// about the old account's: this iPhone has never backed up here, so
    /// the restore-first guard applies before anything is written over the
    /// new account's own backup, and Delete All leaves that backup alone.
    private func noticeAccountSwitch() async {
        guard let account = await store.accountID() else { return }
        if let known = defaults.string(forKey: Self.accountKey), known != account {
            lastBackup = nil
            defaults.removeObject(forKey: Self.backedUpHereKey)
        }
        defaults.set(account, forKey: Self.accountKey)
        knownAccount = account
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

    /// The app came to the front: finish a pending delete, at most one try
    /// per launch. It runs on every scene-active, and a phone with no
    /// iCloud account or no network failed it every time (183 reports from
    /// one phone in two days, 10 Oct 2026). A delete left pending is tried
    /// again at the next launch.
    func retryPendingDeleteAtLaunch() async {
        guard !triedPendingDeleteThisLaunch else { return }
        triedPendingDeleteThisLaunch = true
        await retryPendingDelete()
    }

    func retryPendingDelete() async {
        guard isDeletePending else { return }
        do {
            // Another iCloud account now: the copy Delete All meant is out of
            // reach, and this account's backup is not it. Still pending: it
            // goes when that account is back.
            guard pendingDeleteMatches(await store.accountID()) else { return }
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
            try await deleteCopy(showingFailure: false)
            clearPendingDelete()
        } catch {
            // Still pending; the next launch tries again. No iCloud account or
            // no network is expected, not a fault; anything else once a launch.
            guard !Self.isExpected(error), !reportedPendingDeleteFailure else { return }
            reportedPendingDeleteFailure = true
            ErrorLog.report(error, where: "CloudBackup.retryPendingDelete", defaults: defaults)
        }
    }

    /// A failure that says nothing is wrong with Sortd: no network, no
    /// iCloud account (or not now), or no iCloud in this build.
    nonisolated static func isExpected(_ error: Error) -> Bool {
        if Connectivity.isNetworkDown(error) { return true }
        if error is CloudKitBackupStore.Unavailable { return true }
        if let known = error as? CloudBackupError { return known == .notSignedIn }
        if let failure = error as? CloudKitBackupStore.Failure {
            return failure.code == .accountTemporarilyUnavailable || failure.code == .notAuthenticated
        }
        return false
    }

    // MARK: - Failure

    private func fail(with error: Error, context: ModelContext?) {
        retry?.cancel()
        guard let known = error as? CloudBackupError else {
            // No connection or no iCloud account is expected, not a fault:
            // the backup is still behind and `resumeAfterReconnect` carries on.
            if !Self.isExpected(error) { ErrorLog.report(error, where: "CloudBackup.backUp", defaults: defaults) }
            status = .failed(error.localizedDescription)
            return
        }
        status = .paused(known)
        guard case .rateLimited(let seconds) = known else { return }
        pausedUntil = clock().addingTimeInterval(max(seconds, 1))
        retry = Task { [weak self] in
            guard let self else { return }
            try? await self.sleep(.seconds(max(seconds, 1)))
            guard !Task.isCancelled, self.status == .paused(known) else { return }
            self.status = .idle
            // iCloud said when to come back: try the backup once more. A
            // restore or a delete has nothing to retry with; its pause just
            // ends, so automatic backups are not held up for the session.
            guard let context, self.isEnabled else { return }
            self.lastAttempt = nil
            try? await self.backUp(from: context, automatic: true)
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
