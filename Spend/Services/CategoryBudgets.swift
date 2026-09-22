import Foundation

/// A monthly limit per category, on top of the overall budget. Limits are in
/// the home currency (`Money.home`) and live in UserDefaults as
/// [SpendCategory.rawValue: Double].
enum CategoryBudgets {
    static let key = "categoryBudgets"
    /// Alerts already sent, as "yyyy-MM|category|threshold".
    static let alertsKey = "categoryBudgetAlerts"

    // MARK: Storage

    static func all(_ defaults: UserDefaults = .standard) -> [SpendCategory: Double] {
        let raw = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        var out: [SpendCategory: Double] = [:]
        for (k, v) in raw {
            if let c = SpendCategory(rawValue: k), v > 0 { out[c] = v }
        }
        return out
    }

    static func limit(for category: SpendCategory, _ defaults: UserDefaults = .standard) -> Double? {
        all(defaults)[category]
    }

    /// Sets a limit. Zero or less removes it.
    static func set(_ limit: Double, for category: SpendCategory, _ defaults: UserDefaults = .standard) {
        var raw = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        raw[category.rawValue] = limit > 0 ? limit : nil
        defaults.set(raw, forKey: key)
    }

    static func remove(_ category: SpendCategory, _ defaults: UserDefaults = .standard) {
        set(0, for: category, defaults)
    }

    /// The limits exactly as saved, keyed by `SpendCategory.rawValue`.
    static func stored(_ defaults: UserDefaults = .standard) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    // MARK: Currency

    /// The home currency changed: multiply each limit by `rate` and round to a
    /// whole amount, like the monthly budget. Only limits still equal to
    /// `before` change; one set again while the rate loaded is already in the
    /// new currency.
    static func convert(from before: [String: Double], rate: Double, _ defaults: UserDefaults = .standard) {
        guard rate > 0, !before.isEmpty else { return }
        var raw = stored(defaults)
        for (k, v) in raw where before[k] == v && v > 0 {
            raw[k] = max(1, (v * rate).rounded())
        }
        defaults.set(raw, forKey: key)
    }

    // MARK: Progress

    enum Status: Equatable {
        case ok, near, over
    }

    struct Progress: Equatable {
        let spent: Double
        let limit: Double
        /// Negative when over.
        var left: Double { limit - spent }
        /// spent / limit, not capped (1.5 = 50% over).
        var fraction: Double { limit > 0 ? spent / limit : 0 }
        var status: Status {
            if spent > limit { return .over }
            if fraction >= 0.8 { return .near }
            return .ok
        }
    }

    static func progress(spent: Double, limit: Double) -> Progress {
        Progress(spent: max(0, spent), limit: max(0, limit))
    }

    /// This month's progress for every category with a limit.
    static func progress(for transactions: [Transaction], limits: [SpendCategory: Double],
                         now: Date = .now, calendar: Calendar = .current) -> [SpendCategory: Progress] {
        guard !limits.isEmpty, let month = calendar.dateInterval(of: .month, for: now) else { return [:] }
        let items = transactions.filter { month.contains($0.date) }
        var out: [SpendCategory: Progress] = [:]
        for (category, limit) in limits {
            let spent = items.filter { $0.category == category }.audTotal.double
            out[category] = progress(spent: spent, limit: limit)
        }
        return out
    }

    // MARK: Alerts

    enum Threshold: Int, CaseIterable {
        case near = 80
        case over = 100
    }

    struct Alert: Equatable {
        let category: SpendCategory
        let threshold: Threshold
        let progress: Progress
    }

    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func alertKey(month: String, category: SpendCategory, threshold: Threshold) -> String {
        "\(month)|\(category.rawValue)|\(threshold.rawValue)"
    }

    /// Which alerts to send now, and the updated record. Each threshold fires
    /// once per category per month. If both are crossed at once only the
    /// 100% one is sent, but both are recorded. Old months are dropped.
    static func dueAlerts(_ progress: [SpendCategory: Progress], month: String,
                          sent: Set<String>) -> (alerts: [Alert], sent: Set<String>) {
        var record = sent.filter { $0.hasPrefix(month + "|") }
        var alerts: [Alert] = []
        for (category, p) in progress.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let crossed: [Threshold] = Threshold.allCases.filter {
                $0 == .over ? p.status == .over : p.fraction >= 0.8
            }
            let fresh = crossed.filter { !record.contains(alertKey(month: month, category: category, threshold: $0)) }
            if let top = fresh.max(by: { $0.rawValue < $1.rawValue }) {
                alerts.append(Alert(category: category, threshold: top, progress: p))
            }
            for t in crossed { record.insert(alertKey(month: month, category: category, threshold: t)) }
        }
        return (alerts, record)
    }

    static func sentAlerts(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: alertsKey) ?? [])
    }

    static func saveSentAlerts(_ sent: Set<String>, _ defaults: UserDefaults = .standard) {
        defaults.set(sent.sorted(), forKey: alertsKey)
    }
}
