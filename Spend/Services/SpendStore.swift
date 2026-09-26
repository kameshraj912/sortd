import Foundation
import SwiftData
import OSLog

let log = Logger(subsystem: "com.kameshraj.spend", category: "app")

/// The database layout as it shipped in 1.0.
///
/// Every future change to a model (renaming or removing a property, changing
/// a type, adding `.unique`) needs a `SchemaV2` and a stage in
/// `SpendMigrationPlan`. Without one, SwiftData can fail to open an existing
/// user's store and the app stops at launch. Adding an optional or defaulted
/// property is the one change that migrates by itself.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self]
    }
}

enum SpendMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// One container shared by the app UI and the App Intent, so a purchase
/// logged from Shortcuts shows up straight away.
enum SpendStore {
    static let container: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.environment["SPEND_IN_MEMORY"] == "1"
        #else
        let inMemory = false
        #endif
        // `.none`: with the iCloud entitlement present, SwiftData would
        // otherwise mirror the whole store to CloudKit on its own and refuse
        // to open it (unique keys on FXRate, ImportedRecord and MerchantRule
        // are not allowed there). Backup is CloudBackup's own encrypted record.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: SpendMigrationPlan.self, configurations: [config])
        } catch {
            fatalError("Could not open the Spend database: \(error)")
        }
    }()
}

/// Input from any source, before it becomes a `Transaction`.
struct IncomingPurchase {
    var date: Date = .now
    var merchant: String
    var amount: Decimal
    var currency: String
    var card: Card
    var source: TxnSource
    var category: SpendCategory? = nil
    var note: String = ""
    var platform: String? = nil
}

enum TransactionLogger {
    enum Outcome {
        case added(Transaction)
        case merged(Transaction)

        var transaction: Transaction {
            switch self {
            case .added(let t), .merged(let t): t
            }
        }
    }

