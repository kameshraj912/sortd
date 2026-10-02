import Testing
import SwiftData
import Foundation
@testable import Spend

/// Delete All Data must also delete an iCloud copy that was kept.
///
/// Turning iCloud backup off asks "Delete the iCloud copy too?". Someone who
/// chose Keep It and later chose Delete All Data still had that copy in
/// iCloud, because Delete All only deleted it when the switch was on. Now the
/// copy goes whenever this iPhone may have written one: the switch is on, it
/// backed up before (`backedUpFromThisPhone`), or an earlier delete is still
/// pending. A copy this iPhone only restored from is another iPhone's live
/// backup and stays.
@MainActor
struct CloudBackupResetTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "cloudbackupreset-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func logOne(_ context: ModelContext) throws {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000),
                                 merchant: "Woolworths", amount: 58.30, currency: "AUD",
                                 card: .other, source: .email)
        _ = try TransactionLogger.log(p, in: context)
    }

    private let fixedClock: () -> Date = { Date(timeIntervalSince1970: 1_790_500_000) }

    // MARK: The decision

    @Test func deletesWhenTheSwitchIsOn() {
        #expect(CloudBackup.deletesCloudCopyOnReset(switchOn: true, backedUpHere: false, deletePending: false))
    }

    @Test func deletesAKeptCopyWithTheSwitchOff() {
        #expect(CloudBackup.deletesCloudCopyOnReset(switchOn: false, backedUpHere: true, deletePending: false))
    }

    @Test func deletesWhenAnEarlierDeleteIsStillPending() {
        #expect(CloudBackup.deletesCloudCopyOnReset(switchOn: false, backedUpHere: false, deletePending: true))
    }

    /// Never backed up from this iPhone: there is no copy of its own to
    /// delete, and another iPhone's backup is left alone.
    @Test func leavesICloudAloneWhenThisIPhoneNeverBackedUp() {
        #expect(!CloudBackup.deletesCloudCopyOnReset(switchOn: false, backedUpHere: false, deletePending: false))
    }

    /// Restoring on a second iPhone doesn't make the old iPhone's live
    /// backup this one's to delete.
    @Test func aRestoreAloneDoesNotMakeTheCopyThisIPhones() async throws {
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let oldPhoneContext = try store()
        try logOne(oldPhoneContext)
        let oldPhone = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        oldPhone.isEnabled = true
        try await oldPhone.backUpNow(from: oldPhoneContext)
        #expect(oldPhone.backedUpFromThisPhone)

        let newPhone = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: fixedClock)
        let added = try await newPhone.restore(into: try store(), mode: .merge)
        #expect(added == 1)
        #expect(newPhone.lastBackup != nil)
        #expect(newPhone.backedUpFromThisPhone == false)
        #expect(!newPhone.deletesCloudCopyOnReset)
    }

    // MARK: Keep It, then Delete All Data

    @Test func aCopyKeptWhenBackupWasTurnedOffIsDeletedByDeleteAll() async throws {
        let cloudStore = FakeCloudBackupStore()
        let ctx = try store()
        try logOne(ctx)
        let cloud = CloudBackup(store: cloudStore, keys: FakeBackupKeyStore(), defaults: scratch(), clock: fixedClock)
        cloud.isEnabled = true
        try await cloud.backUpNow(from: ctx)
        // Switch off, then "Keep It": nothing is deleted.
        cloud.isEnabled = false
        #expect(cloudStore.saved != nil)

        #expect(cloud.deletesCloudCopyOnReset)
        await cloud.deleteCloudCopyAfterReset()

        #expect(cloudStore.deleteCount == 1)
        #expect(cloudStore.saved == nil)
        #expect(cloud.isDeletePending == false)
        #expect(cloud.lastBackup == nil)
    }

    /// The kept copy's delete still waits for the next launch when iCloud
    /// can't be reached.
    @Test func aKeptCopyThatCantBeDeletedNowIsRetriedAtTheNextLaunch() async throws {
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let defaults = scratch()
        let ctx = try store()
        try logOne(ctx)
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: defaults, clock: fixedClock)
        cloud.isEnabled = true
        try await cloud.backUpNow(from: ctx)
        cloud.isEnabled = false

        cloudStore.deleteError = CloudBackupError.notSignedIn
        #expect(cloud.deletesCloudCopyOnReset)
        await cloud.deleteCloudCopyAfterReset()
        #expect(cloud.isDeletePending == true)
        #expect(cloudStore.saved != nil)

        cloudStore.deleteError = nil
        let nextLaunch = CloudBackup(store: cloudStore, keys: keys, defaults: defaults, clock: fixedClock)
        await nextLaunch.retryPendingDelete()
        #expect(cloudStore.saved == nil)
        #expect(nextLaunch.isDeletePending == false)
    }

    /// The copy was already gone (deleted from another iPhone, say): the
    /// delete is a no-op and nothing stays pending.
    @Test func aCopyThatIsAlreadyGoneCountsAsDeleted() async throws {
        let cloudStore = FakeCloudBackupStore()
        let defaults = scratch()
        defaults.set(true, forKey: CloudBackup.backedUpHereKey)
        let cloud = CloudBackup(store: cloudStore, keys: FakeBackupKeyStore(), defaults: defaults, clock: fixedClock)
        #expect(cloud.isEnabled == false)
        #expect(cloudStore.saved == nil)

        #expect(cloud.deletesCloudCopyOnReset)
        await cloud.deleteCloudCopyAfterReset()
        #expect(cloud.isDeletePending == false)
        #expect(cloud.backedUpFromThisPhone == false)
    }

    @Test func aFreshInstallHasNothingToDelete() {
        let cloud = CloudBackup(store: FakeCloudBackupStore(), keys: FakeBackupKeyStore(), defaults: scratch(), clock: fixedClock)
        #expect(!cloud.deletesCloudCopyOnReset)
    }

    // MARK: The Delete All alert

    @Test func theDeleteAllMessageMentionsICloudWhenTheCopyGoes() {
        let text = BackupDataSettingsView.deleteAllMessage(deletesCloudCopy: true)
        #expect(text.contains("iCloud"))
        #expect(text.hasSuffix("There's no undo."))
    }

    @Test func theDeleteAllMessageLeavesICloudOutWhenThereIsNoCopy() {
        let text = BackupDataSettingsView.deleteAllMessage(deletesCloudCopy: false)
        #expect(!text.contains("iCloud"))
        #expect(!text.contains("Gmail"))
    }
}
