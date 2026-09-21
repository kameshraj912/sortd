import Testing
import SwiftData
import Foundation
@testable import Spend

/// Backup and restore. The point of these is that a restore never loses a
/// purchase and never duplicates one — the two ways a backup can betray you.
@MainActor
struct BackupTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "backup-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @discardableResult
    private func add(_ ctx: ModelContext, _ merchant: String, _ amount: Decimal,
                     _ day: String, currency: String = "AUD",
                     category: SpendCategory = .groceries,
                     source: TxnSource = .manual) -> Transaction {
        let t = Transaction(date: date(day), merchant: merchant, amount: amount,
                            currencyCode: currency, card: .nab, category: category,
                            source: source)
        ctx.insert(t)
        try? ctx.save()
        return t
    }

    private func date(_ ymd: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Australia/Melbourne")
        return f.date(from: ymd)!
    }

    // MARK: Round trip

    @Test func everyPurchaseSurvivesARoundTrip() throws {
        let from = try store()
        add(from, "Woolworths", Decimal(string: "58.30")!, "2026-09-01")
        add(from, "Seven Seeds", Decimal(string: "5.50")!, "2026-09-02", category: .eatingOut)
        add(from, "DBS Orchard", Decimal(string: "22.10")!, "2026-09-03", currency: "SGD")

        let data = try Backup.data(in: from, defaults: scratch())

        let to = try store()
        let result = try Backup.restore(data, mode: .merge, into: to, defaults: scratch())

        #expect(result.added == 3)
        #expect(result.skipped == 0)

        let restored = try to.fetch(FetchDescriptor<Transaction>()).sorted { $0.date < $1.date }
        #expect(restored.count == 3)
        #expect(restored[0].merchant == "Woolworths")
        #expect(restored[0].amount == Decimal(string: "58.30")!)
        #expect(restored[1].category == .eatingOut)
        #expect(restored[2].currencyCode == "SGD")
        #expect(restored[2].amount == Decimal(string: "22.10")!)
    }

    @Test func restoringTheSameBackupTwiceAddsNothing() throws {
        let from = try store()
        add(from, "Woolworths", 58.30, "2026-09-01")
        add(from, "Coles", 12.00, "2026-09-02")
        let data = try Backup.data(in: from, defaults: scratch())

        let to = try store()
        let first = try Backup.restore(data, mode: .merge, into: to, defaults: scratch())
        let second = try Backup.restore(data, mode: .merge, into: to, defaults: scratch())

        #expect(first.added == 2)
        #expect(second.added == 0)
        #expect(second.skipped == 2)
        #expect(try to.fetch(FetchDescriptor<Transaction>()).count == 2)
    }

    @Test func mergeKeepsWhatIsAlreadyOnThePhone() throws {
        let from = try store()
        add(from, "Woolworths", 58.30, "2026-09-01")
        let data = try Backup.data(in: from, defaults: scratch())

        let to = try store()
        add(to, "Something Local", 9.99, "2026-09-05")
        try Backup.restore(data, mode: .merge, into: to, defaults: scratch())

        let names = try to.fetch(FetchDescriptor<Transaction>()).map(\.merchant).sorted()
        #expect(names == ["Something Local", "Woolworths"])
    }

    @Test func replaceWipesFirst() throws {
        let from = try store()
        add(from, "Woolworths", 58.30, "2026-09-01")
        let data = try Backup.data(in: from, defaults: scratch())

        let to = try store()
        add(to, "Should Be Gone", 9.99, "2026-09-05")
        try Backup.restore(data, mode: .replace, into: to, defaults: scratch())

        let names = try to.fetch(FetchDescriptor<Transaction>()).map(\.merchant)
        #expect(names == ["Woolworths"])
    }

    // MARK: Details that are easy to drop

    @Test func refundsFlagsAndRenewalsSurvive() throws {
        let from = try store()
        let t = add(from, "Netflix", Decimal(string: "18.99")!, "2026-09-01", category: .entertainment)
        t.refunded = true
        t.renewsOn = date("2026-10-01")
        t.billingPeriod = "monthly"
        t.platform = "apple"
        t.note = "checked"
        try from.save()

        let data = try Backup.data(in: from, defaults: scratch())
        let to = try store()
        try Backup.restore(data, mode: .merge, into: to, defaults: scratch())

        let back = try #require(try to.fetch(FetchDescriptor<Transaction>()).first)
        #expect(back.refunded)
        #expect(back.renewsOn == date("2026-10-01"))
        #expect(back.billingPeriod == "monthly")
        #expect(back.platform == "apple")
        #expect(back.note == "checked")
    }

    @Test func everySourceThatSawAPurchaseSurvives() throws {
        let from = try store()
        let t = add(from, "Uber Eats", Decimal(string: "31.40")!, "2026-09-01", source: .tap)
        t.markSeen(in: .email)
        try from.save()
        #expect(t.seenIn.count == 2)

        let data = try Backup.data(in: from, defaults: scratch())
        let to = try store()
        try Backup.restore(data, mode: .merge, into: to, defaults: scratch())

        let back = try #require(try to.fetch(FetchDescriptor<Transaction>()).first)
        #expect(Set(back.seenIn.map(\.rawValue)) == Set([TxnSource.tap.rawValue, TxnSource.email.rawValue]))
    }

    // MARK: Learned categories

    @Test func aNewerLearnedCategoryWins() throws {
        let from = try store()
        let old = MerchantRule(key: "woolworths", category: .groceries)
        old.updatedAt = date("2026-09-01")
        from.insert(old)
        try from.save()
        let data = try Backup.data(in: from, defaults: scratch())

        // This phone learned something more recent for the same merchant.
        let to = try store()
        let mine = MerchantRule(key: "woolworths", category: .shopping)
        mine.updatedAt = date("2026-09-10")
        to.insert(mine)
        try to.save()

        try Backup.restore(data, mode: .merge, into: to, defaults: scratch())
        let rules = try to.fetch(FetchDescriptor<MerchantRule>())
        #expect(rules.count == 1)
        #expect(rules[0].category == .shopping)
    }

    @Test func anOlderLocalRuleIsUpdatedFromTheBackup() throws {
        let from = try store()
        let newer = MerchantRule(key: "woolworths", category: .groceries)
        newer.updatedAt = date("2026-09-10")
        from.insert(newer)
        try from.save()
        let data = try Backup.data(in: from, defaults: scratch())

        let to = try store()
        let stale = MerchantRule(key: "woolworths", category: .shopping)
        stale.updatedAt = date("2026-09-01")
        to.insert(stale)
        try to.save()

        try Backup.restore(data, mode: .merge, into: to, defaults: scratch())
        let rules = try to.fetch(FetchDescriptor<MerchantRule>())
        #expect(rules.count == 1)
        #expect(rules[0].category == .groceries)
    }

    // MARK: Settings

    @Test func settingsComeBackOnAFreshPhone() throws {
        let fromDefaults = scratch()
        fromDefaults.set(2400.0, forKey: "monthlyBudget")
        fromDefaults.set("SGD", forKey: Money.homeKey)
        fromDefaults.set(true, forKey: "appLockEnabled")
        fromDefaults.set(["eatingOut": 300.0], forKey: CategoryBudgets.key)

        let data = try Backup.data(in: try store(), defaults: fromDefaults)

        let toDefaults = scratch()
        try Backup.restore(data, mode: .merge, into: try store(), defaults: toDefaults)

        #expect(toDefaults.double(forKey: "monthlyBudget") == 2400.0)
        #expect(toDefaults.string(forKey: Money.homeKey) == "SGD")
        #expect(toDefaults.bool(forKey: "appLockEnabled"))
        #expect((toDefaults.dictionary(forKey: CategoryBudgets.key) as? [String: Double])?["eatingOut"] == 300.0)
    }

    // MARK: A backup from a phone with another home currency (bug hunt D1, D2)

    @Test func mergeFromAnotherCurrencyDoesNotMixCurrencies() throws {
        let fromDefaults = scratch()
        fromDefaults.set("SGD", forKey: Money.homeKey)
        let from = try store()
        add(from, "DBS Orchard", 100, "2026-09-01", currency: "SGD").audAmount = 100
        add(from, "Qantas", 50, "2026-09-02", currency: "AUD").audAmount = 45   // 50 AUD in SGD
        try from.save()
        let data = try Backup.data(in: from, defaults: fromDefaults)

        let toDefaults = scratch()
        toDefaults.set("AUD", forKey: Money.homeKey)
        toDefaults.set("AUD", forKey: FXService.convertedKey)
        let to = try store()
        try Backup.restore(data, mode: .merge, into: to, defaults: toDefaults)

        let rows = try to.fetch(FetchDescriptor<Transaction>())
        // S$100 must not be counted as A$100: left for FXService to convert.
        #expect(rows.first { $0.merchant == "DBS Orchard" }?.audAmount == nil)
        // Already in this phone's currency.
        #expect(rows.first { $0.merchant == "Qantas" }?.audAmount == 50)
        #expect(toDefaults.string(forKey: Money.homeKey) == "AUD")
        #expect(toDefaults.string(forKey: FXService.convertedKey) == "AUD")
    }

    @Test func replaceTakesTheBackupsCurrencyWithoutConvertingTheBudgetAgain() throws {
        let fromDefaults = scratch()
        fromDefaults.set("SGD", forKey: Money.homeKey)
        fromDefaults.set(2400.0, forKey: "monthlyBudget")
        let from = try store()
        add(from, "DBS Orchard", 100, "2026-09-01", currency: "SGD").audAmount = 100
        try from.save()
        let data = try Backup.data(in: from, defaults: fromDefaults)

        let toDefaults = scratch()
        toDefaults.set("AUD", forKey: Money.homeKey)
        toDefaults.set("AUD", forKey: FXService.convertedKey)
        toDefaults.set(900.0, forKey: "monthlyBudget")
        let to = try store()
        try Backup.restore(data, mode: .replace, into: to, defaults: toDefaults)

        #expect(toDefaults.string(forKey: Money.homeKey) == "SGD")
        #expect(toDefaults.double(forKey: "monthlyBudget") == 2400.0)
        // Already in SGD, so ensureConverted has nothing to redo.
        #expect(toDefaults.string(forKey: FXService.convertedKey) == "SGD")
        #expect(try to.fetch(FetchDescriptor<Transaction>()).first?.audAmount == 100)
    }

    @Test func mergeOntoAPhoneWithNoCurrencyYetRebasesItsOwnPurchasesOnly() throws {
        // A phone with no currency chosen uses its region's (Money.home). The
        // backup must be in a different one, or there's nothing to rebase:
        // on a Singapore simulator that default is already SGD.
        let backupHome = Money.home == "SGD" ? "NZD" : "SGD"
        let fromDefaults = scratch()
        fromDefaults.set(backupHome, forKey: Money.homeKey)
        let from = try store()
        add(from, "DBS Orchard", 100, "2026-09-01", currency: backupHome).audAmount = 100
        try from.save()
        let data = try Backup.data(in: from, defaults: fromDefaults)

        let toDefaults = scratch()           // no home currency chosen here yet
        let to = try store()
        let mine = add(to, "Coles", 20, "2026-09-03", currency: "AUD")
        mine.audAmount = 20
        try to.save()
        try Backup.restore(data, mode: .merge, into: to, defaults: toDefaults)

        #expect(toDefaults.string(forKey: Money.homeKey) == backupHome)
        #expect(toDefaults.string(forKey: FXService.convertedKey) == backupHome)
        let rows = try to.fetch(FetchDescriptor<Transaction>())
        #expect(rows.first { $0.merchant == "DBS Orchard" }?.audAmount == 100)
        #expect(rows.first { $0.merchant == "Coles" }?.audAmount == nil)   // A$20 to be converted
    }

    @Test func mergeDoesNotOverwriteASettingChosenOnThisPhone() throws {
        let fromDefaults = scratch()
        fromDefaults.set(2400.0, forKey: "monthlyBudget")
        let data = try Backup.data(in: try store(), defaults: fromDefaults)

        let toDefaults = scratch()
        toDefaults.set(900.0, forKey: "monthlyBudget")
        try Backup.restore(data, mode: .merge, into: try store(), defaults: toDefaults)

        #expect(toDefaults.double(forKey: "monthlyBudget") == 900.0)
    }

    @Test func gmailAccountsAreNeverInTheFile() throws {
        let defaults = scratch()
        defaults.set(["someone@example.com"], forKey: "gmailAccounts")
        let data = try Backup.data(in: try store(), defaults: defaults)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("someone@example.com"))
        #expect(!text.contains("gmailAccounts"))
    }

    // MARK: Bad input

    @Test func aRandomFileIsRejected() throws {
        let junk = Data("hello, I am not a backup".utf8)
        #expect(throws: Backup.Failure.self) {
            try Backup.decode(junk)
        }
    }

    @Test func aCSVIsRejected() throws {
        let csv = Data("date,merchant,amount\n2026-09-01,Coles,12.00".utf8)
        #expect(throws: Backup.Failure.self) {
            try Backup.decode(csv)
        }
    }

    @Test func aBackupFromANewerSortdIsRejectedClearly() throws {
        var snapshot = Backup.Snapshot()
        snapshot.version = Backup.formatVersion + 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        #expect(throws: Backup.Failure.self) { try Backup.decode(data) }
    }

    @Test func anEmptyBackupIsValidAndRestoresNothing() throws {
        let data = try Backup.data(in: try store(), defaults: scratch())
        let to = try store()
        let result = try Backup.restore(data, mode: .merge, into: to, defaults: scratch())
        #expect(result.added == 0)
        #expect(try to.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }
}
