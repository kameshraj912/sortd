import Foundation
import SwiftData

/// "Explore with sample data": a believable two months of spending on two
/// sample cards, in the user's home currency, so a new user (or an App
/// Review tester) can see every screen before connecting anything.
/// Everything it adds is marked and removed in one go.
@MainActor
enum DemoData {
    static let activeKey = "demoActive"
    private static let marker = "Sample purchase"
    private static let cardIds = ["demo-debit", "demo-credit"]

    static var isActive: Bool { UserDefaults.standard.bool(forKey: activeKey) }

    static func load(in context: ModelContext, now: Date = .now) {
        guard !isActive else { return }
        let home = Money.home
        UserDefaults.standard.set(home, forKey: Money.homeKey)
        let region = Locale.current.region?.identifier ?? "AU"
        CardBook.shared.upsert(CardInfo(id: "demo-debit", name: "Everyday Debit", shortName: "Everyday",
                                        currency: home, country: region))
        CardBook.shared.upsert(CardInfo(id: "demo-credit", name: "Rewards Credit", shortName: "Rewards",
                                        isCredit: true, currency: home, country: region))
        let debit = Card(rawValue: "demo-debit"), credit = Card(rawValue: "demo-credit")

        // (days ago, hour, merchant, amount, card)
        var rows: [(Double, Double, String, Decimal, Card)] = [
            (0, 8.4, "Starbucks", 6.20, debit), (0, 12.9, "Uber Eats", 31.40, credit),
            (1, 19.1, "DoorDash", 42.15, credit), (1, 9.0, "Woolworths", 58.30, debit),
            (2, 13.0, "Grill'd", 22.90, debit), (3, 18.2, "Uber", 17.60, debit),
            (4, 20.3, "Uber Eats", 27.80, credit), (5, 8.1, "Starbucks", 6.20, debit),
            (6, 11.4, "Kmart", 36.00, debit), (7, 19.6, "DoorDash", 35.50, credit),
            (9, 12.2, "McDonald's", 12.40, debit), (10, 9.5, "Coles", 71.25, debit),
            (12, 21.0, "Hoyts", 24.50, credit), (14, 19.8, "Uber Eats", 29.95, credit),
            (17, 13.1, "Sushi Hub", 16.80, debit), (20, 9.4, "Woolworths", 64.10, debit),
            (23, 18.7, "Uber", 21.30, debit), (26, 19.2, "DoorDash", 44.25, credit),
            (31, 12.4, "Grill'd", 21.90, debit), (35, 9.0, "Coles", 66.80, debit),
            (38, 20.1, "Uber Eats", 25.10, credit), (44, 11.0, "JB Hi-Fi", 129.00, credit),
            (50, 19.5, "DoorDash", 38.40, credit), (55, 9.2, "Woolworths", 59.95, debit),
        ]
        // Monthly subscriptions and a phone bill, so Recurring has something to show.
        for months in 0..<3 {
            let back = Double(months) * 30.4
            rows.append((back + 3, 6, "Netflix", 18.99, credit))
            rows.append((back + 9, 6, "Spotify", 13.99, credit))
            rows.append((back + 15, 6, "Optus Mobile", 45.00, debit))
        }

        let cal = Calendar.current
        for (daysAgo, hour, merchant, amount, card) in rows {
            let date = cal.startOfDay(for: now).addingTimeInterval(-daysAgo * 86400 + hour * 3600)
            guard date <= now else { continue }
            let t = Transaction(date: date, merchant: merchant, amount: amount, currencyCode: home, card: card,
                                category: Categorizer.category(for: merchant), source: .manual, note: marker)
            context.insert(t)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: activeKey)
    }

    /// Removes every sample purchase and the two sample cards.
    static func clear(in context: ModelContext) {
        let marker = marker
        for t in (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.note == marker }))) ?? [] {
            context.delete(t)
        }
        try? context.save()
        CardBook.shared.replaceAll(CardBook.shared.cards.filter { !cardIds.contains($0.id) })
        UserDefaults.standard.set(false, forKey: activeKey)
    }
}
