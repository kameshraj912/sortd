import Foundation
import SwiftData
import OSLog

let log = Logger(subsystem: "com.kameshraj.spend", category: "app")

/// One container shared by the app UI and the App Intent, so a purchase
/// logged from Shortcuts shows up straight away.
enum SpendStore {
    static let container: ModelContainer = {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.environment["SPEND_IN_MEMORY"] == "1"
        #else
        let inMemory = false
        #endif
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
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
    @discardableResult
    static func log(_ p: IncomingPurchase, in context: ModelContext) throws -> Outcome {
        let learned = try learnedRules(in: context)
        let cleanName = MerchantName.clean(p.merchant)

        // Only look at purchases near this date.
        let from = p.date.addingTimeInterval(-Deduper.window)
        let to = p.date.addingTimeInterval(Deduper.window)
        let nearby = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= from && $0.date <= to }
        ))
        let candidate = Deduper.Candidate(date: p.date, merchant: p.merchant, amount: p.amount,
                                          currency: p.currency, card: p.card, source: p.source,
                                          platform: p.platform)
        let pool = nearby.map {
            Deduper.Candidate(date: $0.date, merchant: $0.rawMerchant, amount: $0.amount,
                              currency: $0.currencyCode, card: $0.card, source: $0.source,
                              platform: $0.platform)
        }

        if let i = Deduper.match(candidate, in: pool) {
            let existing = nearby[i]
            merge(p, into: existing)
            try context.save()
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
        try context.save()
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

    static func recategorise(_ t: Transaction, to category: SpendCategory, in context: ModelContext) throws {
        t.category = category
        let key = MerchantName.key(t.rawMerchant)
        guard !key.isEmpty else { try context.save(); return }

        let existing = try context.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.key == key }))
        if let rule = existing.first {
            rule.categoryRaw = category.rawValue
            rule.updatedAt = .now
        } else {
            context.insert(MerchantRule(key: key, category: category))
        }

        let all = try context.fetch(FetchDescriptor<Transaction>())
        for other in all where other.id != t.id && MerchantName.key(other.rawMerchant) == key {
            other.category = category
        }
        try context.save()
    }
}
