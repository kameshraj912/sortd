import Testing
import Foundation
import CloudKit
import SwiftData
@testable import Spend

/// Being offline: the `Connectivity` wrapper, the one plain sentence for a
/// network failure, the backup that waits for a connection, and a foreign
/// purchase logged with no rates.
@MainActor
struct ConnectivityTests {

    // MARK: Connectivity

    @Test func goingOfflineThenOnlineFiresOnReconnectOnce() {
        let c = Connectivity(isOnline: true)
        var fired = 0
        c.onReconnect = { fired += 1 }
        c.set(isOnline: false)
        #expect(fired == 0)
        c.set(isOnline: true)
        c.set(isOnline: true)
        #expect(fired == 1)
        #expect(c.reconnects == 1)
        #expect(c.isOnline)
    }

    @Test func startingOfflineAndComingOnlineIsAReconnect() {
        let c = Connectivity(isOnline: false)
        var fired = 0
        c.onReconnect = { fired += 1 }
        c.set(isOnline: true)
        #expect(fired == 1)
    }

    @Test func isReconnectIsOnlyOfflineToOnline() {
        #expect(Connectivity.isReconnect(from: false, to: true))
        #expect(!Connectivity.isReconnect(from: true, to: true))
        #expect(!Connectivity.isReconnect(from: true, to: false))
        #expect(!Connectivity.isReconnect(from: false, to: false))
    }

    // MARK: The plain message

    @Test func networkDownErrorsMapToTheOneOfflineSentence() {
        let down: [Error] = [
            URLError(.notConnectedToInternet), URLError(.networkConnectionLost), URLError(.timedOut),
            AccountError.offline, CKError(.networkUnavailable), CKError(.networkFailure),
            CloudKitBackupStore.Failure(code: .networkUnavailable),
        ]
        for error in down {
            #expect(Connectivity.plainMessage(for: error) == "You're offline. Try again when you're connected.")
        }
    }

    @Test func otherErrorsKeepTheirOwnWords() {
        #expect(Connectivity.plainMessage(for: URLError(.badServerResponse)) == nil)
        #expect(Connectivity.plainMessage(for: AccountError.noIdentity) == nil)
        #expect(Connectivity.plainMessage(for: CKError(.quotaExceeded)) == nil)
    }

    @Test func theOfflineSentenceIsPlain() {
        #expect(!Connectivity.offlineMessage.contains("!"))
        #expect(Connectivity.blockedMessage(isOnline: true) == nil)
        #expect(Connectivity.blockedMessage(isOnline: false) == Connectivity.offlineMessage)
    }

    @Test func googleSignInOfflineShowsTheOfflineSentence() {
        let mapped = GoogleIdentityProvider.error(from: URLError(.notConnectedToInternet))
        #expect(mapped.localizedDescription == Connectivity.offlineMessage)
    }

    // MARK: Backup that is behind

    private func memoryContext() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "connectivity-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func statusLineSaysWaitingOnlyWhenOfflineAndBehind() {
        let waiting = CloudBackup.waitingMessage
        #expect(waiting == "Waiting for a connection. Sortd will back up when you're online.")
        let failed = CloudBackup.Status.failed("iCloud couldn't be reached.")
        #expect(CloudBackup.statusLine(status: failed, isEnabled: true, isBehind: true, isOnline: false) == waiting)
        #expect(CloudBackup.statusLine(status: .idle, isEnabled: true, isBehind: true, isOnline: false) == waiting)
        // Online: the usual line.
        #expect(CloudBackup.statusLine(status: failed, isEnabled: true, isBehind: true, isOnline: true) == "iCloud couldn't be reached.")
        #expect(CloudBackup.statusLine(status: .idle, isEnabled: true, isBehind: true, isOnline: true) == nil)
        // Nothing waiting, or the switch is off: nothing to say.
        #expect(CloudBackup.statusLine(status: .idle, isEnabled: true, isBehind: false, isOnline: false) == nil)
        #expect(CloudBackup.statusLine(status: .idle, isEnabled: false, isBehind: true, isOnline: false) == nil)
        // A running backup says so.
        #expect(CloudBackup.statusLine(status: .backingUp, isEnabled: true, isBehind: true, isOnline: false) == "Backing up…")
    }

    @Test func aBackupThatFailedOfflineIsBehindThenUploadsWhenOnlineAgain() async throws {
        let cloudStore = FakeCloudBackupStore()
        let defaults = scratch()
        let ctx = try memoryContext()
        let p = IncomingPurchase(date: .now, merchant: "Coles", amount: 12, currency: "AUD", card: .other, source: .manual)
        try TransactionLogger.log(p, in: ctx)

        let cloud = CloudBackup(store: cloudStore, keys: FakeBackupKeyStore(), defaults: defaults)
        cloud.sleep = { _ in }
        cloud.isEnabled = true
        cloudStore.saveError = CloudKitBackupStore.Failure(code: .networkUnavailable)

        cloud.scheduleBackup(from: ctx)
        await cloud.pending?.value
        #expect(cloudStore.saved == nil)
        #expect(cloud.behind)
        #expect(defaults.bool(forKey: CloudBackup.behindKey))

        // It is remembered across a relaunch.
        let relaunched = CloudBackup(store: cloudStore, keys: FakeBackupKeyStore(), defaults: defaults)
        #expect(relaunched.behind)

        // Back online: the same backup goes up without another save.
        cloudStore.saveError = nil
        await cloud.resumeAfterReconnect(from: ctx)
        #expect(cloudStore.saved != nil)
        #expect(!cloud.behind)
        #expect(cloud.status == .idle)
    }

    @Test func resumeDoesNothingWhenNothingIsBehind() async throws {
        let cloudStore = FakeCloudBackupStore()
        let ctx = try memoryContext()
        let cloud = CloudBackup(store: cloudStore, keys: FakeBackupKeyStore(), defaults: scratch())
        cloud.isEnabled = true
        await cloud.resumeAfterReconnect(from: ctx)
        #expect(cloudStore.saved == nil)
    }

    // MARK: A foreign purchase logged offline

    @Test func aForeignPurchaseLoggedOfflineIsSavedAtOnceAndReRatedLater() async throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let foreign = Money.home == "SGD" ? "USD" : "SGD"
        let date = Date(timeIntervalSince1970: 1_790_000_000)

        // Logged with no rates and no network: the purchase is on disk now.
        let t = try TransactionLogger.log(
            IncomingPurchase(date: date, merchant: "Grab", amount: 25, currency: foreign, card: .other, source: .tap),
            in: ctx).transaction
        #expect(!ctx.hasChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Transaction>()).count == 1)
        #expect(t.amount == 25)
        #expect(t.currencyCode == foreign)
        #expect(t.needsRate)

        // The rate arrives later: the same purchase is re-rated, not lost.
        let day = FXService.dayString(date)
        let key = Money.home == "AUD" ? "\(foreign)-\(day)" : "\(foreign)>\(Money.home)-\(day)"
        ctx.insert(FXRate(key: key, rate: 2))
        try ctx.save()
        _ = await FXService.backfill(in: ctx)
        #expect(!t.needsRate)
        #expect(t.audAmount == 50)
        #expect(t.amount == 25)
    }
}
