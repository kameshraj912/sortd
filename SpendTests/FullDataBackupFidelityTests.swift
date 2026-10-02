import Testing
import SwiftData
import Foundation
import CryptoKit
@testable import Spend

/// Backup and restore, attacked as a person who needs every purchase back:
/// every field, hostile files, a big history, and a backup racing a save.
/// All dates are pinned; purchases go through `TransactionLogger.log`.
@MainActor
struct FullDataBackupFidelityTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "fulldata-fidelity-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func book(_ cards: [CardInfo] = []) -> CardBook {
        let b = CardBook(defaults: scratch())
        b.replaceAll(cards)
        return b
    }

    /// 2026-09-26 12:00:00 UTC, whole seconds.
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func row(id: UUID = UUID(), merchant: String = "Shop", amount: Decimal = 10,
                     date: Date, currency: String = "AUD", homeAmount: Decimal? = 10)
        -> Backup.Snapshot.Row {
        Backup.Snapshot.Row(id: id, date: date, merchant: merchant, rawMerchant: merchant,
                            amount: amount, currencyCode: currency, homeAmount: homeAmount,
                            card: Card.nab.rawValue, category: SpendCategory.groceries.rawValue,
                            source: TxnSource.manual.rawValue, seenIn: "", note: "",
                            createdAt: date, platform: nil, refunded: false,
                            renewsOn: nil, billingPeriod: nil, sourceAccount: nil)
    }

    // MARK: - Every field survives, merge and replace

    /// One purchase with every field set, logged and then edited the way the
    /// app edits it (a rate arrives, a second source sees it, a refund).
    private func fullPurchase(in ctx: ModelContext) throws -> Transaction {
        let p = IncomingPurchase(date: t0, merchant: "Uber Eats", amount: Decimal(string: "23.45")!,
                                 currency: "SGD", card: .scDebit, source: .tap,
                                 category: .eatingOut, note: Transaction.needsCheckTag + "check me",
                                 platform: "uber")
        let t = try TransactionLogger.log(p, in: ctx).transaction
        t.audAmount = Decimal(string: "26.1234")!
        t.markSeen(in: .email)
        t.refunded = true
        t.renewsOn = Date(timeIntervalSince1970: 1_792_000_000)
        t.billingPeriod = "monthly"
        t.sourceAccount = "raj@example.com"
        try ctx.save()
        return t
    }

    private func expectSame(_ a: Transaction, _ b: Transaction) {
        #expect(b.id == a.id)
        #expect(b.merchant == a.merchant)
        #expect(b.rawMerchant == a.rawMerchant)
        #expect(b.amount == a.amount)
        #expect(b.currencyCode == a.currencyCode)
        #expect(b.audAmount == a.audAmount)
        #expect(b.cardRaw == a.cardRaw)
        #expect(b.categoryRaw == a.categoryRaw)
        #expect(b.sourceRaw == a.sourceRaw)
        #expect(b.seenInRaw == a.seenInRaw)
        #expect(b.note == a.note)
        #expect(b.needsCheck == a.needsCheck)
        #expect(b.platform == a.platform)
        #expect(b.refunded == a.refunded)
        #expect(b.renewsOn == a.renewsOn)
        #expect(b.billingPeriod == a.billingPeriod)
        #expect(b.sourceAccount == a.sourceAccount)
        #expect(b.date == a.date)
        #expect(b.createdAt == a.createdAt || abs(b.createdAt.timeIntervalSince(a.createdAt)) < 1)
    }

    @Test(arguments: [Backup.Mode.merge, Backup.Mode.replace])
    func everyFieldOfAPurchaseSurvivesARoundTrip(mode: Backup.Mode) throws {
        let from = try store()
        let original = try fullPurchase(in: from)
        let data = try Backup.data(in: from, defaults: scratch())

        let to = try store()
        try Backup.restore(data, mode: mode, into: to, defaults: scratch(), cardBook: book())

        let back = try to.fetch(FetchDescriptor<Transaction>())
        #expect(back.count == 1)
        if let restored = back.first { expectSame(original, restored) }
    }

    /// Amounts with many decimals must come back exactly: this is money.
    @Test func decimalAmountsComeBackExactly() throws {
        var snap = Backup.Snapshot()
        snap.transactions = [
            row(merchant: "A", amount: Decimal(string: "0.07")!, date: t0, homeAmount: Decimal(string: "0.07")!),
            row(merchant: "B", amount: Decimal(string: "1234567.89")!, date: t0, homeAmount: Decimal(string: "1234567.89")!),
            row(merchant: "C", amount: Decimal(string: "19.999")!, date: t0, homeAmount: Decimal(string: "30.4567")!),
        ]
        let ctx = try store()
        try Backup.restore(try Backup.encode(snap), mode: .replace, into: ctx,
                           defaults: scratch(), cardBook: book())
        let by = Dictionary(uniqueKeysWithValues: try ctx.fetch(FetchDescriptor<Transaction>()).map { ($0.merchant, $0) })
        #expect(by["A"]?.amount == Decimal(string: "0.07")!)
        #expect(by["B"]?.amount == Decimal(string: "1234567.89")!)
        #expect(by["C"]?.amount == Decimal(string: "19.999")!)
        #expect(by["C"]?.audAmount == Decimal(string: "30.4567")!)
    }

    /// A purchase time is kept to the second only: the file writes dates with
    /// `.iso8601`, which has no fractions. Two taps in one second lose their
    /// order, and a restored row is not equal to the one that was backed up.
    /// Whether anyone needs sub-second times is not obvious: Raj decides.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("backup dates use .iso8601, so a purchase's time loses its fraction of a second"))
    func aPurchaseTimeKeepsItsFractionOfASecond() throws {
        let precise = Date(timeIntervalSince1970: 1_790_000_000.4)
        let from = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: precise, merchant: "Coles", amount: 12, currency: "AUD",
                             card: .nab, source: .tap), in: from)
        let data = try Backup.data(in: from, defaults: scratch())
        let to = try store()
        try Backup.restore(data, mode: .merge, into: to, defaults: scratch(), cardBook: book())
        #expect(try to.fetch(FetchDescriptor<Transaction>()).first?.date == precise)
    }

    // MARK: - Cards, rules, settings

    @Test(arguments: [Backup.Mode.merge, Backup.Mode.replace])
    func cardsKeepEveryFieldThroughARoundTrip(mode: Backup.Mode) throws {
        let card = CardInfo(id: "card-A", name: "Everyday Visa", shortName: "Everyday", bank: "NAB",
                            isCredit: true, currency: "SGD", country: "SG", last4: ["4821", "9930"],
                            applePayLast4: ["1177"], walletWords: ["everyday", "visa"], archived: true)
        let from = try store()
        try fullPurchase(in: from).cardRaw = "card-A"
        try from.save()
        let fromBook = book([card])
        let data = try Backup.encode(try {
            // Backup.snapshot reads CardBook.shared; build the same snapshot by hand.
            var s = try Backup.snapshot(in: from, defaults: scratch())
            s.cards = fromBook.cards
            return s
        }())

        let toBook = book()
        try Backup.restore(data, mode: mode, into: try store(), defaults: scratch(), cardBook: toBook)
        #expect(toBook.cards == [card])
    }

    @Test func aRuleAndABudgetSurviveReplaceOnAPhoneThatHadOthers() throws {
        let from = try store()
        from.insert(MerchantRule(key: "ikea", category: .housing))
        try from.save()
        let fromDefaults = scratch()
        fromDefaults.set(3100.0, forKey: "monthlyBudget")
        fromDefaults.set(["groceries": 400.0, "eatingOut": 150.5], forKey: CategoryBudgets.key)
        let data = try Backup.data(in: from, defaults: fromDefaults)

        let to = try store()
        to.insert(MerchantRule(key: "old-rule", category: .transport))
        try to.save()
        let toDefaults = scratch()
        toDefaults.set(99.0, forKey: "monthlyBudget")
        toDefaults.set(["transport": 5.0], forKey: CategoryBudgets.key)
        try Backup.restore(data, mode: .replace, into: to, defaults: toDefaults, cardBook: book())

        #expect(try to.fetch(FetchDescriptor<MerchantRule>()).map(\.key) == ["ikea"])
        #expect(toDefaults.double(forKey: "monthlyBudget") == 3100.0)
        #expect((toDefaults.dictionary(forKey: CategoryBudgets.key) as? [String: Double]) == ["groceries": 400.0, "eatingOut": 150.5])
    }

    /// App Lock: a backup made with the lock OFF, restored with Replace on a
    /// phone that has it ON, used to switch the lock off. The code kept the
    /// lock on only when the backup had no value at all ("a restore never
    /// quietly switches it off"), so an explicit `false` was the same
    /// surprise by another door. Now a restore never turns it off.
    @Test func aReplaceRestoreNeverSwitchesAppLockOff() throws {
        let fromDefaults = scratch()
        fromDefaults.set(false, forKey: "appLockEnabled")
        let data = try Backup.data(in: try store(), defaults: fromDefaults)

        let toDefaults = scratch()
        toDefaults.set(true, forKey: "appLockEnabled")
        try Backup.restore(data, mode: .replace, into: try store(), defaults: toDefaults, cardBook: book())
        #expect(toDefaults.bool(forKey: "appLockEnabled") == true)
    }

    /// What was kept: a backup made with the lock ON still turns it on, on
    /// Replace, for a phone that had it off.
    @Test func aReplaceRestoreStillSwitchesAppLockOn() throws {
        let fromDefaults = scratch()
        fromDefaults.set(true, forKey: "appLockEnabled")
        let data = try Backup.data(in: try store(), defaults: fromDefaults)

        let toDefaults = scratch()
        toDefaults.set(false, forKey: "appLockEnabled")
        try Backup.restore(data, mode: .replace, into: try store(), defaults: toDefaults, cardBook: book())
        #expect(toDefaults.bool(forKey: "appLockEnabled") == true)
    }

    // MARK: - Hostile files

    @Test func hugeStringsRestoreAndComeBackWhole() throws {
        let long = String(repeating: "Café 東京 ", count: 50_000)
        var snap = Backup.Snapshot()
        var r = row(merchant: long, date: t0)
        r.note = long
        snap.transactions = [r]
        let ctx = try store()
        try Backup.restore(try Backup.encode(snap), mode: .merge, into: ctx,
                           defaults: scratch(), cardBook: book())
        let back = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(back.first?.merchant == long)
        #expect(back.first?.note == long)
    }

    @Test func aBackupWithNoPurchasesButRulesAndCardsStillRestoresThem() throws {
        var snap = Backup.Snapshot()
        snap.rules = [Backup.Snapshot.Rule(key: "ikea", category: SpendCategory.housing.rawValue, updatedAt: t0)]
        snap.cards = [CardInfo(id: "c1", name: "C", shortName: "C")]
        let ctx = try store()
        let cards = book()
        let result = try Backup.restore(try Backup.encode(snap), mode: .merge, into: ctx,
                                        defaults: scratch(), cardBook: cards)
        #expect(result.added == 0)
        #expect(result.rules == 1)
        #expect(cards.cards.map(\.id) == ["c1"])
    }

    /// A currency code a person (or an older export) wrote in lower case.
    /// The code never normalises it, so the row matches no currency, has no
    /// rate and counts as zero in every total. A restored purchase must not
    /// quietly vanish from the totals. (The same family as the logger-side
    /// `aLowercaseHomeCurrencyStillCountsInTotals`, on the restore path.)
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("restore keeps a lower-case or padded currency code as written, so the purchase counts as zero"))
    func aLowerCaseCurrencyInABackupIsNormalised() throws {
        var snap = Backup.Snapshot()
        snap.transactions = [row(merchant: "Qantas", amount: 50, date: t0, currency: " aud ", homeAmount: nil)]
        let ctx = try store()
        try Backup.restore(try Backup.encode(snap), mode: .merge, into: ctx,
                           defaults: scratch(), cardBook: book())
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).first?.currencyCode == "AUD")
    }

    /// Dates far outside any real life (1900, 2200) in a hand-edited backup.
    /// The statement importer is meant to refuse these (`absurdDatesAreNotImported`).
    /// A backup written by Sortd never has them, so this is low priority and
    /// the router and Raj decide whether restore should too.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("restore accepts purchases dated 1900 or 2200 from a hand-edited backup"))
    func absurdDatesInABackupAreNotRestored() throws {
        let y1900 = Date(timeIntervalSince1970: -2_208_988_800)
        let y2200 = Date(timeIntervalSince1970: 7_258_118_400)
        var snap = Backup.Snapshot()
        snap.transactions = [row(merchant: "Old", date: y1900), row(merchant: "Future", date: y2200),
                             row(merchant: "Real", date: t0)]
        let ctx = try store()
        try Backup.restore(try Backup.encode(snap), mode: .merge, into: ctx,
                           defaults: scratch(), cardBook: book())
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    // MARK: - A big history

    @Test func twentyThousandPurchasesRoundTripThroughTheEncryptedBlob() async throws {
        // Rows are written straight into a file, not through the logger: the
        // logger re-reads the store per row and would make this a test of the
        // logger. The point here is the size of the backup.
        var snap = Backup.Snapshot()
        snap.transactions = (0..<20_000).map { i in
            row(merchant: "Shop \(i)", amount: Decimal(i % 500) + 1,
                date: t0.addingTimeInterval(Double(i) * 3600), homeAmount: Decimal(i % 500) + 1)
        }
        let from = try store()
        try Backup.restore(try Backup.encode(snap), mode: .replace, into: from,
                           defaults: scratch(), cardBook: book())
        #expect(try from.fetchCount(FetchDescriptor<Transaction>()) == 20_000)

        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: { self.t0 })
        let started = ContinuousClock.now
        try await cloud.backUpNow(from: from)
        let backedUp = ContinuousClock.now - started

        let to = try store()
        let restorer = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: { self.t0 })
        let added = try await restorer.restore(into: to, mode: .replace)
        let total = ContinuousClock.now - started

        #expect(added == 20_000)
        #expect(try to.fetchCount(FetchDescriptor<Transaction>()) == 20_000)
        // Not a benchmark: a screen frozen for a minute is the thing to catch.
        #expect(backedUp < .seconds(60), "backup took \(backedUp)")
        #expect(total < .seconds(120), "backup and restore took \(total)")
    }

    // MARK: - A bad iCloud copy never costs the person what they have

    /// A corrupt iCloud blob, Replace chosen: the local purchases stay.
    @Test func aCorruptICloudCopyLeavesThisPhonesPurchasesAlone() async throws {
        let ctx = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: t0, merchant: "Woolworths", amount: 58.30, currency: "AUD",
                             card: .nab, source: .manual), in: ctx)
        let cloudStore = FakeCloudBackupStore()
        cloudStore.saved = (Data("SBK1".utf8) + Data(repeating: 7, count: 64), t0)
        let keys = FakeBackupKeyStore()
        keys.key = SymmetricKey(size: .bits256)
        let cloud = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: { self.t0 })

        await #expect(throws: CloudBackupError.corrupt) {
            _ = try await cloud.restore(into: ctx, mode: .replace)
        }
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    /// The key never reached this phone (iCloud Keychain late): Replace is
    /// refused and local purchases stay, and a later try with the key works.
    @Test func aMissingKeyRefusesReplaceThenWorksOnceTheKeyArrives() async throws {
        let oldPhone = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: t0, merchant: "Woolworths", amount: 58.30, currency: "AUD",
                             card: .nab, source: .manual), in: oldPhone)
        let cloudStore = FakeCloudBackupStore()
        let keys = FakeBackupKeyStore()
        let old = CloudBackup(store: cloudStore, keys: keys, defaults: scratch(), clock: { self.t0 })
        try await old.backUpNow(from: oldPhone)

        let newKeys = FakeBackupKeyStore()
        let ctx = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: t0, merchant: "Local", amount: 1, currency: "AUD",
                             card: .nab, source: .manual), in: ctx)
        let cloud = CloudBackup(store: cloudStore, keys: newKeys, defaults: scratch(), clock: { self.t0 })
        await #expect(throws: CloudBackupError.noKey) {
            _ = try await cloud.restore(into: ctx, mode: .replace)
        }
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)

        newKeys.key = keys.key   // iCloud Keychain delivers it
        let added = try await cloud.restore(into: ctx, mode: .replace)
        #expect(added == 1)
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).map(\.merchant) == ["Woolworths"])
    }

    // MARK: - A backup racing a save

    /// A `CloudBackupStore` whose `save` can be held open.
    private final class HoldingCloudStore: CloudBackupStore {
        var saved: (blob: Data, modified: Date)?
        var holdSave = false
        var saveStarted = false
        private var parked: CheckedContinuation<Void, Never>?
        func save(_ blob: Data, modified: Date) async throws {
            saveStarted = true
            if holdSave { await withCheckedContinuation { self.parked = $0 } }
            saved = (blob, modified)
        }
        func fetch() async throws -> (blob: Data, modified: Date)? { saved }
        func delete() async throws { saved = nil }
        func release() { holdSave = false; parked?.resume(); parked = nil }
    }

    @MainActor private final class ClockBox { var now: Date; init(_ d: Date) { now = d } }

    /// A purchase is saved while a backup is mid-upload. The snapshot was
    /// taken before it, so the upload cannot hold it. The end of the upload
    /// used to mark the store "clean" (`dirty = false`) while the save's own
    /// scheduled backup had found the cloud busy and given up, so nothing was
    /// scheduled: that purchase was missing from iCloud until some later save.
    @Test func aPurchaseSavedDuringAnUploadIsBackedUpAfterwards() async throws {
        let holding = HoldingCloudStore()
        let keys = FakeBackupKeyStore()
        let defaults = scratch()
        let box = ClockBox(t0)
        let ctx = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: t0, merchant: "First", amount: 5, currency: "AUD",
                             card: .nab, source: .manual), in: ctx)
        let cloud = CloudBackup(store: holding, keys: keys, defaults: defaults, clock: { box.now })
        // Every wait ends at once and moves the clock past the ten-minute cap.
        cloud.sleep = { _ in box.now = box.now.addingTimeInterval(700) }
        cloud.isEnabled = true

        holding.holdSave = true
        let upload = Task { try? await cloud.backUpNow(from: ctx) }
        while !holding.saveStarted { await Task.yield() }   // parked inside save()

        // The person logs a second purchase; the app's save hook fires.
        _ = try TransactionLogger.log(
            IncomingPurchase(date: t0.addingTimeInterval(60), merchant: "Second", amount: 6,
                             currency: "AUD", card: .nab, source: .manual), in: ctx)
        cloud.scheduleBackup(from: ctx)
        _ = await cloud.pending?.value

        holding.release()
        _ = await upload.value
        _ = await cloud.pending?.value
        _ = await cloud.catchUp?.value

        let to = try store()
        let reader = CloudBackup(store: holding, keys: keys, defaults: scratch(), clock: { box.now })
        _ = try await reader.restore(into: to, mode: .replace)
        #expect(try to.fetchCount(FetchDescriptor<Transaction>()) == 2,
                "iCloud holds only what existed before the second purchase")
    }
}
