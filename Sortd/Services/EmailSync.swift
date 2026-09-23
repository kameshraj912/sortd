import Foundation
import SwiftData

/// One purchase, refund or subscription read from an email.
nonisolated struct EmailRecord: Codable, Equatable, Sendable {
    struct Subscription: Codable, Equatable, Sendable {
        var name: String?
        var period: String?
        var renews: String?
    }

    var id: String
    var kind: String
    var merchant: String
    var rawMerchant: String?
    var platform: String?
    var amount: String
    var currency: String
    var card: String
    /// Last 4 digits from the email, when the script sends them.
    var last4: String?
    var date: String
    var note: String?
    var subscription: Subscription?
}

enum EmailSync {

    struct Summary: Equatable {
        var added = 0
        var merged = 0
        var refunds = 0
        var skipped = 0
        /// Receipt emails looked at in this sync (Gmail connect only).
        var checked = 0
        /// More emails are waiting than one sync reads.
        var incomplete = false
        /// Accounts whose sync threw. Pull-to-refresh says so instead of
        /// finishing silently and looking identical to "nothing new".
        var failed = 0
        /// Gmail: the oldest email listed when `incomplete`, where the next sync carries on.
        var oldestListed: Date?

        var text: String {
            var parts = ["\(added) new"]
            if checked > 0 { parts.append("\(checked) \(checked == 1 ? "email" : "emails") checked") }
            if merged > 0 { parts.append("\(merged) matched") }
            if refunds > 0 { parts.append("\(refunds) refund\(refunds == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        }
    }

    /// Turns records into purchases. Already-imported ids are skipped, so this
    /// is safe to run on overlapping windows.
    @discardableResult
    static func importRecords(_ records: [EmailRecord], in context: ModelContext, account: String? = nil) throws -> Summary {
        var summary = Summary()
        let done = Set(try context.fetch(FetchDescriptor<ImportedRecord>()).map(\.id))
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        // Purchases first, then refunds, so a refund can find its purchase.
        // Refunds that found nothing last time are tried again too.
        let waiting = pendingRefunds.filter { p in !records.contains { $0.id == p.id } }
        let ordered = records.filter { $0.kind == "purchase" } + records.filter { $0.kind == "refund" } + waiting
        var stillWaiting: [EmailRecord] = []
        for r in ordered where !done.contains(r.id) {
            guard let amount = Decimal(string: r.amount), amount > 0,
                  let date = iso.date(from: r.date) ?? isoPlain.date(from: r.date) else {
                summary.skipped += 1
                continue
            }
            // Raj's own card list decides first (by last 4 digits); the
            // script's CARD_MAP guess is the fallback for older scripts.
            let card = CardBook.shared.card(last4: r.last4) ?? Card(rawValue: r.card)

            if r.kind == "refund" {
                // No match yet (the purchase may come from the other Gmail
                // account on a later sync): leave it unmarked so it's retried.
                guard markRefunded(amount: amount, currency: r.currency, card: card, merchant: r.rawMerchant ?? r.merchant,
                                   platform: r.platform, before: date, in: context) else {
                    // Keep it for 30 days: its purchase may arrive in a later
                    // batch, sync or Gmail account.
                    if date > Date.now.addingTimeInterval(-30 * 86400) { stillWaiting.append(r) }
                    continue
                }
                summary.refunds += 1
            } else {
                var purchase = IncomingPurchase(date: date, merchant: r.merchant, amount: amount,
                                                currency: r.currency, card: card, source: .email,
                                                note: r.note ?? "", platform: r.platform)
                // Delivery orders: use the shop's category if it has one
                // (Costco → Groceries), otherwise Food Delivery.
                if r.platform == "doordash" || r.platform == "uber" {
                    let learned = try TransactionLogger.learnedRules(in: context)
                    let byShop = Categorizer.category(for: r.merchant, learned: learned)
                    purchase.category = [.other, .transport, .eatingOut].contains(byShop) ? .foodDelivery : byShop
                    if r.merchant == "Uber" { purchase.category = .transport }
                }
                // App Store: renewing plans are subscriptions, one-off app
                // buys and in-app purchases count as entertainment.
                if r.platform == "apple" {
                    let learned = try TransactionLogger.learnedRules(in: context)
                    let byName = Categorizer.category(for: r.merchant, learned: learned)
                    purchase.category = byName != .other ? byName : (r.subscription != nil ? .subscriptions : .entertainment)
                }
                // DoorDash re-sends the confirmation when an order is changed:
                // update the earlier purchase instead of adding a second one.
                if r.platform == "doordash", (r.note ?? "").contains("order adjusted"),
                   let earlier = try adjustedOriginal(merchant: r.merchant, near: date, in: context) {
                    earlier.amount = amount
                    earlier.audAmount = r.currency == Money.home ? amount : nil
                    earlier.note = r.note ?? earlier.note
                    summary.merged += 1
                    context.insert(ImportedRecord(id: r.id, account: account))
                    continue
                }
                let outcome = try TransactionLogger.log(purchase, in: context)
                if outcome.transaction.sourceAccount == nil { outcome.transaction.sourceAccount = account }
                switch outcome {
                case .added: summary.added += 1
                case .merged: summary.merged += 1
                }
                if let sub = r.subscription {
                    outcome.transaction.billingPeriod = sub.period
                    outcome.transaction.renewsOn = sub.renews.flatMap(Self.renewalDate)
                }
            }
            context.insert(ImportedRecord(id: r.id, account: account))
        }
        pendingRefunds = stillWaiting
        try context.save()
        CardBook.shared.adoptLegacy(usedIds: Set(records.map(\.card)))
        return summary
    }

    private static let pendingKey = "pendingRefunds"

    /// Refund emails whose purchase hasn't been found yet.
    static var pendingRefunds: [EmailRecord] {
        get {
            guard let d = UserDefaults.standard.data(forKey: pendingKey) else { return [] }
            return (try? JSONDecoder().decode([EmailRecord].self, from: d)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: pendingKey) }
    }

    /// The first DoorDash purchase from this restaurant in the 2 days before.
    private static func adjustedOriginal(merchant: String, near date: Date, in context: ModelContext) throws -> Transaction? {
        let from = date.addingTimeInterval(-2 * 86400)
        let key = MerchantName.key(merchant)
        return try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= from && $0.date <= date },
                                                               sortBy: [SortDescriptor(\.date, order: .reverse)]))
            .first { $0.platform == "doordash" && MerchantName.key($0.merchant) == key }
    }

