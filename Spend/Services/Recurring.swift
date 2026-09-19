import Foundation

/// How often a payment repeats.
enum Cadence: String, CaseIterable, Codable, Sendable {
    case weekly, fortnightly, monthly, quarterly, yearly

    var name: String {
        switch self {
        case .weekly: "Weekly"
        case .fortnightly: "Fortnightly"
        case .monthly: "Monthly"
        case .quarterly: "Every 3 months"
        case .yearly: "Yearly"
        }
    }

    /// Typical gap in days, and the gaps that still count as this cadence
    /// (billing dates drift with weekends and short months).
    var days: Double {
        switch self {
        case .weekly: 7
        case .fortnightly: 14
        case .monthly: 30.44
        case .quarterly: 91.3
        case .yearly: 365.25
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .weekly: 5...9
        case .fortnightly: 12...17
        case .monthly: 26...35
        case .quarterly: 80...100
        case .yearly: 350...380
        }
    }

    static func from(gap: Double) -> Cadence? { allCases.first { $0.range.contains(gap) } }

    static func from(period: String?) -> Cadence? {
        switch period?.lowercased() {
        case "weekly": .weekly
        case "monthly": .monthly
        case "quarterly": .quarterly
        case "yearly", "annual", "annually": .yearly
        default: nil
        }
    }

    func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly: calendar.date(byAdding: .day, value: 7, to: date)!
        case .fortnightly: calendar.date(byAdding: .day, value: 14, to: date)!
        case .monthly: calendar.date(byAdding: .month, value: 1, to: date)!
        case .quarterly: calendar.date(byAdding: .month, value: 3, to: date)!
        case .yearly: calendar.date(byAdding: .year, value: 1, to: date)!
        }
    }
}

/// A payment that repeats, found from past purchases or a subscription receipt.
struct Recurring: Identifiable, Hashable, Sendable {
    enum Status: Sendable { case active, lapsed, cancelled }

    let key: String
    let merchant: String
    let category: SpendCategory
    let card: Card
    let cadence: Cadence
    /// Latest charge, in the currency it was charged in.
    let amount: Decimal
    let currency: String
    /// Latest charge in AUD (for totals).
    let audAmount: Decimal
    let lastDate: Date
    let nextDate: Date
    let charges: Int
    /// Previous charge amount, when it was different (a price change).
    let previousAmount: Decimal?
    let status: Status
    /// Charged again after Raj marked it cancelled.
    let chargedAfterCancel: Bool

    var id: String { key }

    var priceChange: Decimal? {
        guard let previousAmount, previousAmount > 0 else { return nil }
        return amount - previousAmount
    }

    /// Something you signed up for (and could cancel), as opposed to rent,
    /// phone and other bills.
    var isSubscription: Bool { category == .subscriptions || category == .entertainment }

    /// Cost spread over a month, in AUD.
    var monthlyAUD: Double { audAmount.double * Cadence.monthly.days / cadence.days }
}

/// Finds repeating payments in purchase history. Pure: no database, no
/// clock except `now`, so it is easy to test.
enum RecurringDetector {
    /// Categories where repeats are habits, not bills (the same coffee every
    /// Monday is not a subscription).
    static let habitCategories: Set<SpendCategory> = [.eatingOut, .foodDelivery, .groceries, .transport, .transfers]

    struct Charge: Sendable {
        let date: Date
        let merchant: String
        let amount: Decimal
        let currency: String
        let audAmount: Decimal
        let category: SpendCategory
        let card: Card
        let renewsOn: Date?
        let billingPeriod: String?
    }

