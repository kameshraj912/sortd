import Foundation

/// Decides whether a new purchase is one we already have from another source
/// (e.g. the Wallet tap and the StanChart email alert for the same coffee).
enum Deduper {
    struct Candidate {
        var date: Date
        var merchant: String
        var amount: Decimal
        var currency: String
        var card: Card
        var source: TxnSource
        var platform: String? = nil
        /// Every source that has ever contributed to this row (a merge keeps
        /// adding to this list even after `source` is raised to a more
        /// trusted one). Empty means "only ever seen in `source`" — the
        /// common case for a purchase that has not merged with anything yet.
        var seenIn: [TxnSource] = []
    }

    static let window: TimeInterval = 2 * 24 * 3600

    /// Sources that carry the real time of the purchase, not just its date.
    private static let timed: Set<TxnSource> = [.tap, .manual]

    /// Index of the best match in `existing`, or nil if this is a new purchase.
    /// `calendar` decides what "the same day" is (the phone's own days).
    static func match(_ new: Candidate, in existing: [Candidate],
                      calendar: Calendar = DayKey.calendar) -> Int? {
        // A zero amount means the source failed to send one; never merge those.
        guard new.amount > 0 else { return nil }
        var best: (index: Int, score: Double)?
        for (i, old) in existing.enumerated() {
            // Two purchases typed by hand are two purchases: a person pressing
            // Add is never a re-send (two "Coffee 5" in ten minutes are real).
            if old.source == .manual, new.source == .manual { continue }
            guard old.amount == new.amount, old.currency == new.currency else { continue }
            guard abs(old.date.timeIntervalSince(new.date)) <= window else { continue }
            // Unknown card on either side is fine; two different known cards are not.
            if old.card != .other, new.card != .other, old.card != new.card { continue }

            // Same delivery platform on both sides ("DD *DOORDASH CHENNAIBI"
            // vs a DoorDash email for "Chennai Biryani House") is a strong match.
            let samePlatform = platformKey(old) != nil && platformKey(old) == platformKey(new)
            let nameScore = samePlatform ? 0.95 : similarity(old.merchant, new.merchant)
            // A merge can raise `old.source` past `new.source` (a tap row
            // that later absorbed a bank email is now an email row), but the
            // row was still, at some point, a tap: `seenIn` remembers every
            // source that ever touched it, not just the current, most
            // trusted one.
            let everSeenIn = old.seenIn.isEmpty ? [old.source] : old.seenIn
            let sameSourceSeenBefore = everSeenIn.contains(new.source)
            // Same source twice is only a duplicate if the names clearly agree
            // (two $5 coffees at two cafes on one day are two purchases).
            let needed = sameSourceSeenBefore ? 0.8 : 0.3
            guard nameScore >= needed else { continue }
            // Same source, same shop, same amount on different days is two
            // purchases (a coffee on Monday and Tuesday); only near-identical
            // times are a re-send.
            if sameSourceSeenBefore, abs(old.date.timeIntervalSince(new.date)) > 10 * 60 { continue }
            // A hand-typed purchase and an Apple Pay tap both carry the real
            // time; the 2-day window is for statement rows, which carry only
            // a date. Between those two, only the same day is one purchase: a
            // coffee typed on Monday and a tap at the same shop on Tuesday are
            // two coffees, and Monday's must not move to Tuesday.
            if timed.contains(new.source), everSeenIn.allSatisfy(timed.contains),
               new.source == .manual || everSeenIn.contains(.manual),
               !calendar.isDate(old.date, inSameDayAs: new.date) { continue }

            let timeScore = 1 - abs(old.date.timeIntervalSince(new.date)) / window
            let score = nameScore + timeScore
            if best == nil || score > best!.score { best = (i, score) }
        }
        return best?.index
    }

    /// "doordash" / "uber" if the purchase went through a delivery platform.
    static func platformKey(_ c: Candidate) -> String? {
        if let p = c.platform, p == "doordash" || p == "uber" { return p }
        let s = c.merchant.lowercased()
        if s.contains("doordash") || s.hasPrefix("dd *") { return "doordash" }
        if s.contains("uber") { return "uber" }
        return nil
    }

    /// "DoorDash", "Uber Eats", "Uber" — names that say nothing about the shop.
    static func isBarePlatformName(_ name: String) -> Bool {
        ["doordash", "ubereats", "uber"].contains(MerchantName.key(name))
    }

    /// 0…1. Token overlap, plus a pass if one name contains the other
    /// ("Uber Eats" vs "Uber *Eats Pending").
    static func similarity(_ a: String, _ b: String) -> Double {
        let ka = MerchantName.key(a), kb = MerchantName.key(b)
        if ka.isEmpty || kb.isEmpty { return 0 }
        if ka == kb { return 1 }
        if ka.contains(kb) || kb.contains(ka) { return 0.9 }
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        return Double(ta.intersection(tb).count) / Double(ta.union(tb).count)
    }

    private static func tokens(_ s: String) -> Set<String> {
        let parts = MerchantName.clean(s).lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
        return Set(parts)
    }
}