    /// Adds a purchase, or folds it into an existing one from another source.
    /// `excluding`: purchases this same import already added or matched. Two
    /// identical lines in one statement are two purchases, never a re-send.
    /// Bulk imports pass `learned` (read once) and `save: false`, then save
    /// once at the end: one disk write and one screen refresh, not hundreds.
    /// Unsaved purchases still count for matching (fetches include them).
    @discardableResult
    static func log(_ p: IncomingPurchase, in context: ModelContext, excluding: Set<UUID> = [],
                    learned known: [String: SpendCategory]? = nil, save: Bool = true) throws -> Outcome {
        let learned = try known ?? learnedRules(in: context)
        let cleanName = MerchantName.clean(p.merchant)

        // Only look at purchases near this date.
        let from = p.date.addingTimeInterval(-Deduper.window)
        let to = p.date.addingTimeInterval(Deduper.window)
        let nearby = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= from && $0.date <= to }
        )).filter { !excluding.contains($0.id) }
        let candidate = Deduper.Candidate(date: p.date, merchant: p.merchant, amount: p.amount,
                                          currency: p.currency, card: p.card, source: p.source,
                                          platform: p.platform)
        let pool = nearby.map {
            Deduper.Candidate(date: $0.date, merchant: $0.rawMerchant, amount: $0.amount,
                              currency: $0.currencyCode, card: $0.card, source: $0.source,
                              platform: $0.platform, seenIn: $0.seenIn)
        }

        if let i = Deduper.match(candidate, in: pool) {
            let existing = nearby[i]
            merge(p, into: existing)
            if save { try context.save() }
            return .merged(existing)
        }

        let txn = Transaction(
            date: p.date,
            merchant: cleanName,
            rawMerchant: p.merchant,
            amount: p.amount,
            currencyCode: p.currency,
            card: p.card,
            category: p.category ?? Categorizer.category(for: p.merchant, learned: learned),
            source: p.source,
            note: p.note
        )
        txn.platform = p.platform
        context.insert(txn)
        if save { try context.save() }
        return .added(txn)
    }

    /// The more trusted source wins for merchant name and card; the tap keeps
    /// its exact time because bank records often only carry the date.
    private static func merge(_ p: IncomingPurchase, into t: Transaction) {
        t.markSeen(in: p.source)
        // A bank alert only says "DoorDash"; the DoorDash email names the
        // restaurant. Keep the more useful name whichever arrives first.
        if Deduper.isBarePlatformName(t.merchant), !Deduper.isBarePlatformName(p.merchant) {
            t.merchant = MerchantName.clean(p.merchant)
        }
        if t.platform == nil { t.platform = p.platform }
        if p.source.trust > t.source.trust {
            if t.source != .tap { t.date = p.date }
            t.rawMerchant = p.merchant
            t.source = p.source
        }
        if t.card == .other, p.card != .other { t.card = p.card }
        if t.note.isEmpty, !p.note.isEmpty { t.note = p.note }
    }

    static func learnedRules(in context: ModelContext) throws -> [String: SpendCategory] {
        let rules = try context.fetch(FetchDescriptor<MerchantRule>())
        return Dictionary(rules.map { ($0.key, $0.category) }, uniquingKeysWith: { a, _ in a })
    }

    /// Raj changed a category: remember it and fix his other purchases there.
    /// Re-runs the rules on purchases still in Other, so new built-in rules
    /// reach old purchases. Anything Raj set by hand is kept: his choice is a
    /// learned rule, and learned rules win.
    static func refreshUncategorised(in context: ModelContext) throws {
        let learned = try learnedRules(in: context)
        let other = SpendCategory.other.rawValue
        let pending = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.categoryRaw == other }))
        var changed = false
        // Names saved before the cleaner learned new tricks.
        for t in try context.fetch(FetchDescriptor<Transaction>()) {
            let tidy = MerchantName.clean(t.merchant)
            if tidy != t.merchant { t.merchant = tidy; changed = true }
        }
        // Delivery orders a restaurant rule put under Eating Out. Raj's own
        // choice (a learned rule) still wins.
        let eatingOut = SpendCategory.eatingOut.rawValue
        let delivered = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate {
            $0.categoryRaw == eatingOut && ($0.platform == "doordash" || $0.platform == "uber")
        }))
        for t in delivered where learned[MerchantName.key(t.rawMerchant)] == nil && learned[MerchantName.key(t.merchant)] == nil {
            t.category = .foodDelivery
            changed = true
        }
        for t in pending {
            var next = Categorizer.category(for: t.rawMerchant, learned: learned)
            if next == .other { next = Categorizer.category(for: t.merchant, learned: learned) }
            if next == .other, t.platform == "doordash" || t.platform == "uber" { next = .foodDelivery }
            if next == .other, t.platform == "apple" { next = .entertainment }
            if next != .other { t.category = next; changed = true }
        }
        if changed { try context.save() }
    }

    /// The name a category rule is learned on: the source's own text, unless
    /// that is a bare "DoorDash" / "Uber Eats". Then the shop name (merged in
    /// from the order email) is used, so one DoorDash order doesn't move
    /// every DoorDash order.
    private static func ruleKey(_ t: Transaction) -> String {
        Deduper.isBarePlatformName(t.rawMerchant) ? MerchantName.key(t.merchant) : MerchantName.key(t.rawMerchant)
    }

    /// Other purchases a new category for `t` would also move: the ones
    /// sharing its rule key (same shop). Empty when the shop has no name.
    /// `excluding`: rows to leave alone, such as ones waiting on a pending
    /// delete.
    static func samePlace(as t: Transaction, in context: ModelContext,
                          excluding: Set<UUID> = []) throws -> [Transaction] {
        let key = ruleKey(t)
        guard !key.isEmpty else { return [] }
        return try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.id != t.id && !excluding.contains($0.id) && ruleKey($0) == key }
    }

    /// Raj picked a new category for one purchase.
    ///
    /// `applyToOthers` true: remember it as a rule for the shop and move his
    /// other purchases there too. False ("Just This One"): change only `t`,
    /// learn nothing.
    ///
    /// Returns what changed, so the screen can say "Moved 12 others at
    /// Coles · Undo" and `undo(_:in:)` can put every one of them back.
    @discardableResult
    static func recategorise(_ t: Transaction, to category: SpendCategory, in context: ModelContext,
                             applyToOthers: Bool = true, excluding: Set<UUID> = []) throws -> RecategoriseChange {
        var change = RecategoriseChange(merchant: t.merchant, to: category,
                                        moved: [.init(id: t.id, fromRaw: t.categoryRaw)])
        t.category = category
        let key = ruleKey(t)
        guard applyToOthers, !key.isEmpty else { try context.save(); return change }

        let existing = try context.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.key == key }))
        change.ruleKey = key
        if let rule = existing.first {
            change.ruleBefore = rule.category
            change.ruleUpdatedAtBefore = rule.updatedAt
            rule.categoryRaw = category.rawValue
            rule.updatedAt = .now
        } else {
            context.insert(MerchantRule(key: key, category: category))
        }

        for other in try samePlace(as: t, in: context, excluding: excluding) where other.category != category {
            change.moved.append(.init(id: other.id, fromRaw: other.categoryRaw))
            other.category = category
        }
        try context.save()
        return change
    }

    /// Reverses `recategorise`: every moved purchase gets its old category
    /// back, and the shop's rule goes back to what it was (or away, if the
    /// change made it). Purchases deleted since are skipped.
    static func undo(_ change: RecategoriseChange, in context: ModelContext) throws {
        let ids = change.moved.map(\.id)
        let from = Dictionary(change.moved.map { ($0.id, $0.fromRaw) }, uniquingKeysWith: { a, _ in a })
        let touched = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { ids.contains($0.id) }))
        for t in touched {
            // The raw string as it was, so a value newer than this build
            // survives the round trip.
            if let old = from[t.id] { t.categoryRaw = old }
        }
        if let key = change.ruleKey {
            let rules = try context.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.key == key }))
            if let before = change.ruleBefore {
                if let rule = rules.first {
                    rule.categoryRaw = before.rawValue
                    rule.updatedAt = change.ruleUpdatedAtBefore ?? .now
                } else {
                    let rule = MerchantRule(key: key, category: before)
                    if let stamp = change.ruleUpdatedAtBefore { rule.updatedAt = stamp }
                    context.insert(rule)
                }
            } else {
                for rule in rules { context.delete(rule) }
            }
        }
        try context.save()
    }
}

/// What one `TransactionLogger.recategorise` did, enough to undo it.
struct RecategoriseChange: Equatable, Sendable {
    struct Moved: Equatable, Sendable {
        let id: UUID
        /// `categoryRaw` as it was; `from` reads it as a category.
        let fromRaw: String
        var from: SpendCategory { SpendCategory(rawValue: fromRaw) ?? .other }
    }

    /// The shop, for the toast.
    let merchant: String
    let to: SpendCategory
    /// The purchase picked first, then every other one that changed.
    var moved: [Moved]
    /// The rule key learned or updated; nil for "Just This One".
    var ruleKey: String?
    /// The rule's category before, nil when the change made the rule.
    var ruleBefore: SpendCategory?
    var ruleUpdatedAtBefore: Date?

    /// How many purchases moved besides the one picked.
    var others: Int { max(0, moved.count - 1) }

    /// "Moved 12 others at Coles"; nil when nothing else moved.
    var toastText: String? {
        guard others > 0 else { return nil }
        return "Moved \(others) \(others == 1 ? "other" : "others") at \(merchant)"
    }
}
