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
    /// Monday to now. Less punishing than a daily figure for some people.
    var week: Decimal = 0
    var month: Decimal = 0
    /// Budget split over the days in the month, so "today" has a limit too.
    var dayAllowance: Decimal?
    /// Nil when no monthly budget is set.
    var leftThisMonth: Decimal?
    var perDay: Decimal?
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

    /// 0 when there is no budget. Can go past 1 when over.
    var budgetUsed: Double {
        guard let budget, budget > 0 else { return 0 }
        return (month as NSDecimalNumber).doubleValue / (budget as NSDecimalNumber).doubleValue
    }

    struct Item: Codable, Equatable, Sendable, Identifiable {
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
