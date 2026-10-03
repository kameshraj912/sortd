import Foundation
import SwiftData

/// Matching a refund to the purchase it cancels. Used by the Apple Pay refund
/// tap (`LogPurchaseIntent`).
enum Refunds {

    /// Finds the purchase a refund cancels: same amount and currency, within
    /// 14 days before, same card if known, similar merchant or same platform.
    /// Marks it refunded, so it stops counting. Used by refund taps.
    static func markRefunded(amount: Decimal, currency: String, card: Card, merchant: String,
                             platform: String?, before date: Date, lookbackDays: Double = 14,
                             in context: ModelContext) -> Bool {
        markRefundedPurchase(amount: amount, currency: currency, card: card, merchant: merchant,
                             platform: platform, before: date, lookbackDays: lookbackDays, in: context) != nil
    }

    /// `markRefunded`, returning the purchase it marked (nil if none fit).
    static func markRefundedPurchase(amount: Decimal, currency: String, card: Card, merchant: String,
                                     platform: String?, before date: Date, lookbackDays: Double = 14,
                                     in context: ModelContext) -> Transaction? {
        let from = date.addingTimeInterval(-lookbackDays * 86400)
        let to = date.addingTimeInterval(86400)
        guard let pool = try? context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= from && $0.date <= to && $0.refunded == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )) else { return nil }

        let refund = Deduper.Candidate(date: date, merchant: merchant, amount: amount, currency: currency,
                                       card: card, source: .tap, platform: platform)
        let hit = pool.first { t in
            guard t.amount == amount, t.currencyCode == currency else { return false }
            if card != .other, t.card != .other, t.card != card { return false }
            let other = Deduper.Candidate(date: t.date, merchant: t.rawMerchant, amount: t.amount,
                                          currency: t.currencyCode, card: t.card, source: t.source, platform: t.platform)
            let samePlatform = Deduper.platformKey(refund) != nil && Deduper.platformKey(refund) == Deduper.platformKey(other)
            return samePlatform || Deduper.similarity(merchant, t.rawMerchant) >= 0.3
                || Deduper.similarity(merchant, t.merchant) >= 0.3
        }
        guard let t = hit else { return nil }
        t.refunded = true
        if !t.note.isEmpty { t.note += " · " }
        t.note += "Refunded"
        return t
    }

    /// A partial refund: less than the whole purchase (one item back from a
    /// bigger basket). `markRefunded` above only matches the exact amount;
    /// this looks for a purchase strictly bigger than the refund and reduces
    /// its amount instead, keeping the original in the note. Returns the
    /// purchase it changed, or nil if none fit — the caller then falls back
    /// to today's behaviour (a standalone refunded row).
    static func markPartiallyRefunded(amount: Decimal, currency: String, card: Card, merchant: String,
                                      platform: String?, before date: Date, lookbackDays: Double = 14,
                                      in context: ModelContext) -> Transaction? {
        let from = date.addingTimeInterval(-lookbackDays * 86400)
        let to = date.addingTimeInterval(86400)
        guard let pool = try? context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= from && $0.date <= to && $0.refunded == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )) else { return nil }

        let refund = Deduper.Candidate(date: date, merchant: merchant, amount: amount, currency: currency,
                                       card: card, source: .tap, platform: platform)
        let hit = pool.first { t in
            guard t.amount > amount, t.currencyCode == currency else { return false }
            if card != .other, t.card != .other, t.card != card { return false }
            let other = Deduper.Candidate(date: t.date, merchant: t.rawMerchant, amount: t.amount,
                                          currency: t.currencyCode, card: t.card, source: t.source, platform: t.platform)
            let samePlatform = Deduper.platformKey(refund) != nil && Deduper.platformKey(refund) == Deduper.platformKey(other)
            return samePlatform || Deduper.similarity(merchant, t.rawMerchant) >= 0.3
                || Deduper.similarity(merchant, t.merchant) >= 0.3
        }
        guard let t = hit else { return nil }
        let original = t.amount
        t.amount -= amount
        let refundNote = "\(Money.format(amount, currency)) refunded (was \(Money.format(original, t.currencyCode)))"
        t.note = t.note.isEmpty ? refundNote : "\(t.note) · \(refundNote)"
        // The rate used for `audAmount` was for the original amount; nil it
        // out so `FXService.backfill` recomputes it for the new one (the
        // pattern `TransactionDetailView.refreshAUD` uses for a hand-edit).
        t.audAmount = t.currencyCode == Money.home ? t.amount : nil
        return t
    }
}