    static func detect(_ charges: [Charge], cancelled: [String: Date] = [:], ignored: Set<String> = [],
                       now: Date = .now, calendar: Calendar = .current) -> [Recurring] {
        let groups = Dictionary(grouping: charges.filter { $0.amount > 0 }) { MerchantName.key($0.merchant) }
        var found: [Recurring] = []

        for (key, group) in groups where !key.isEmpty && !ignored.contains(key) {
            // One charge per day at most (a tap and an email are already merged,
            // but a split payment could still show twice).
            var byDay: [Date: Charge] = [:]
            for c in group { byDay[calendar.startOfDay(for: c.date)] = byDay[calendar.startOfDay(for: c.date)] ?? c }
            let all = byDay.values.sorted { $0.date < $1.date }

            // The bill is the biggest group of similar amounts: rent every
            // fortnight plus a one-off fee is still fortnightly rent.
            let list = mainCluster(all)
            guard let last = list.last else { continue }

            // Habits (food, groceries, rides) only count when the price is
            // identical, 4+ times: a weekly meal-plan box, not a weekly coffee run.
            if habitCategories.contains(last.category) {
                let identical = list.count >= 4 && Set(list.map(\.amount)).count == 1
                if !identical || last.category == .transfers { continue }
            }

            var cadence: Cadence?
            var next: Date?

            // 1. A receipt that says when it renews.
            if let renews = list.compactMap(\.renewsOn).max(),
               let c = Cadence.from(period: last.billingPeriod) ?? Cadence.from(gap: renews.timeIntervalSince(last.date) / 86400) {
                cadence = c
                next = renews
            }

            // 2. Otherwise, a steady rhythm between charges (a skipped month
            // is fine: a 61-day gap is two monthly cycles).
            if cadence == nil, list.count >= 2 {
                let gaps = zip(list, list.dropFirst()).map { $1.date.timeIntervalSince($0.date) / 86400 }
                if let c = bestCadence(gaps), c != .weekly || list.count >= 3 {
                    cadence = c
                    next = c.next(after: last.date, calendar: calendar)
                }
            }

            guard let cadence, var nextDate = next else { continue }

            // Missed a payment? Roll forward, but if it's missed by more than
            // half a cycle it has probably stopped.
            var status: Recurring.Status = .active
            let overdue = now.timeIntervalSince(nextDate) / 86400
            if overdue > max(3, cadence.days / 2) {
                status = .lapsed
            }
            while nextDate < calendar.startOfDay(for: now), status == .active {
                nextDate = cadence.next(after: nextDate, calendar: calendar)
            }

            var chargedAfterCancel = false
            if let cancelledOn = cancelled[key] {
                if last.date > cancelledOn { chargedAfterCancel = true } else { status = .cancelled }
            }

            let previous = list.dropLast().last
            let changed = previous.flatMap { p -> Decimal? in
                guard p.currency == last.currency, p.amount > 0 else { return nil }
                let ratio = abs((last.amount - p.amount) / p.amount).double
                return ratio > 0.01 ? p.amount : nil
            }

            found.append(Recurring(
                key: key, merchant: last.merchant, category: last.category, card: last.card,
                cadence: cadence, amount: last.amount, currency: last.currency, audAmount: last.audAmount,
                lastDate: last.date, nextDate: nextDate, charges: list.count, previousAmount: changed,
                status: status, chargedAfterCancel: chargedAfterCancel))
        }
        return found.sorted { $0.nextDate < $1.nextDate }
    }

    /// Within 25% of each other: a price rise, tax or exchange-rate change
    /// still counts, a random shop visit does not.
    static func similarAmounts(_ amounts: [Decimal]) -> Bool {
        let values = amounts.map(\.double).filter { $0 > 0 }
        guard let lo = values.min(), let hi = values.max() else { return false }
        return hi / lo <= 1.25
    }

    /// Largest set of charges with similar amounts, in date order. Ties go
    /// to the set with the most recent charge.
    static func mainCluster(_ charges: [Charge]) -> [Charge] {
        var clusters: [[Charge]] = []
        for c in charges.sorted(by: { $0.date < $1.date }) {
            if let i = clusters.firstIndex(where: { similarAmounts([$0.last!.amount, c.amount]) }) {
                clusters[i].append(c)
            } else {
                clusters.append([c])
            }
        }
        return clusters.max { a, b in
            a.count != b.count ? a.count < b.count : a.last!.date < b.last!.date
        } ?? []
    }

    /// The cadence that explains most gaps as 1, 2 or 3 cycles, needing at
    /// least one single-cycle gap. Longer cadences win ties, so a monthly
    /// bill isn't read as "every 4 weeks, sometimes skipped".
    static func bestCadence(_ gaps: [Double]) -> Cadence? {
        var best: (Cadence, Double)?
        for c in Cadence.allCases {
            let tolerance = (c.range.upperBound - c.range.lowerBound) / 2
            var fits = 0, single = 0
            for g in gaps {
                let k = (g / c.days).rounded()
                guard k >= 1, k <= 3, abs(g - k * c.days) <= tolerance * k else { continue }
                fits += 1
                if k == 1 { single += 1 }
            }
            let share = Double(fits) / Double(max(gaps.count, 1))
            guard single > 0, share >= 0.6 else { continue }
            if best == nil || share >= best!.1 { best = (c, share) }
        }
        return best?.0
    }
}

/// Raj's choices about recurring payments, kept on the phone.
@MainActor
enum RecurringPrefs {
    private static let cancelledKey = "recurring.cancelled"
    private static let ignoredKey = "recurring.ignored"

    static var cancelled: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: cancelledKey) as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: cancelledKey) }
    }

    static var ignored: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: ignoredKey) }
    }

    static func markCancelled(_ key: String) { cancelled[key] = .now }
    static func undoCancel(_ key: String) { cancelled[key] = nil }
    static func ignore(_ key: String) { ignored.insert(key) }
}

extension Array where Element == Transaction {
    /// Recurring payments in these purchases, with Raj's choices applied.
    @MainActor func recurring(now: Date = .now) -> [Recurring] {
        let charges = filter { !$0.refunded }.map {
            RecurringDetector.Charge(date: $0.date, merchant: $0.merchant, amount: $0.amount,
                                     currency: $0.currencyCode, audAmount: $0.audValue,
                                     category: $0.category, card: $0.card,
                                     renewsOn: $0.renewsOn, billingPeriod: $0.billingPeriod)
        }
        return RecurringDetector.detect(charges, cancelled: RecurringPrefs.cancelled,
                                        ignored: RecurringPrefs.ignored, now: now)
    }
}
