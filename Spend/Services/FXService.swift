import Foundation
import SwiftData

/// Fills in `audAmount` for non-AUD purchases using daily ECB rates from
/// frankfurter.dev (free, no key). Rates are cached, so each day is fetched once.
enum FXService {
    private struct Series: Decodable {
        let rates: [String: [String: Double]]
    }

    /// "2026-09-18" in the phone's own time zone.
    static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Home currency changed: forget converted values, then convert again.
    /// The currency `audAmount` values are currently in.
    static let convertedKey = "convertedTo"

    /// Safety net: if the saved values were converted for a different
    /// currency than the current home one, convert them again.
    static func ensureConverted(in context: ModelContext) async {
        let home = Money.home
        guard UserDefaults.standard.string(forKey: convertedKey) != home else { return }
        await rebase(to: home, in: context)
    }

    static func rebase(to home: String, in context: ModelContext) async {
        let old = UserDefaults.standard.string(forKey: convertedKey) ?? Money.home
        // The monthly budget was set in the old currency: convert it too.
        if old != home, UserDefaults.standard.double(forKey: "monthlyBudget") > 0,
           let rate = try? await latestRate(from: old, to: home) {
            let b = UserDefaults.standard.double(forKey: "monthlyBudget") * rate
            UserDefaults.standard.set((b / 10).rounded() * 10, forKey: "monthlyBudget")
        }
        UserDefaults.standard.set(home, forKey: Money.homeKey)
        UserDefaults.standard.set(home, forKey: convertedKey)
        for t in (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] {
            t.audAmount = t.currencyCode == home ? t.amount : nil
        }
        try? context.save()
        await backfill(in: context)
    }

    /// Converts every purchase still missing a home-currency value. Safe to call often.
    static func backfill(in context: ModelContext) async {
        do {
            let pending = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.audAmount == nil }))
            guard !pending.isEmpty else { return }

            let home = Money.home
            for (currency, txns) in Dictionary(grouping: pending, by: \.currencyCode) {
                if currency == home {
                    for t in txns { t.audAmount = t.amount }
                    continue
                }
                guard let earliest = txns.map(\.date).min() else { continue }
                // Start a few days early so a Monday purchase can use Friday's rate.
                try await fetchRates(currency: currency, to: home, from: earliest.addingTimeInterval(-5 * 86400), in: context)
                // Home currency changed while waiting: these rates are for the old one.
                guard Money.home == home else { return }
                for t in txns {
                    if let rate = try rate(currency: currency, to: home, on: t.date, in: context) {
                        t.audAmount = (t.amount * rate).rounded(2)
                    }
                }
            }
            try context.save()
        } catch {
            log.error("FX backfill failed: \(error.localizedDescription)")
        }
    }

    private static func fetchRates(currency: String, to home: String, from: Date, in context: ModelContext) async throws {
        let start = dayString(from)
        let url = URL(string: "https://api.frankfurter.dev/v1/\(start)..?base=\(currency)&symbols=\(home)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        let series = try JSONDecoder().decode(Series.self, from: data)

        let existing = Set(try context.fetch(FetchDescriptor<FXRate>()).map(\.key))
        for (day, values) in series.rates {
            guard let aud = values[home] else { continue }
            let key = rateKey(currency, home, day)
            if !existing.contains(key) {
                context.insert(FXRate(key: key, rate: Decimal(string: String(aud)) ?? Decimal(aud)))
            }
        }
    }

    /// Rate for that day, or the most recent earlier day (weekends, holidays,
    /// and today before the ECB publishes).
    private struct Latest: Decodable { let rates: [String: Double] }

    /// Today's rate, for converting settings like the budget.
    static func latestRate(from: String, to: String) async throws -> Double? {
        let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=\(from)&symbols=\(to)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Latest.self, from: data).rates[to]
    }

    /// Old keys ("SGD-2026-09-18") were always to AUD; keep reading them.
    private static func rateKey(_ from: String, _ to: String, _ day: String) -> String {
        to == "AUD" ? "\(from)-\(day)" : "\(from)>\(to)-\(day)"
    }

    private static func rate(currency: String, to home: String, on date: Date, in context: ModelContext) throws -> Decimal? {
        for back in 0..<7 {
            let key = rateKey(currency, home, dayString(date.addingTimeInterval(Double(-back) * 86400)))
            let hit = try context.fetch(FetchDescriptor<FXRate>(predicate: #Predicate { $0.key == key }))
            if let r = hit.first { return r.rate }
        }
        return nil
    }
}

extension Decimal {
    func rounded(_ places: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, places, .plain)
        return result
    }
}
