import Foundation
import SwiftData

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

    static let formatName = "sortd.backup"
    static let formatVersion = 1

    /// Settings worth carrying to a new phone. Deliberately an allowlist:
    /// anything about *this* device or a live login stays behind. Gmail
    /// accounts are excluded because their keys live in the Keychain and
    /// would restore as connected-but-broken.
    static let settingKeys = [
        "monthlyBudget",
        Money.homeKey,
        "cardStyle",
        "appLockEnabled",
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
        /// Emails already read from Gmail. Without these, reconnecting Gmail on
        /// the new phone reads every email again and brings back purchases the
        /// user had deleted. Optional: backups made before this have none.
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
        var rules = 0
        var cards = 0
        var settings = 0

        var summary: String {
            var parts = ["\(added) purchase\(added == 1 ? "" : "s") added"]
            if skipped > 0 { parts.append("\(skipped) already here") }
            if rules > 0 { parts.append("\(rules) category rule\(rules == 1 ? "" : "s")") }
            if cards > 0 { parts.append("\(cards) card\(cards == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        }
    }

    static func decode(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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

        for key in settingKeys {
            if let setting = snapshot.settings[key] {
                // On merge, don't stomp a setting the user has already chosen here.
                if mode == .merge, defaults.object(forKey: key) != nil { continue }
                defaults.set(setting.value, forKey: key)
                result.settings += 1
            } else if mode == .replace, key != "appLockEnabled" {
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
            let t = Transaction(
                date: row.date, merchant: row.merchant, rawMerchant: row.rawMerchant,
                amount: row.amount, currencyCode: row.currencyCode,
                card: Card(rawValue: row.card),
                category: SpendCategory(rawValue: row.category) ?? .other,
                source: TxnSource(rawValue: row.source) ?? .manual,
                note: row.note
            )
            t.id = row.id
            // Converted in another currency: keep it only if it's already in this
            // one; otherwise leave it empty for FXService.backfill to convert.
            t.audAmount = (backupHome ?? homeAfter) == homeAfter ? row.homeAmount
                : (row.currencyCode == homeAfter ? row.amount : nil)
            t.seenInRaw = row.seenIn
            t.createdAt = row.createdAt
            t.platform = row.platform
            t.refunded = row.refunded
            t.renewsOn = row.renewsOn
            t.billingPeriod = row.billingPeriod
            t.sourceAccount = row.sourceAccount
            t.unmatchedLast4 = row.unmatchedLast4
            context.insert(t)
            result.added += 1
        }

        // Emails already read, so a reconnected Gmail doesn't import them again.
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
