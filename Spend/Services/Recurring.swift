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

    /// `date` moved forward by `n` cycles, counted from `date` itself.
    func advance(_ date: Date, by n: Int, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly: calendar.date(byAdding: .day, value: 7 * n, to: date)!
        case .fortnightly: calendar.date(byAdding: .day, value: 14 * n, to: date)!
        case .monthly: calendar.date(byAdding: .month, value: n, to: date)!
        case .quarterly: calendar.date(byAdding: .month, value: 3 * n, to: date)!
        case .yearly: calendar.date(byAdding: .year, value: n, to: date)!
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

    func withMerchant(_ name: String) -> Recurring {
        Recurring(key: key, merchant: name, category: category, card: card, cadence: cadence,
                  amount: amount, currency: currency, audAmount: audAmount, lastDate: lastDate,
                  nextDate: nextDate, charges: charges, previousAmount: previousAmount,
                  status: status, chargedAfterCancel: chargedAfterCancel)
    }

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

            // One shop can hold more than one bill (two plans on different
            // amounts). Each run of similar amounts is looked at on its own; a
            // stray one-off at another amount is not a bill.
            let clusters = amountClusters(all)
            let mainIndex = clusters.indices.max { a, b in
                clusters[a].count != clusters[b].count ? clusters[a].count < clusters[b].count
                    : clusters[a].last!.date < clusters[b].last!.date
            }
            var bills: [Recurring] = []
            for (i, list) in clusters.enumerated() where i == mainIndex || list.count >= 3 {
                // The biggest cluster keeps the plain key, so choices made
                // before a second plan appeared still apply to it.
                let billKey = i == mainIndex ? key : "\(key)|\(list[0].amount)"
                if ignored.contains(billKey) { continue }
                if let r = bill(from: list, key: billKey, cancelled: cancelled, now: now, calendar: calendar) { bills.append(r) }
            }
            // Two or more at one shop: the amount tells them apart.
            if bills.count > 1 { bills = bills.map { $0.withMerchant("\($0.merchant) · \(Money.format($0.amount, $0.currency))") } }
            found += bills
        }
        return found.sorted { $0.nextDate < $1.nextDate }
    }

    /// One bill from one run of similar amounts, or nil if it does not repeat.
    private static func bill(from list: [Charge], key: String, cancelled: [String: Date],
                             now: Date, calendar: Calendar) -> Recurring? {
        guard let last = list.last else { return nil }

        // Habits (food, groceries, rides) only count when the price is
        // identical, 4+ times: a weekly meal-plan box, not a weekly coffee run.
        if habitCategories.contains(last.category) {
            let identical = list.count >= 4 && Set(list.map(\.amount)).count == 1
            if !identical || last.category == .transfers { return nil }
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
            // Two charges is enough only for subscriptions and bills; a shop
            // visited twice a month apart isn't a monthly bill.
            let billLike = [.subscriptions, .bills, .housing].contains(last.category)
            if let c = bestCadence(gaps), list.count >= (c == .weekly || !billLike ? 3 : 2) {
                cadence = c
                next = c.next(after: last.date, calendar: calendar)
            }
        }

        guard let cadence, var nextDate = next else { return nil }

        // Missed a payment? Roll forward, but if it's missed by more than
        // half a cycle it has probably stopped.
        var status: Recurring.Status = .active
        let overdue = now.timeIntervalSince(nextDate) / 86400
        if overdue > max(3, cadence.days / 2) {
            status = .lapsed
        }
        // Step from the last real charge each time, so a bill on the 31st
        // goes 28 Feb → 31 Mar, not 28 Feb → 28 Mar.
        var step = 1
        while nextDate < calendar.startOfDay(for: now), status == .active, step < 400 {
            step += 1
            nextDate = cadence.advance(last.date, by: step, calendar: calendar)
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

        return Recurring(
            key: key, merchant: last.merchant, category: last.category, card: last.card,
            cadence: cadence, amount: last.amount, currency: last.currency, audAmount: last.audAmount,
            lastDate: last.date, nextDate: nextDate, charges: list.count, previousAmount: changed,
            status: status, chargedAfterCancel: chargedAfterCancel)
    }

    /// Within 25% of each other: a price rise, tax or exchange-rate change
    /// still counts, a random shop visit does not.
    static func similarAmounts(_ amounts: [Decimal]) -> Bool {
        let values = amounts.map(\.double).filter { $0 > 0 }
        guard let lo = values.min(), let hi = values.max() else { return false }
        return hi / lo <= 1.25
    }

    /// Runs of similar amounts, in date order. A run that starts after another
    /// stopped, on the same rhythm, is the same bill at a new price (a rise of
    /// any size), so it joins that run. Runs that overlap in time are separate
    /// bills.
    static func amountClusters(_ charges: [Charge]) -> [[Charge]] {
        var clusters: [[Charge]] = []
        for c in charges.sorted(by: { $0.date < $1.date }) {
            if let i = clusters.firstIndex(where: { similarAmounts([$0.last!.amount, c.amount]) }) {
                clusters[i].append(c)
            } else {
                clusters.append([c])
            }
        }
        var merged: [[Charge]] = []
        for c in clusters {
            if let i = merged.lastIndex(where: { continues($0, with: c) }) { merged[i] += c } else { merged.append(c) }
        }
        return merged
    }

    /// `new` starts after `old` ended, one to three cycles later.
    private static func continues(_ old: [Charge], with new: [Charge]) -> Bool {
        guard old.count >= 2, let last = old.last, let first = new.first, first.date > last.date,
              old.last!.currency == first.currency else { return false }
        let gaps = zip(old, old.dropFirst()).map { $1.date.timeIntervalSince($0.date) / 86400 }
        guard let c = bestCadence(gaps) else { return false }
        let gap = first.date.timeIntervalSince(last.date) / 86400
        let tolerance = (c.range.upperBound - c.range.lowerBound) / 2
        let k = (gap / c.days).rounded()
        return k >= 1 && k <= 3 && abs(gap - k * c.days) <= tolerance * k
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
    /// Puts one back. Without this, "Not Recurring" was the only
    /// action in the app with no way back.
    static func unignore(_ key: String) { ignored.remove(key) }
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