    /// "15 September 2027" (Apple's format) → date.
    nonisolated static func renewalDate(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "d MMMM yyyy"
        return f.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    /// Finds the purchase a refund cancels: same amount and currency, within
    /// 14 days before, same card if known, similar merchant or same platform.
    /// Finds the purchase a refund belongs to and marks it refunded, so it
    /// stops counting. Used by email refunds and by refund taps.
    static func markRefunded(amount: Decimal, currency: String, card: Card, merchant: String,
                             platform: String?, before date: Date, lookbackDays: Double = 14,
                             in context: ModelContext) -> Bool {
        let from = date.addingTimeInterval(-lookbackDays * 86400)
        let to = date.addingTimeInterval(86400)
        guard let pool = try? context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= from && $0.date <= to && $0.refunded == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )) else { return false }

        let refund = Deduper.Candidate(date: date, merchant: merchant, amount: amount, currency: currency,
                                       card: card, source: .email, platform: platform)
        let hit = pool.first { t in
            guard t.amount == amount, t.currencyCode == currency else { return false }
            if card != .other, t.card != .other, t.card != card { return false }
            let other = Deduper.Candidate(date: t.date, merchant: t.rawMerchant, amount: t.amount,
                                          currency: t.currencyCode, card: t.card, source: t.source, platform: t.platform)
            let samePlatform = Deduper.platformKey(refund) != nil && Deduper.platformKey(refund) == Deduper.platformKey(other)
            return samePlatform || Deduper.similarity(merchant, t.rawMerchant) >= 0.3
                || Deduper.similarity(merchant, t.merchant) >= 0.3
        }
        guard let t = hit else { return false }
        t.refunded = true
        if !t.note.isEmpty { t.note += " · " }
        t.note += "Refunded"
        return true
    }
}
