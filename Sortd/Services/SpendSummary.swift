import Foundation

/// Plain-English answers for Siri and Shortcuts ("How much have I spent this
/// week?"). Pure: no database and no clock except `now`, so it is easy to test.
enum SpendSummary {
    enum Period: String, CaseIterable, Sendable {
        case today, week, month

        var phrase: String {
            switch self {
            case .today: "today"
            case .week: "this week"
            case .month: "this month"
            }
        }

        func interval(now: Date, calendar: Calendar) -> DateInterval? {
            switch self {
            case .today: calendar.dateInterval(of: .day, for: now)
            case .week: calendar.dateInterval(of: .weekOfYear, for: now)
            case .month: calendar.dateInterval(of: .month, for: now)
            }
        }
    }

    /// The parts of a purchase the answers need.
    struct Purchase: Sendable {
        let date: Date
        let merchant: String
        let amount: Decimal
        let currency: String
        /// Value in the home currency (0 when refunded).
        let homeValue: Decimal
        let category: SpendCategory
        let refunded: Bool

        init(date: Date, merchant: String, amount: Decimal, currency: String,
             homeValue: Decimal? = nil, category: SpendCategory, refunded: Bool = false) {
            self.date = date
            self.merchant = merchant
            self.amount = amount
            self.currency = currency
            self.homeValue = refunded ? 0 : (homeValue ?? amount)
            self.category = category
            self.refunded = refunded
        }

        init(_ t: Transaction) {
            self.init(date: t.date, merchant: t.merchant, amount: t.amount, currency: t.currencyCode,
                      homeValue: t.audValue, category: t.category, refunded: t.refunded)
        }
    }

    static let noPurchases = "No purchases yet."

    // MARK: Spent

    /// Total spent in the period, and the sentence to say. Transfers are left
    /// out (as in `audTotal`) unless Transfers is the category asked about.
    static func spent(_ purchases: [Purchase], period: Period, category: SpendCategory? = nil,
                      budget: Double = 0, currency: String, now: Date = .now,
                      calendar: Calendar = .current) -> (text: String, total: Decimal) {
        guard !purchases.isEmpty else { return (noPurchases, 0) }
        guard let interval = period.interval(now: now, calendar: calendar) else { return (noPurchases, 0) }

        let inPeriod = purchases.filter { interval.contains($0.date) }
        let total = inPeriod
            .filter { p in
                if let category { return p.category == category }
                return p.category != .transfers
            }
            .reduce(Decimal(0)) { $0 + $1.homeValue }

        let on = category.map { " on \($0.name)" } ?? ""
        guard total > 0 else {
            return ("You haven't spent anything\(on) \(period.phrase).", 0)
        }

        var text = "You've spent \(money(total, currency))\(on) \(period.phrase)"
        // The budget is monthly, so only mention it for the whole month.
        if period == .month, category == nil, budget > 0 {
            text += ", " + budgetClause(spent: total, budget: budget, currency: currency)
        }
        return (text + ".", total)
    }

    // MARK: Budget left

    /// What is left of the monthly budget (negative when over).
    static func budgetLeft(_ purchases: [Purchase], budget: Double, currency: String,
                           now: Date = .now, calendar: Calendar = .current) -> (text: String, left: Decimal) {
        guard budget > 0 else {
            return ("You haven't set a monthly budget. You can set one in Sortd.", 0)
        }
        let limit = Decimal(budget)
        guard !purchases.isEmpty else {
            return ("\(noPurchases) You have all \(money(limit, currency)) of your budget left.", limit)
        }
        let spent = monthTotal(purchases, now: now, calendar: calendar)
        let left = limit - spent
        if left < 0 {
            return ("You're \(money(-left, currency)) over your \(money(limit, currency)) budget this month.", left)
        }
        return ("You have \(money(left, currency)) left of your \(money(limit, currency)) budget this month.", left)
    }

    // MARK: Upcoming bills

    /// The next few active recurring payments due within `days` days.
    static func upcomingBills(_ bills: [Recurring], hasPurchases: Bool, days: Int = 14, limit: Int = 3,
                              now: Date = .now, calendar: Calendar = .current) -> String {
        guard hasPurchases else { return noPurchases }
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days + 1, to: start) else { return noPurchases }
        let due = bills
            .filter { $0.status == .active && $0.nextDate >= start && $0.nextDate < end }
            .sorted { $0.nextDate < $1.nextDate }
            .prefix(limit)
        guard !due.isEmpty else { return "No bills due in the next \(days) days." }

        let parts = due.map { b in
            "\(b.merchant) \(Money.format(b.amount, b.currency)) \(when(b.nextDate, now: now, calendar: calendar))"
        }
        let intro = due.count == 1 ? "Your next bill is" : "Your next \(due.count) bills are"
        return "\(intro): \(parts.joined(separator: ", "))."
    }

    // MARK: Last purchase

    /// The most recent purchase that was not refunded or a transfer.
    static func lastPurchase(_ purchases: [Purchase], now: Date = .now, calendar: Calendar = .current) -> String {
        let real = purchases.filter { !$0.refunded && $0.category != .transfers }
        guard let last = real.max(by: { $0.date < $1.date }) else { return noPurchases }
        let amount = last.amount == 0 ? "A purchase with no amount" : Money.format(last.amount, last.currency)
        let prefix = last.amount == 0 ? amount : "Your last purchase was \(amount)"
        return "\(prefix) at \(last.merchant) \(when(last.date, now: now, calendar: calendar))."
    }

    // MARK: Helpers

    static func monthTotal(_ purchases: [Purchase], now: Date, calendar: Calendar) -> Decimal {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return purchases
            .filter { interval.contains($0.date) && $0.category != .transfers }
            .reduce(Decimal(0)) { $0 + $1.homeValue }
    }

    static func budgetClause(spent: Decimal, budget: Double, currency: String) -> String {
        let limit = Decimal(budget)
        let left = limit - spent
        if left < 0 { return "\(money(-left, currency)) over your \(money(limit, currency)) budget" }
        return "\(money(left, currency)) left of your \(money(limit, currency)) budget"
    }

    /// Whole units for round or large amounts ("$1,240"), cents otherwise ("$12.50").
    static func money(_ value: Decimal, _ currency: String) -> String {
        let hasCents = value.rounded(0) != value
        return Money.format(value, currency, cents: hasCents && abs(value.double) < 1000)
    }

    /// "today", "yesterday", "tomorrow", or "on 3 Oct".
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let a = calendar.startOfDay(for: now), b = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        default: return "on " + date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}
