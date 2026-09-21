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
                billingPeriod: t.billingPeriod, sourceAccount: t.sourceAccount
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(try snapshot(in: context, defaults: defaults))
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
                        defaults: UserDefaults = .standard) throws -> Result {
        let snapshot = try decode(data)
        var result = Result()
        // `homeAmount` in the file is in the backup phone's home currency.
        let backupHome: String? = if case .string(let code)? = snapshot.settings[Money.homeKey] { code } else { nil }
        // Replace takes the backup's currency with its settings. Merge keeps this
        // phone's, unless this phone never chose one (then the backup's comes in).
        let phoneHome = defaults.string(forKey: Money.homeKey)
        let homeBefore = phoneHome ?? Money.home
        let homeAfter = mode == .replace ? (backupHome ?? homeBefore) : (phoneHome ?? backupHome ?? homeBefore)

        if mode == .replace {
            try? context.delete(model: Transaction.self)
            try? context.delete(model: MerchantRule.self)
            try context.save()
        }

        // Purchases are matched by id, so restoring the same backup twice
        // adds nothing the second time.
        let existing = Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.id))
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
        var rulesByKey: [String: MerchantRule] = [:]
        for rule in try context.fetch(FetchDescriptor<MerchantRule>()) { rulesByKey[rule.key] = rule }
        for rule in snapshot.rules {
            if let mine = rulesByKey[rule.key] {
                guard rule.updatedAt > mine.updatedAt else { continue }
                mine.categoryRaw = rule.category
                mine.updatedAt = rule.updatedAt
            } else {
                let new = MerchantRule(key: rule.key,
                                       category: SpendCategory(rawValue: rule.category) ?? .other)
                new.updatedAt = rule.updatedAt
                context.insert(new)
            }
            result.rules += 1
        }

        try context.save()

        // Cards: add any this phone doesn't have. Never drop one, or a
        // restore could orphan purchases that point at it.
        if !snapshot.cards.isEmpty {
            let mine = CardBook.shared.cards
            let known = Set(mine.map(\.id))
            let missing = snapshot.cards.filter { !known.contains($0.id) }
            if mode == .replace {
                CardBook.shared.replaceAll(snapshot.cards)
                result.cards = snapshot.cards.count
            } else if !missing.isEmpty {
                CardBook.shared.replaceAll(mine + missing)
                result.cards = missing.count
            }
        }

        for (key, setting) in snapshot.settings where settingKeys.contains(key) {
            // On merge, don't stomp a setting the user has already chosen here.
            if mode == .merge, defaults.object(forKey: key) != nil { continue }
            defaults.set(setting.value, forKey: key)
            result.settings += 1
        }
        // The restored amounts and budget are already in `homeAfter`. Without this,
        // FXService.ensureConverted would convert the restored budget a second time
        // and wipe every converted amount.
        if mode == .replace || homeAfter != homeBefore {
            if mode == .merge {
                // This phone's own purchases were converted to the old currency.
                for t in try context.fetch(FetchDescriptor<Transaction>()) where existing.contains(t.id) {
                    t.audAmount = t.currencyCode == homeAfter ? t.amount : nil
                }
                try context.save()
            }
            defaults.set(homeAfter, forKey: FXService.convertedKey)
        }

        return result
    }
}
