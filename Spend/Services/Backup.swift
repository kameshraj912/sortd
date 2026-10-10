import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A full copy of everything Sortd holds, as one file you keep.
///
/// Why a file and not iCloud sync: CloudKit needs a paid Apple Developer
/// account, an iCloud container and an entitlement, and it cannot carry
/// `@Attribute(.unique)` models (`MerchantRule`, `ImportedRecord`, `FXRate`
/// all use one). A file works today, on any account, and the user decides
/// where it goes — Files, iCloud Drive, AirDrop to the new phone.
///
/// Nothing is uploaded. Sortd writes the file and hands it to the share
/// sheet; where it lands is the user's choice.
///
/// Exchange rates are left out on purpose: they are a cache that rebuilds
/// itself from frankfurter.dev, and including them would double the file.
nonisolated enum Backup {

    /// The `.sortdbackup` file type. Declared in `Spend-Info.plist`
    /// (UTExportedTypeDeclarations), so Files, the share sheet and the picker
    /// all know the extension. Without it iOS treats the name as having no
    /// extension and "Keep Both" gave "... .sortdbackup 2".
    static let typeIdentifier = "com.kameshraj.spend.backup"
    static let fileExtension = "sortdbackup"
    static let fileType = UTType(exportedAs: typeIdentifier)

    static let formatName = "sortd.backup"
    static let formatVersion = 1

    /// Settings worth carrying to a new phone. Deliberately an allowlist:
    /// anything about *this* device or a live login stays behind. A backup
    /// made while Gmail still existed may carry Gmail-era settings; they are
    /// not in this list, so a restore ignores them.
    /// `AppLock.enabledKey`, spelt out: `AppLock` is main-actor bound.
    static let appLockKey = "appLockEnabled"

    static let settingKeys = [
        "monthlyBudget",
        Money.homeKey,
        "cardStyle",
        appLockKey,
        CategoryBudgets.key,
        "paymentReminders",
        "recurring.cancelled",
        "recurring.ignored",
    ]

    // MARK: - The file

    struct Snapshot: Codable {
        var format = Backup.formatName
        var version = Backup.formatVersion
        var createdAt = Date.now
        var appVersion: String?
        var cards: [CardInfo] = []
        var settings: [String: Setting] = [:]
        var transactions: [Row] = []
        var rules: [Rule] = []
        /// Email ids recorded by the removed Gmail sync (`ImportedRecord`). Kept
        /// so an old backup still restores completely and a new one keeps the
        /// rows it held. Optional: backups made before this have none.
        var imported: [Imported]?

        /// One purchase. Flat and explicit so the file stays readable and a
        /// future version can add fields without breaking old backups.
        struct Row: Codable {
            var id: UUID
            var date: Date
            var merchant: String
            var rawMerchant: String
            var amount: Decimal
            var currencyCode: String
            var homeAmount: Decimal?
            var card: String
            var category: String
            var source: String
            var seenIn: String
            var note: String
            var createdAt: Date
            var platform: String?
            var refunded: Bool
            var renewsOn: Date?
            var billingPeriod: String?
            var sourceAccount: String?
            /// `Transaction.tapOrigins`. Optional: older backups have none.
            var tapOrigins: String? = nil
            /// Card digits that matched none of the cards, so "Which card?"
            /// can find the purchase. Optional: older backups have none.
            var unmatchedLast4: String? = nil
        }

        struct Imported: Codable {
            var id: String
            var account: String?
        }

        struct Rule: Codable {
            var key: String
            var category: String
            var updatedAt: Date
        }
    }

    /// A UserDefaults value, typed, so restoring puts back what was there.
    enum Setting: Codable {
        case bool(Bool)
        case double(Double)
        case string(String)
        case strings([String])
        case numbers([String: Double])
        case dates([String: Date])

        init?(_ value: Any) {
            switch value {
            case let v as Bool: self = .bool(v)
            case let v as Double: self = .double(v)
            case let v as Int: self = .double(Double(v))
            case let v as String: self = .string(v)
            case let v as [String]: self = .strings(v)
            case let v as [String: Double]: self = .numbers(v)
            case let v as [String: Date]: self = .dates(v)
            default: return nil
            }
        }

        var value: Any {
            switch self {
            case .bool(let v): v
            case .double(let v): v
            case .string(let v): v
            case .strings(let v): v
            case .numbers(let v): v
            case .dates(let v): v
            }
        }
    }

    // MARK: - Making one

    @MainActor
    static func snapshot(in context: ModelContext,
                         defaults: UserDefaults = .standard) throws -> Snapshot {
        var out = Snapshot()
        out.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        // Sample data is never real spending: leave it out, or it comes back on
        // the new phone with no "Clear" banner to remove it.
        out.cards = CardBook.shared.cards.filter { !DemoData.cardIds.contains($0.id) }

        for key in settingKeys {
            guard let raw = defaults.object(forKey: key), let setting = Setting(raw) else { continue }
            out.settings[key] = setting
        }

        out.transactions = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.note != DemoData.marker }
            .map { t in
            Snapshot.Row(
                id: t.id, date: t.date, merchant: t.merchant, rawMerchant: t.rawMerchant,
                amount: t.amount, currencyCode: t.currencyCode, homeAmount: t.audAmount,
                card: t.cardRaw, category: t.categoryRaw, source: t.sourceRaw,
                seenIn: t.seenInRaw, note: t.note, createdAt: t.createdAt,
                platform: t.platform, refunded: t.refunded, renewsOn: t.renewsOn,
                billingPeriod: t.billingPeriod, sourceAccount: t.sourceAccount,
                tapOrigins: t.tapOrigins,
                unmatchedLast4: t.unmatchedLast4
            )
        }

        out.rules = try context.fetch(FetchDescriptor<MerchantRule>()).map {
            Snapshot.Rule(key: $0.key, category: $0.categoryRaw, updatedAt: $0.updatedAt)
        }
        out.imported = try context.fetch(FetchDescriptor<ImportedRecord>()).map {
            Snapshot.Imported(id: $0.id, account: $0.account)
        }

        return out
    }

    @MainActor
    static func data(in context: ModelContext,
                     defaults: UserDefaults = .standard) throws -> Data {
        try encode(try snapshot(in: context, defaults: defaults))
    }

    /// The file's bytes. Safe off the main thread, so the slow part of
    /// saving a big backup doesn't freeze the screen.
    static func encode(_ snapshot: Snapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    // MARK: - Reading one back

    enum Failure: LocalizedError {
        case notABackup
        case tooNew(Int)

        var errorDescription: String? {
            switch self {
            case .notABackup:
                "That file isn't a Sortd backup."
            case .tooNew(let v):
                "This backup was made by a newer version of Sortd (format \(v)). Update Sortd and try again."
            }
        }
    }

    enum Mode {
        /// Keep what's here and add anything the backup has that this phone
        /// doesn't. The safe one, and the default.
        case merge
        /// Wipe first. For "my phone died, put it all back".
        case replace
    }

    struct Result {
        var added = 0
        var skipped = 0
        /// Rows left out because their date can't be real (see `plausible`).
        var badDates = 0
        var rules = 0
        var cards = 0
        var settings = 0

        var summary: String {
            var parts = ["\(added) purchase\(added == 1 ? "" : "s") added"]
            if skipped > 0 { parts.append("\(skipped) already here") }
            if badDates > 0 { parts.append(Backup.badDatesNote(badDates)) }
            if rules > 0 { parts.append("\(rules) category rule\(rules == 1 ? "" : "s")") }
            if cards > 0 { parts.append("\(cards) card\(cards == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        }
    }

    /// 1 Jan 2000, UTC. Nothing Sortd logs is older.
    static let earliestDate = Date(timeIntervalSince1970: 946_684_800)

    /// Whether a restored purchase's date could be real: from 2000 to a year
    /// from now (a bill can be dated ahead, never by years).
    static func plausible(_ date: Date, now: Date = .now) -> Bool {
        date >= earliestDate && date <= now.addingTimeInterval(366 * 24 * 60 * 60)
    }

    /// "2 rows skipped (dates that can't be right)", for the restore message.
    static func badDatesNote(_ count: Int) -> String {
        "\(count) row\(count == 1 ? "" : "s") skipped (dates that can't be right)"
    }

    /// Only the two fields every format version keeps.
    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    static func decode(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // The version first: a newer Sortd may have changed any other field,
        // and that file is "update Sortd", not "not a backup".
        if let header = try? decoder.decode(Header.self, from: data), header.format == formatName,
           header.version > formatVersion {
            throw Failure.tooNew(header.version)
        }
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.format == formatName else {
            throw Failure.notABackup
        }
        guard snapshot.version <= formatVersion else { throw Failure.tooNew(snapshot.version) }
        return snapshot
    }

    @MainActor
    @discardableResult
    static func restore(_ data: Data, mode: Mode, into context: ModelContext,
                        defaults: UserDefaults = .standard,
                        cardBook: CardBook = .shared) throws -> Result {
        let snapshot = try decode(data)
        var result = Result()
        // `homeAmount` in the file is in the backup phone's home currency.
        let backupHome: String? = if case .string(let code)? = snapshot.settings[Money.homeKey] { code } else { nil }
        // Replace takes the backup's currency with its settings. Merge keeps this
        // phone's, unless this phone never chose one (then the backup's comes in).
        let phoneHome = defaults.string(forKey: Money.homeKey)
        let homeBefore = phoneHome ?? Money.home
        let homeAfter = mode == .replace ? (backupHome ?? homeBefore) : (phoneHome ?? backupHome ?? homeBefore)

        // Every change below is saved once, at the end. If anything fails
        // on the way, nothing is kept: a failed Replace must not leave the
        // phone empty.
        do {
            try apply(snapshot, mode: mode, homeBefore: homeBefore, homeAfter: homeAfter,
                      backupHome: backupHome, into: context, result: &result)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        // Cards. Replace: the backup's list, and nothing else (an empty list
        // if the backup has none), so old cards don't linger. A card of this
        // phone's stays only if a restored purchase still points at it.
        // Merge: add any this phone doesn't have, never drop one.
        let mine = cardBook.cards
        if mode == .replace {
            cardBook.replaceAll(replacementCards(snapshot, current: mine))
            result.cards = snapshot.cards.count
        } else {
            let known = Set(mine.map(\.id))
            let missing = snapshot.cards.filter { !known.contains($0.id) }
            if !missing.isEmpty {
                cardBook.replaceAll(mine + missing)
                result.cards = missing.count
            }
        }

        var capped: Set<String> = []
        for key in settingKeys {
            if let setting = snapshot.settings[key] {
                // On merge, don't stomp a setting the user has already chosen here.
                if mode == .merge, defaults.object(forKey: key) != nil { continue }
                // A restore never switches App Lock off, whatever the backup
                // says: once it is on here, the backup can't change it. A
                // backup may still switch it on, as it always could.
                if key == appLockKey, defaults.bool(forKey: key) { continue }
                defaults.set(setting.value, forKey: key)
                result.settings += 1
                if key == FXService.budgetKey || key == CategoryBudgets.key { capped.insert(key) }
            } else if mode == .replace, key != appLockKey {
                // The backup phone never set this, so it had the default. Keep
                // this phone's value and a budget or limit set here in one
                // currency would be read in the backup's. The app lock is the
                // exception: a restore never quietly switches it off.
                defaults.removeObject(forKey: key)
            }
        }
        // The restored amounts and budget are already in `homeAfter`. Without this,
        // FXService.ensureConverted would convert the restored budget a second time
        // and wipe every converted amount.
        if mode == .replace || homeAfter != homeBefore {
            if mode == .replace { defaults.set(homeAfter, forKey: Money.homeKey) }
            defaults.set(homeAfter, forKey: FXService.convertedKey)
        }
        // A budget or limit from the file is held to what the budget field
        // lets anyone type (`BudgetSheet.maxBudget`): a huge one reached
        // Home's pace line and crashed it on every open.
        let cap = BudgetSheet.maxBudget(homeAfter)
        func held(_ value: Double) -> Double? { value.isFinite && value > 0 ? min(value, cap) : nil }
        if capped.contains(FXService.budgetKey) {
            if let budget = held(defaults.double(forKey: FXService.budgetKey)) {
                defaults.set(budget, forKey: FXService.budgetKey)
            } else {
                defaults.removeObject(forKey: FXService.budgetKey)
            }
        }
        if capped.contains(CategoryBudgets.key) {
            defaults.set(CategoryBudgets.stored(defaults).compactMapValues(held), forKey: CategoryBudgets.key)
        }
        // Replace took the sample rows out: this is no longer sample data, so
        // the banner and the analytics pause end too.
        if mode == .replace, defaults.bool(forKey: DemoData.activeKey), !DemoData.hasRows(in: context) {
            defaults.set(false, forKey: DemoData.activeKey)
        }

        return result
    }

    /// The card list after a Replace: the backup's cards, plus any card on
    /// this phone that a restored purchase uses but the backup didn't list
    /// (so no purchase is left pointing at nothing).
    static func replacementCards(_ snapshot: Snapshot, current: [CardInfo]) -> [CardInfo] {
        let listed = Set(snapshot.cards.map(\.id))
        let used = Set(snapshot.transactions.map(\.card))
        let kept = current.filter { used.contains($0.id) && !listed.contains($0.id) }
        return snapshot.cards + kept
    }

    /// What a backup holds, for the Replace warning.
    struct Contents: Equatable {
        var purchases: Int
        var cards: Int
        var createdAt: Date
    }

    static func contents(of data: Data) -> Contents? {
        guard let s = try? decode(data) else { return nil }
        return Contents(purchases: s.transactions.count, cards: s.cards.count, createdAt: s.createdAt)
    }

    /// The Replace confirmation, said plainly: what's here now, and what the
    /// backup will leave. An empty backup says Sortd will be left empty.
    static func replaceWarning(backup: Contents, purchasesHere: Int) -> (title: String, message: String) {
        func purchases(_ n: Int) -> String { n == 1 ? "1 purchase" : "\(n) purchases" }
        func cards(_ n: Int) -> String { n == 0 ? "no cards" : n == 1 ? "1 card" : "\(n) cards" }
        let made = backup.createdAt.formatted(date: .abbreviated, time: .shortened)
        let title = purchasesHere == 0
            ? "Replace this iPhone's data with this backup?"
            : "Replace the \(purchases(purchasesHere)) on this iPhone?"
        var message: String
        if backup.purchases == 0 {
            message = "This backup has no purchases. Replacing will leave Sortd empty."
            if backup.cards > 0 { message += " It has \(cards(backup.cards))." }
            message += " Backup made \(made)."
        } else {
            message = "This backup from \(made) has \(purchases(backup.purchases)) and \(cards(backup.cards)). "
                + "They'll take the place of everything here, and anything added since will be lost."
        }
        message += " This can't be undone."
        return (title, message)
    }

    /// The store changes for `restore`, left unsaved so the caller can save
    /// them all at once or throw them all away.
    @MainActor
    private static func apply(_ snapshot: Snapshot, mode: Mode, homeBefore: String, homeAfter: String,
                              backupHome: String?, into context: ModelContext,
                              result: inout Result) throws {
        let mine = try context.fetch(FetchDescriptor<Transaction>())
        if mode == .replace {
            for t in mine { context.delete(t) }
        } else if homeAfter != homeBefore {
            // This phone's own purchases were converted to the old currency.
            for t in mine { t.audAmount = t.currencyCode == homeAfter ? t.amount : nil }
        }

        // Purchases are matched by id, so restoring the same backup twice
        // adds nothing the second time.
        let existing: Set<UUID> = mode == .replace ? [] : Set(mine.map(\.id))
        for row in snapshot.transactions {
            guard !existing.contains(row.id) else { result.skipped += 1; continue }
            // A date no real purchase has (1900, 2200) only comes from a
            // hand-edited file. It would sit outside every month for ever.
            guard plausible(row.date) else { result.badDates += 1; continue }
            // " aud " from a hand-edited file matches no rate and would count
            // as zero in every total.
            let currency = row.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let t = Transaction(
                date: row.date, merchant: row.merchant, rawMerchant: row.rawMerchant,
                amount: row.amount, currencyCode: currency,
                card: Card(rawValue: row.card),
                category: SpendCategory(rawValue: row.category) ?? .other,
                source: TxnSource(rawValue: row.source) ?? .manual,
                note: row.note
            )
            t.id = row.id
            // Converted in another currency: keep it only if it's already in this
            // one; otherwise leave it empty for FXService.backfill to convert.
            t.audAmount = (backupHome ?? homeAfter) == homeAfter ? row.homeAmount
                : (currency == homeAfter ? row.amount : nil)
            t.seenInRaw = row.seenIn
            t.createdAt = row.createdAt
            t.platform = row.platform
            t.refunded = row.refunded
            t.renewsOn = row.renewsOn
            t.billingPeriod = row.billingPeriod
            t.sourceAccount = row.sourceAccount
            t.tapOrigins = row.tapOrigins
            t.unmatchedLast4 = row.unmatchedLast4
            context.insert(t)
            result.added += 1
        }

        // Email ids from the removed Gmail sync: put back as they were.
        if let imported = snapshot.imported, !imported.isEmpty {
            let have = Set(try context.fetch(FetchDescriptor<ImportedRecord>()).map(\.id))
            for r in imported where !have.contains(r.id) {
                context.insert(ImportedRecord(id: r.id, account: r.account))
            }
        }

        // A learned category is the user's own choice, so a newer one wins.
        // Replace takes the backup's as they are. Rules are updated in place,
        // not deleted and added again: `key` is unique, and a delete and an
        // insert of the same key can't go in one save.
        var rulesByKey: [String: MerchantRule] = [:]
        for rule in try context.fetch(FetchDescriptor<MerchantRule>()) { rulesByKey[rule.key] = rule }
        if mode == .replace {
            let keep = Set(snapshot.rules.map(\.key))
            for (key, rule) in rulesByKey where !keep.contains(key) {
                context.delete(rule)
                rulesByKey[key] = nil
            }
        }
        for rule in snapshot.rules {
            if let mine = rulesByKey[rule.key] {
                guard mode == .replace || rule.updatedAt > mine.updatedAt else { continue }
                mine.categoryRaw = rule.category
                mine.updatedAt = rule.updatedAt
            } else {
                let new = MerchantRule(key: rule.key,
                                       category: SpendCategory(rawValue: rule.category) ?? .other)
                new.updatedAt = rule.updatedAt
                context.insert(new)
                rulesByKey[rule.key] = new
            }
            result.rules += 1
        }
    }
}
