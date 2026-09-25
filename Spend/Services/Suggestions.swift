import Foundation

/// Shop suggestions for the add sheet, from local history only: the shops
/// you go to at about this time on this kind of day, most recent first.
/// Nothing leaves the phone and nothing is learned beyond what is stored.
enum Suggestions {
    struct Suggestion: Equatable, Identifiable {
        let merchant: String
        let category: SpendCategory
        var id: String { merchant }
    }

    /// How many chips the add sheet shows.
    static let limit = 3
    /// A shop seen only once is a one-off, not a habit.
    static let minimumVisits = 2

    /// Up to `limit` shops, best first. Each visit scores by how close its
    /// weekday and hour are to `now`, weighted towards recent visits, and
    /// a shop's score is the sum over its visits. Refunds and transfers do
    /// not count as going somewhere.
    static func forNow(_ history: [Transaction], now: Date = .now,
                       calendar: Calendar = .current) -> [Suggestion] {
        let nowDay = calendar.component(.weekday, from: now)
        let nowHour = Double(calendar.component(.hour, from: now)) + Double(calendar.component(.minute, from: now)) / 60
        let nowWeekend = calendar.isDateInWeekend(now)

        struct Tally {
            var score = 0.0
            var visits = 0
            var latest: Transaction
        }
        var byShop: [String: Tally] = [:]
        for t in history where counts(t) {
            let key = MerchantName.key(t.merchant)
            guard !key.isEmpty else { continue }
            let day = calendar.component(.weekday, from: t.date)
            let hour = Double(calendar.component(.hour, from: t.date)) + Double(calendar.component(.minute, from: t.date)) / 60
            let daysAgo = max(0, now.timeIntervalSince(t.date) / 86400)
            let score = dayCloseness(day, nowDay, sameKind: calendar.isDateInWeekend(t.date) == nowWeekend)
                * hourCloseness(hour, nowHour)
                * recency(daysAgo: daysAgo)
            var tally = byShop[key] ?? Tally(latest: t)
            tally.score += score
            tally.visits += 1
            if t.date > tally.latest.date { tally.latest = t }
            byShop[key] = tally
        }

        return byShop.values
            .filter { $0.visits >= minimumVisits && $0.score > 0 }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.latest.merchant < b.latest.merchant
            }
            .prefix(limit)
            .map { Suggestion(merchant: $0.latest.merchant, category: $0.latest.category) }
    }

    /// A real visit: not sample data, not a legacy test tap, not a refund
    /// or a transfer.
    static func counts(_ t: Transaction) -> Bool {
        !t.refunded && t.category != .transfers && !t.merchant.isEmpty
            && t.note != DemoData.marker && t.merchant != LogPurchaseIntent.legacyTestMerchant
    }

    /// Same weekday 1, same kind of day (both weekdays, both weekend) 0.6,
    /// otherwise 0.3.
    static func dayCloseness(_ a: Int, _ b: Int, sameKind: Bool) -> Double {
        if a == b { return 1 }
        return sameKind ? 0.6 : 0.3
    }

    /// 1 at the same hour, fading to 0 four hours away (either side of
    /// midnight).
    static func hourCloseness(_ a: Double, _ b: Double) -> Double {
        let gap = min(abs(a - b), 24 - abs(a - b))
        return max(0, 1 - gap / 4)
    }

    /// Yesterday counts for about twice what a visit six weeks ago does.
    static func recency(daysAgo: Double) -> Double {
        exp(-daysAgo / 60)
    }
}
