import Foundation

/// What the widget shows, as one small file in the App Group container.
///
/// The widget runs in its own process and can't see Sortd's database. It
/// could be given a copy of the database instead, but that would mean
/// moving the real one into a shared container and migrating everyone's
/// purchases across — a lot of risk for a home screen tile. A few numbers
/// in a file does the same job and never touches the database.
///
/// It stays on the phone: the App Group container is Sortd talking to its
/// own widget, not a server.
nonisolated struct WidgetSummary: Codable, Equatable, Sendable {
    var updatedAt = Date.now
    /// The currency totals are in (`Money.home`).
    var currency = "AUD"
    var today: Decimal = 0
    /// How many purchases make up `today`. Cleared by `asOf` at midnight.
    var todayCount = 0
    /// Monday to now. Less punishing than a daily figure for some people.
    var week: Decimal = 0
    var month: Decimal = 0
    /// What one day is worth against the budget (`perDay`), so "today" has a limit too.
    var dayAllowance: Decimal?
    /// Nil when no monthly budget is set.
    var leftThisMonth: Decimal?
    var perDay: Decimal?
    /// The last three purchases, newest first. Shop names are in here since
    /// 2 Oct 2026; the widgets hide them while the iPhone is locked.
    /// `asOf` leaves this alone at midnight: "the most recent purchase" is
    /// still true the next morning.
    var recent: [Item] = []
    /// Biggest categories this month, largest first.
    var categories: [Slice] = []
    /// Subscriptions and bills due next.
    var bills: [Bill] = []
    /// The monthly budget, if one is set.
    var budget: Decimal?
    /// The card style chosen in Settings, so widgets match the app.
    var style = "satin"
    /// So the widget can say "no purchases yet" rather than "$0".
    var hasAnyPurchases = false
    /// Settings › "Show Amounts When Locked". Nil or false: amounts are
    /// hidden on the Lock Screen and in StandBy until the iPhone is unlocked.
    var showWhenLocked: Bool?
    /// App Lock is on: the widgets hide shop names and amounts even on an
    /// unlocked iPhone, as the app itself does until Face ID. Nil or false
    /// for a file from an older build.
    var appLocked: Bool?

    /// The summary as it stands at `now`. The file is written when Sortd runs;
    /// past midnight, a new week or a new month, the old totals aren't true any
    /// more, so those periods start again from zero until the app updates it.
    func asOf(_ now: Date, calendar: Calendar = .current) -> WidgetSummary {
        var s = self
        if !calendar.isDate(updatedAt, inSameDayAs: now) {
            s.today = 0
            s.todayCount = 0
            s.perDay = nil
        }
        if !calendar.isDate(updatedAt, equalTo: now, toGranularity: .weekOfYear) { s.week = 0 }
        if !calendar.isDate(updatedAt, equalTo: now, toGranularity: .month) {
            s.month = 0
            s.categories = []
            s.leftThisMonth = s.budget
            // Budget over this month's days: February's figure is not March's.
            if let budget = s.budget, budget > 0, let days = calendar.range(of: .day, in: .month, for: now)?.count {
                s.dayAllowance = budget / Decimal(days)
            }
        }
        return s
    }

    /// What can be spent each day for the rest of this month, today included:
    /// what's left of the budget, less bills still to charge, over the days
    /// left. Home's "a day" and the widget's both come from here, so they
    /// always agree. 0 when the budget is used up.
    static func perDay(budget: Decimal, spent: Decimal, billsToCome: Decimal,
                       now: Date, calendar: Calendar = .current) -> Decimal {
        let left = budget - spent
        guard left > 0 else { return 0 }
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysLeft = max(1, daysInMonth - calendar.component(.day, from: now) + 1)
        return max(0, left - billsToCome) / Decimal(daysLeft)
    }

    /// Whether widgets should redact their numbers while the phone is locked.
    var hidesWhenLocked: Bool { showWhenLocked != true || appLocked == true }

    static let showWhenLockedKey = "widgetShowWhenLocked"

    /// 0 when there is no budget. Can go past 1 when over.
    var budgetUsed: Double {
        guard let budget, budget > 0 else { return 0 }
        return (month as NSDecimalNumber).doubleValue / (budget as NSDecimalNumber).doubleValue
    }

    struct Item: Codable, Equatable, Sendable, Identifiable {
        /// The purchase's own id (`Transaction.id`), so a widget row can link
        /// to `sortd://purchase/<id>`.
        var id = UUID()
        var merchant: String
        var amount: Decimal
        var currency: String
        var category: String
        var date: Date
    }

    struct Slice: Codable, Equatable, Sendable, Identifiable {
        var id: String { category }
        /// `SpendCategory.rawValue`.
        var category: String
        var name: String
        var total: Decimal
    }

    struct Bill: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        var name: String
        var amount: Decimal
        var currency: String
        var due: Date
    }

    static let fileName = "widget-summary.json"

    /// Declared here rather than in `SpendStore` so this one file is all the
    /// widget target needs to compile.
    static let appGroup = "group.com.kameshraj.spend"

    /// Nil on a build without the App Group entitlement — a free developer
    /// account can't use App Groups. The app works fine, there's just no
    /// widget, so every call site treats this as optional.
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: fileName)
    }

    static func read(from url: URL? = WidgetSummary.fileURL) -> WidgetSummary? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> WidgetSummary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSummary.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    @discardableResult
    func write(to url: URL? = WidgetSummary.fileURL) -> Bool {
        guard let url, let data = try? encoded() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

extension WidgetSummary {
    /// Reads every field if present and falls back to its default if not, so
    /// a file written by an older build (which has no `todayCount`, say) still
    /// decodes. The synthesized decoder throws on any missing key, and a
    /// widget that can't read its file shows "Nothing logged" until the app
    /// next runs. In an extension so `WidgetSummary()` stays available.
    nonisolated init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? updatedAt
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? currency
        today = try c.decodeIfPresent(Decimal.self, forKey: .today) ?? today
        todayCount = try c.decodeIfPresent(Int.self, forKey: .todayCount) ?? todayCount
        week = try c.decodeIfPresent(Decimal.self, forKey: .week) ?? week
        month = try c.decodeIfPresent(Decimal.self, forKey: .month) ?? month
        dayAllowance = try c.decodeIfPresent(Decimal.self, forKey: .dayAllowance)
        leftThisMonth = try c.decodeIfPresent(Decimal.self, forKey: .leftThisMonth)
        perDay = try c.decodeIfPresent(Decimal.self, forKey: .perDay)
        recent = try c.decodeIfPresent([Item].self, forKey: .recent) ?? recent
        categories = try c.decodeIfPresent([Slice].self, forKey: .categories) ?? categories
        bills = try c.decodeIfPresent([Bill].self, forKey: .bills) ?? bills
        budget = try c.decodeIfPresent(Decimal.self, forKey: .budget)
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? style
        hasAnyPurchases = try c.decodeIfPresent(Bool.self, forKey: .hasAnyPurchases) ?? hasAnyPurchases
        showWhenLocked = try c.decodeIfPresent(Bool.self, forKey: .showWhenLocked)
        appLocked = try c.decodeIfPresent(Bool.self, forKey: .appLocked)
    }
}
