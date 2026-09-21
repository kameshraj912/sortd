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
        out.cards = CardBook.shared.cards

        for key in settingKeys {
            guard let raw = defaults.object(forKey: key), let setting = Setting(raw) else { continue }
            out.settings[key] = setting
        }

        out.transactions = try context.fetch(FetchDescriptor<Transaction>()).map { t in
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

    /// Writes the backup to a temporary file for the share sheet.
    /// Named by date so two backups don't overwrite each other.
    @MainActor
    static func file(in context: ModelContext,
                     defaults: UserDefaults = .standard) throws -> URL {
        let day = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sortd backup \(day).sortdbackup")
        try data(in: context, defaults: defaults).write(to: url, options: .atomic)
        return url
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
            t.audAmount = row.homeAmount
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

        return result
    }
}
