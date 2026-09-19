#if DEBUG
import Foundation
import SwiftData

/// Fake purchases for the simulator and screenshots only. Launch with
/// SPEND_SAMPLE_DATA=1 (and SPEND_IN_MEMORY=1 so nothing is kept).
enum SampleData {
    /// Simulator only: imports saved script responses (the JSON the Gmail
    /// script returns), so real purchases can be viewed without a key.
    /// Launch with SPEND_IMPORT_JSON=/path/a.json:/path/b.json
    static func importJSON(_ paths: [String], into context: ModelContext) {
        struct Payload: Decodable { var records: [EmailRecord] }
        for path in paths {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let records = try JSONDecoder().decode(Payload.self, from: data).records
                let summary = try EmailSync.importRecords(records, in: context)
                print("SPEND_IMPORT \(path): \(records.count) records, \(summary.text)")
            } catch {
                print("SPEND_IMPORT failed \(path): \(error)")
            }
        }
    }

    static func load(into context: ModelContext) {
        guard ((try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0) == 0 else { return }

        let rows: [(daysAgo: Double, hour: Double, merchant: String, amount: Decimal, currency: String, card: Card, source: TxnSource)] = [
            (0, 8.5, "Seven Seeds Coffee", 5.50, "AUD", .nab, .tap),
            (0, 12.8, "Uber Eats", 32.40, "AUD", .nab, .email),
            (1, 19.2, "DoorDash", 41.15, "AUD", .stanchart, .email),
            (1, 9.1, "Woolworths Carlton", 64.20, "AUD", .nab, .tap),
            (2, 13.0, "Grill'd", 22.90, "AUD", .nab, .tap),
            (2, 18.4, "PTV Myki", 20.00, "AUD", .nab, .tap),
            (3, 20.1, "Uber Eats", 27.60, "AUD", .nab, .email),
            (4, 8.2, "Seven Seeds Coffee", 5.50, "AUD", .nab, .tap),
            (5, 12.2, "Guzman y Gomez", 18.70, "AUD", .stanchart, .tap),
            (5, 21.0, "Spotify", 13.99, "AUD", .stanchart, .email),
            (6, 11.0, "Kmart Melbourne Central", 38.00, "AUD", .nab, .tap),
            (7, 19.5, "DoorDash", 36.80, "AUD", .nab, .email),
            (8, 13.4, "Toast Box", 7.80, "SGD", .scDebit, .tap),
            (8, 19.0, "FairPrice Finest", 48.35, "SGD", .stanchart, .tap),
            (9, 12.0, "Ya Kun Kaya Toast", 6.40, "SGD", .scDebit, .tap),
            (10, 20.0, "Grab", 18.60, "SGD", .stanchart, .tap),
            (12, 13.2, "Coles Central", 52.10, "AUD", .nab, .tap),
            (14, 19.9, "Uber Eats", 29.95, "AUD", .nab, .email),
            (15, 10.0, "Apple.com/bill", 4.49, "AUD", .stanchart, .email),
            (18, 12.5, "McDonald's", 11.40, "AUD", .nab, .tap),
            (22, 18.0, "Hoyts Melbourne Central", 24.50, "AUD", .nab, .tap),
            (26, 19.3, "DoorDash", 44.25, "AUD", .nab, .email),
            (33, 12.0, "Uber Eats", 25.10, "AUD", .nab, .email),
            (35, 9.0, "Woolworths Carlton", 71.80, "AUD", .nab, .tap),
            (38, 13.0, "Grill'd", 21.90, "AUD", .nab, .tap),
            (40, 20.0, "DoorDash", 38.40, "AUD", .stanchart, .email),
        ]

        let rates: [String: Decimal] = ["SGD": Decimal(string: "1.0986")!]
        for r in rows {
            let date = Calendar.current.startOfDay(for: .now)
                .addingTimeInterval(-r.daysAgo * 86400 + r.hour * 3600)
            guard date <= .now else { continue }
            let t = Transaction(date: date, merchant: r.merchant, amount: r.amount, currencyCode: r.currency,
                                card: r.card, category: Categorizer.category(for: r.merchant), source: r.source)
            if let rate = rates[r.currency] { t.audAmount = (r.amount * rate).rounded(2) }
            context.insert(t)
        }
        try? context.save()
    }
}
#endif
