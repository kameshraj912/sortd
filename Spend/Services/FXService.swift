import Foundation
import SwiftData

/// Fills in `audAmount` for non-AUD purchases using daily ECB rates from
/// frankfurter.dev (free, no key). Rates are cached, so each day is fetched once.
enum FXService {
    private struct Series: Decodable {
        let rates: [String: [String: Double]]
    }

    /// "2026-09-18" in the phone's own time zone, always Gregorian: it goes
    /// into Frankfurter's URL and the saved rate keys (`DayKey`).
    static func dayString(_ date: Date, calendar: Calendar = DayKey.calendar) -> String {
        DayKey.string(date, calendar: calendar)
    }

    /// Home currency changed: forget converted values, then convert again.
    /// The currency `audAmount` values are currently in.
    static let convertedKey = "convertedTo"

    static let budgetKey = "monthlyBudget"

    /// Where today's rate comes from. Tests pass their own.
    typealias RateSource = (_ from: String, _ to: String) async throws -> Double?

    /// Safety net: if the saved values were converted for a different
    /// currency than the current home one, convert them again.
    static func ensureConverted(in context: ModelContext, defaults: UserDefaults = .standard,
                                rate: @escaping RateSource = FXService.latestRate(from:to:)) async {
        let home = defaults.string(forKey: Money.homeKey) ?? Money.detectedHome
        guard defaults.string(forKey: convertedKey) != home else { return }
        await rebase(to: home, in: context, defaults: defaults, rate: rate)
    }

    /// The rebase running now (or queued last), so two callers never convert
    /// the budget twice: app-open's `ensureConverted` and the Settings picker
    /// can both fire while the rate is still downloading.
    private static var rebasing: (home: String, defaults: UserDefaults, task: Task<Void, Never>)?

    /// Home currency changed. One at a time: a call for the currency already
    /// on its way waits for that one; any other waits its turn, then reads
    /// what the last one left.
    static func rebase(to home: String, in context: ModelContext, defaults: UserDefaults = .standard,
                       rate: @escaping RateSource = FXService.latestRate(from:to:)) async {
        if let running = rebasing, running.home == home, running.defaults === defaults {
            await running.task.value
            return
        }
        let previous = rebasing?.task
        let task = Task {
            await previous?.value
            await rebaseNow(to: home, in: context, defaults: defaults, rate: rate)
        }
        rebasing = (home, defaults, task)
        await task.value
        if rebasing?.task == task { rebasing = nil }
    }

    private static func rebaseNow(to home: String, in context: ModelContext, defaults: UserDefaults,
                                  rate: RateSource) async {
        // Read everything before waiting on the network.
        let old = defaults.string(forKey: convertedKey)
            ?? defaults.string(forKey: Money.homeKey) ?? Money.detectedHome
        let budget = defaults.double(forKey: budgetKey)
        let limits = CategoryBudgets.stored(defaults)

        // The budget and category limits were set in the old currency.
        // Offline, leave them (and `convertedKey`) as they are so the next
        // `ensureConverted` tries again, rather than keep a SGD 1,000 budget
        // as USD 1,000 for good.
        var settingsDone = old == home || (budget <= 0 && limits.isEmpty)
        if !settingsDone, let r = try? await rate(old, home), r > 0 {
            // Changed while the rate loaded: typed in the new currency already.
            if budget > 0, defaults.double(forKey: budgetKey) == budget {
                defaults.set(convertSetting(budget, rate: r), forKey: budgetKey)
            }
            CategoryBudgets.convert(from: limits, rate: r, defaults)
            settingsDone = true
        }

        defaults.set(home, forKey: Money.homeKey)
        if settingsDone { defaults.set(home, forKey: convertedKey) }
        for t in (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] {
            t.audAmount = t.currencyCode == home ? t.amount : nil
        }
        context.saveReporting(where: "FXService.rebase")
        await backfill(in: context)
    }

    /// A budget or limit in the new currency, rounded to the cent. Rounding
    /// to the nearest 10 made S$1,000 → USD → SGD come back as S$990.
    static func convertSetting(_ value: Double, rate: Double) -> Double {
        let converted = value * rate
        guard converted.isFinite, converted > 0 else { return 0 }
        return max(0.01, (converted * 100).rounded() / 100)
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

    /// A backfill already running. Launch, a refresh and an import can
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
            let home = Money.home
            var cached = try loadRates(in: context)

            // A purchase whose date was corrected still holds the value from
            // the old day. When that day's rate is already saved, re-rate it
            // now; if it isn't, the value is cleared below so it is fetched.
            converted += reRateMovedPurchases(home: home, rates: cached, in: context)

            let pending = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.audAmount == nil }))
            guard !pending.isEmpty else {
                if converted > 0 { try context.save() }
                span.end(converted == 0 ? "nothing" : "\(converted) re-rated")
                return converted == 0 ? .nothingToDo : .updated(converted)
            }

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
            if !Connectivity.isNetworkDown(failure) { ErrorLog.report(failure, where: "FXService.backfill") }
            return .failed(offline: offline)
        }
        return converted == 0 ? .nothingToDo : .updated(converted)
    }

    /// Foreign purchases whose saved value no longer matches the rate for their
    /// own day (the date was edited). Only an exact-day rate counts, so a value
    /// that used a weekend's earlier rate is not flipped back and forth.
    /// Returns how many were changed.
    private static func reRateMovedPurchases(home: String, rates: [String: Decimal],
                                             in context: ModelContext) -> Int {
        let converted = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate {
            $0.audAmount != nil && $0.currencyCode != home
        }))) ?? []
        var changed = 0
        for t in converted where !t.isDeleted && t.modelContext != nil {
            // A foreign tap that met its statement line holds what the bank
            // charged (Deduper's cross-currency merge); keep it.
            if t.seenIn.count > 1, t.seenIn.contains(.csv) { continue }
            guard let r = exactRate(t.currencyCode, home, t.date, rates) else { continue }
            let value = (t.amount * r).rounded(2)
            if t.audAmount != value { t.audAmount = value; changed += 1 }
        }
        return changed
    }

    /// `amount` in `currency` as home-currency money, from the rates already
    /// saved on this phone (the day's, or the nearest earlier day within a
    /// week). Never goes to the network. Nil when the currency is the home one
    /// or no saved rate is close enough.
    static func homeValue(of amount: Decimal, currency: String, on date: Date,
                          in context: ModelContext) -> Decimal? {
        let home = Money.home
        guard currency != home else { return nil }
        let keys = (0..<7).map { rateKey(currency, home, dayString(date.addingTimeInterval(Double(-$0) * 86400))) }
        guard let saved = try? context.fetch(FetchDescriptor<FXRate>(predicate: #Predicate { keys.contains($0.key) })) else { return nil }
        let byKey = Dictionary(saved.map { ($0.key, $0.rate) }, uniquingKeysWith: { a, _ in a })
        for key in keys { if let r = byKey[key], r > 0 { return (amount * r).rounded(2) } }
        return nil
    }

    /// The key a saved rate is stored under.
    static func savedRateKey(from: String, to: String, on date: Date) -> String {
        rateKey(from, to, dayString(date))
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
