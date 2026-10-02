import Testing
import SwiftData
import Foundation
import CryptoKit
@testable import Spend

/// Raj's 28 Sep report: iCloud backup said "backed up"; he chose Settings ›
/// Account › Delete Account and All Data; signed in again; restore said "No
/// backup in iCloud yet". Reading `AccountSettingsView.deleteAccount` and
/// `DataReset.deleteEverything` (Spend/Views/DataControlsView.swift): the
/// "Delete Account and All Data" button (`alsoData: true`) does call
/// `DataReset.deleteEverything`, which deletes the iCloud copy whenever
/// `CloudBackup.deletesCloudCopyOnReset` is true — switch on, "backed up
/// here" before, or an earlier delete still pending. Plain "Delete Account"
/// (`alsoData: false`) returns before `DataReset.deleteEverything` is ever
/// called, so it never touches `CloudBackup` at all. Both facts are already
/// pinned by passing tests in `CloudBackupResetTests.swift`
/// (`aCopyKeptWhenBackupWasTurnedOffIsDeletedByDeleteAll`,
/// `leavesICloudAloneWhenThisIPhoneNeverBackedUp`) and `CloudBackupTests.swift`
/// (`deleteAfterResetTurnsTheSwitchOffAndRemovesTheCloudCopy`), so his report
/// describes "Delete Account and All Data" working exactly as designed and
/// as the alert's own words say ("Your purchases stay unless you also
/// delete all data, on this iPhone and in iCloud.") — not a bug on its own.
///
/// Chasing "does any path delete the iCloud copy without the person
/// choosing a delete-all option" turned up a real one below: a delete that
/// had to wait for the next launch (`deletePendingKey`) does not know the
/// difference between "the iCloud copy I was asked to delete" and "a new
/// backup made since", so it can delete a legitimately re-enabled backup
/// that has nothing to do with the original Delete All Data.
@MainActor
struct FullDataResetRaceTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "fulldata-resetrace-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func logOne(_ context: ModelContext, merchant: String = "Woolworths") throws {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000),
                                 merchant: merchant, amount: 58.30, currency: "AUD",
                                 card: .other, source: .email)
        _ = try TransactionLogger.log(p, in: context)
    }

    private let fixedClock: () -> Date = { Date(timeIntervalSince1970: 1_790_500_000) }

    // MARK: - A stale pending delete outruns a fresh backup

    /// Delete All Data with iCloud unreachable leaves `deletePendingKey` set
    /// so the next launch finishes the job (`aFailedDeleteAfterResetIsRememberedAndRetriedLater`,
    /// already passing). But if, before that next launch, the person turns
    /// backup back on and it succeeds — iCloud came back, or they picked
    /// "Keep It" and kept using the app — the stale flag has no way to tell
    /// that backup apart from the one it was meant to remove, and the next
    /// launch deletes the brand new one too.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a pending iCloud delete from an earlier offline Delete All Data deletes a fresh, unrelated backup made before the next launch"))
    func aStalePendingDeleteDoesNotDeleteABackupMadeAfterItWasQueued() async throws {
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let defaults = scratch()

        // A normal backup, then Delete All Data while offline: the local
        // wipe runs, but the iCloud delete can't reach the network.
        let ctx = try store()
        try logOne(ctx, merchant: "Woolworths")
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: defaults, clock: fixedClock)
        cloud.isEnabled = true
        try await cloud.backUpNow(from: ctx)
        #expect(cloudStore.saved != nil)

        cloudStore.deleteError = CloudBackupError.notSignedIn
        await cloud.deleteCloudCopyAfterReset()
        #expect(cloud.isDeletePending == true)
        #expect(cloudStore.saved != nil)   // the old copy is still there, undeleted

        // Same install, iCloud comes back: the person turns backup on again
        // and logs something new. This is a fresh, wanted backup, made
        // after Delete All Data was already chosen and run.
        cloudStore.deleteError = nil
        let freshCtx = try store()
        try logOne(freshCtx, merchant: "New Purchase After Reset")
        cloud.isEnabled = true
        try await cloud.backUpNow(from: freshCtx)
        #expect(cloudStore.saved != nil)
        let freshModified = cloudStore.saved?.modified

        // Next launch: the still-pending flag from the *earlier* delete
        // fires and removes whatever is in iCloud now, with no check that
        // it's a different backup than the one it was queued to remove.
        let nextLaunch = CloudBackup(store: cloudStore, keys: keys, defaults: defaults, clock: fixedClock)
        #expect(nextLaunch.isDeletePending == true)
        await nextLaunch.retryPendingDelete()

        // A user who re-enabled backup and made a new one has every reason
        // to expect it is still there.
        #expect(cloudStore.saved != nil, "the fresh backup made at \(String(describing: freshModified)) must survive a stale pending delete queued before it existed")
    }

    // MARK: - Delete All Data racing an in-flight backup upload

    /// A `CloudBackupStore` whose `save` can be told to hang, so a test can
    /// hold a backup upload open while another operation runs, the way a
    /// real network write can still be in flight when Delete All Data is
    /// chosen a moment later.
    private final class PausableCloudBackupStore: CloudBackupStore {
        var saved: (blob: Data, modified: Date)?
        var deleteCount = 0
        var holdSave = false
        /// True once a save has started, so a test waits for that instead of a guess.
        var saveStarted = false
        private var parked: CheckedContinuation<Void, Never>?

        func save(_ blob: Data, modified: Date) async throws {
            saveStarted = true
            if holdSave {
                await withCheckedContinuation { self.parked = $0 }
            }
            saved = (blob, modified)
        }

        func fetch() async throws -> (blob: Data, modified: Date)? { saved }

        func delete() async throws {
            deleteCount += 1
            saved = nil
        }

        /// Lets the held save finish, and any save that has not started yet.
        func release() {
            holdSave = false
            parked?.resume()
            parked = nil
        }
    }

    /// "Back Up Now" (or an automatic backup already due) starts uploading,
    /// then before it finishes the person chooses Delete All Data.
    /// `deleteCloudCopyAfterReset` only cancels the debounce and catch-up
    /// tasks; it has no handle on a backup already mid-`save`, so that
    /// upload — built from the data Delete All Data just wiped — finishes
    /// afterwards and puts a purchase back in iCloud that "This can't be
    /// undone" said was gone.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("an in-flight iCloud backup upload finishes after Delete All Data and restores the pre-reset copy"))
    func deleteAllDataDoesNotUndoABackupThatWasAlreadyUploading() async throws {
        let pausable = PausableCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let defaults = scratch()
        let ctx = try store()
        try logOne(ctx, merchant: "Woolworths")
        let cloud = CloudBackup(store: pausable, keys: keys, defaults: defaults, clock: fixedClock)
        cloud.isEnabled = true

        pausable.holdSave = true
        let backupTask = Task { try? await cloud.backUpNow(from: ctx) }
        // Wait until the backup is inside `store.save`, parked there, the way
        // a real network write is still in flight a moment later.
        while !pausable.saveStarted { await Task.yield() }

        // Delete All Data runs while that upload is still parked mid-save.
        await cloud.deleteCloudCopyAfterReset()
        #expect(pausable.saved == nil, "Delete All Data must leave iCloud with nothing, even mid-race")

        // The upload that was already running finishes afterwards.
        pausable.release()
        _ = await backupTask.value

        #expect(pausable.saved == nil, "a backup already in flight when Delete All Data ran must not put pre-reset data back in iCloud")
    }
}
