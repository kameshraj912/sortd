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
        /// What the bank charged, in the home currency, when a statement line
        /// has already merged into this foreign-currency row. Lets the same
        /// statement, imported again, find the row it already merged with.
        var statementCharge: (amount: Decimal, currency: String)? = nil
    }

    static let window: TimeInterval = 2 * 24 * 3600

    /// Sources that carry the real time of the purchase, not just its date.
    private static let timed: Set<TxnSource> = [.tap, .manual]

    /// Sources that carry only the day: a statement import (CSV, PDF text or
    /// a screenshot, all saved as `.csv`) puts every row at noon.
    private static let dateOnly: Set<TxnSource> = [.csv]

    /// A foreign tap and its home-currency statement line differ by the bank's
    /// exchange spread and foreign fees. Within this share of the statement
    /// amount counts as the same purchase.
    static let foreignTolerance: Decimal = 0.06

    /// Name match needed across currencies. Stricter than the 0.3 used for
    /// the same currency, because the amount cannot confirm the match.
    static let foreignNameScore = 0.6

    /// `amount` in `from`, converted to `to` using the rate for `date`; nil
    /// when no rate is known. Pure: the caller reads the saved rates.
    typealias Convert = (_ amount: Decimal, _ from: String, _ to: String, _ date: Date) -> Decimal?

    /// Index of the best match in `existing`, or nil if this is a new purchase.
    /// `calendar` decides what "the same day" is (the phone's own days).
    /// `convert` lets a tap or hand-typed purchase in a foreign currency meet
    /// its statement line in the statement's currency. It defaults to "no
    /// rates", so cross-currency purchases never match unless asked.
    static func match(_ new: Candidate, in existing: [Candidate],
                      calendar: Calendar = DayKey.calendar,
                      convert: Convert = { _, _, _, _ in nil }) -> Int? {
        // A zero amount means the source failed to send one; never merge those.
        guard new.amount > 0 else { return nil }
        var best: (index: Int, score: Double)?
        for (i, old) in existing.enumerated() {
            // Two purchases typed by hand are two purchases: a person pressing
            // Add is never a re-send (two "Coffee 5" in ten minutes are real).
            if old.source == .manual, new.source == .manual { continue }
            let crossCurrency = old.currency != new.currency
            if crossCurrency {
                guard foreignAmountsAgree(old, new, convert: convert) else { continue }
            } else {
                guard old.amount == new.amount else { continue }
            }
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
            let needed = max(crossCurrency ? foreignNameScore : 0, sameSourceSeenBefore ? 0.8 : 0.3)
            guard nameScore >= needed else { continue }
            // Same source, same shop, same amount on different days is two
            // purchases (a coffee on Monday and Tuesday); only near-identical
            // times are a re-send. A statement row has no time of day, and a
            // row that merged with a tap keeps the tap's time (09:14), so the
            // same statement imported again is a re-send when it is the same
            // calendar day, not when it is within 10 minutes.
            if sameSourceSeenBefore {
                if dateOnly.contains(new.source) {
                    // A row that merged with a tap keeps the tap's day, not
                    // the bank's: a line the bank posted the next day must
                    // still find it, or every re-import doubles it (D2). The
                    // 2-day window above, which let it merge the first time,
                    // is the limit then.
                    let tapDated = everSeenIn.contains(where: timed.contains)
                    if !tapDated, !calendar.isDate(old.date, inSameDayAs: new.date) { continue }
                } else if abs(old.date.timeIntervalSince(new.date)) > 10 * 60 { continue }
            }
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

    /// Every source that has touched a candidate.
    private static func sources(_ c: Candidate) -> [TxnSource] {
        c.seenIn.isEmpty ? [c.source] : c.seenIn
    }

    /// True for a tap or hand-typed purchase in one currency against a
    /// statement line in another, when the tap's amount, converted into the
    /// statement's currency, is within `foreignTolerance` of the statement's.
    /// Anything else (two statements, a tap and an email, no rate) is false.
    private static func foreignAmountsAgree(_ old: Candidate, _ new: Candidate, convert: Convert) -> Bool {
        // The same statement imported again: the row already holds the bank's
        // exact charge from the first time.
        if sources(new).allSatisfy(dateOnly.contains), let charge = old.statementCharge,
           charge.currency == new.currency, charge.amount == new.amount {
            return true
        }
        let statement: Candidate, other: Candidate
        if sources(old).allSatisfy(dateOnly.contains), sources(new).allSatisfy(timed.contains) {
            (statement, other) = (old, new)
        } else if sources(new).allSatisfy(dateOnly.contains), sources(old).allSatisfy(timed.contains) {
            (statement, other) = (new, old)
        } else {
            return false
        }
        guard statement.amount > 0,
              let converted = convert(other.amount, other.currency, statement.currency, other.date),
              converted > 0 else { return false }
        return abs(converted - statement.amount) / statement.amount <= foreignTolerance
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
