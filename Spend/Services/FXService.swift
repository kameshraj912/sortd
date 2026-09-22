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

    /// What a backfill did, for "Update Exchange Rates".
    enum Outcome: Equatable {
        case nothingToDo
        case updated(Int)
        /// Some purchases still have no value (offline, service down).
        case failed(offline: Bool)

        var text: String {
            switch self {
            case .nothingToDo: "Rates are up to date."
            case .updated(let n): "Updated \(n) \(n == 1 ? "purchase" : "purchases")."
            case .failed(let offline): offline ? "You're offline. Rates update when you're back online." : "Couldn't get today's rates. Try again later."
            }
        }
    }

    /// A backfill already running. Launch, a Gmail sync and an import can
    /// all ask at once; they share one pass instead of racing each other.
    private static var running: Task<Outcome, Never>?

    /// Converts every purchase still missing a home-currency value. Safe to call often.
    @discardableResult
    static func backfill(in context: ModelContext) async -> Outcome {
        if let running {
            let first = await running.value
            // New purchases may have come in while that pass ran.
            let again = await backfill(in: context)
            return again == .nothingToDo ? first : again
        }
        // Clears itself before finishing, so a waiter never sees a done task.
        let task = Task {
            let out = await backfillPass(in: context)
            running = nil
            return out
        }
        running = task
        return await task.value
    }

    /// Last time rates were downloaded for a pair, so a rate from a day
    /// or two back isn't downloaded again every time the app opens.
    private static func fetchedKey(_ from: String, _ to: String) -> String { "fxFetched-\(from)>\(to)" }
    static let refetchAfter: TimeInterval = 6 * 3600

    private static func backfillPass(in context: ModelContext) async -> Outcome {
        let span = Perf.begin("fx.backfill")
        var converted = 0
        var failure: Error?
        do {
            let pending = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.audAmount == nil }))
            guard !pending.isEmpty else { span.end("nothing"); return .nothingToDo }

            let home = Money.home
            var cached = try loadRates(in: context)
            for (currency, txns) in Dictionary(grouping: pending, by: \.currencyCode) {
                if currency == home {
                    for t in txns { t.audAmount = t.amount }
                    converted += txns.count
                    continue
                }
                guard let earliest = txns.map(\.date).min() else { continue }
                // Download only when a day is missing, or the look-back rates
                // we'd use are older than the last download allows.
                let lastFetch = UserDefaults.standard.object(forKey: fetchedKey(currency, home)) as? Date
                let recent = lastFetch.map { Date.now.timeIntervalSince($0) < refetchAfter } ?? false
                let needsFetch = txns.contains { t in
                    exactRate(currency, home, t.date, cached) == nil && !(recent && rate(currency, home, t.date, cached) != nil)
                }
                if needsFetch {
                    do {
                        // Start a few days early so a Monday purchase can use Friday's rate.
                        try await fetchRates(currency: currency, to: home, from: earliest.addingTimeInterval(-5 * 86400), in: context)
                        UserDefaults.standard.set(Date.now, forKey: fetchedKey(currency, home))
                        cached = try loadRates(in: context)
                    } catch {
                        // Offline: convert what the saved rates allow, try the rest later.
                        failure = error
                    }
                }
                // Home currency changed while waiting: these rates are for the old one.
                guard Money.home == home else { span.end("home changed"); return .nothingToDo }
                // Purchases deleted while the rates were downloading.
                for t in txns where !t.isDeleted && t.modelContext != nil {
                    if let r = rate(currency, home, t.date, cached) {
                        t.audAmount = (t.amount * r).rounded(2)
                        converted += 1
                    }
                }
            }
            try context.save()
        } catch {
            failure = error
        }
        span.end("\(converted) converted")
        if let failure {
            log.error("FX backfill failed: \(failure.localizedDescription)")
            let offline = (failure as? URLError).map { [.notConnectedToInternet, .networkConnectionLost, .timedOut, .dataNotAllowed].contains($0.code) } ?? false
            return .failed(offline: offline)
        }
        return converted == 0 ? .nothingToDo : .updated(converted)
    }

    /// Every saved rate by key, read once per pass (not up to 7 queries per purchase).
    private static func loadRates(in context: ModelContext) throws -> [String: Decimal] {
        Dictionary(try context.fetch(FetchDescriptor<FXRate>()).map { ($0.key, $0.rate) }, uniquingKeysWith: { a, _ in a })
    }

    private static func exactRate(_ currency: String, _ home: String, _ date: Date, _ rates: [String: Decimal]) -> Decimal? {
        rates[rateKey(currency, home, dayString(date))]
    }

    private static func rate(_ currency: String, _ home: String, _ date: Date, _ rates: [String: Decimal]) -> Decimal? {
        for back in 0..<7 {
            if let r = rates[rateKey(currency, home, dayString(date.addingTimeInterval(Double(-back) * 86400)))] { return r }
        }
        return nil
    }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        // Rates are a nice-to-have: never hold anything up for a minute.
        req.timeoutInterval = 15
        return req
    }

    private static func fetchRates(currency: String, to home: String, from: Date, in context: ModelContext) async throws {
        let span = Perf.begin("fx.fetch")
        defer { span.end(currency) }
        let start = dayString(from)
        let url = URL(string: "https://api.frankfurter.dev/v1/\(start)..?base=\(currency)&symbols=\(home)")!
        let (data, response) = try await URLSession.shared.data(for: request(url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
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
        let (data, _) = try await URLSession.shared.data(for: request(url))
        return try JSONDecoder().decode(Latest.self, from: data).rates[to]
    }

    /// Old keys ("SGD-2026-09-18") were always to AUD; keep reading them.
    private static func rateKey(_ from: String, _ to: String, _ day: String) -> String {
        to == "AUD" ? "\(from)-\(day)" : "\(from)>\(to)-\(day)"
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
