import Foundation
import SwiftData

/// Reads a bank statement and finds the purchases in it.
///
/// Three ways in, one way out:
///   * a CSV exported from a bank        → `rows(fromCSV:)`
///   * a PDF statement                   → text, then `rows(fromText:)`
///   * a screenshot of a bank app        → Vision OCR, then `rows(fromText:)`
///
/// All three produce the same `Row`s, which the user ticks off before
/// anything is saved. Nothing is uploaded and the file is not kept: Sortd
/// reads it, shows you what it found, and forgets it.
///
/// The two things that quietly ruin a statement importer, both handled here:
///
/// 1. **Money in is not spending.** A refund, salary or transfer in must not
///    be counted as a purchase. Banks disagree about how to say which is
///    which — a signed amount column, or separate Debit and Credit columns —
///    so both are read, and money in is kept separate.
/// 2. **01/02/2026 is ambiguous.** Day-first in Australia and Singapore,
///    month-first in the US. Guessing per line gives you a statement half in
///    each. The order is decided once for the whole file, from whichever
///    lines are unambiguous.
nonisolated enum StatementImport {

    /// One line of a statement, before the user has confirmed it.
    struct Row: Identifiable, Hashable, Sendable {
        var id = UUID()
        var date: Date
        var detail: String
        /// Always positive. `kind` says which way the money went.
        var amount: Decimal
        var currency: String?
        var kind: Kind
        /// The original line, shown if the user wants to check.
        var raw: String
    }

    enum Kind: Hashable, Sendable {
        /// A purchase.
        case spend
        /// A refund, deposit, salary or transfer in. Never counted as spending.
        case moneyIn
    }

    /// Which way round a d/m/y date is written.
    enum DateOrder: Hashable, Sendable {
        case dayFirst, monthFirst
        /// Work it out from the file.
        case auto
    }

    /// What reading a statement found, and how many lines it could not read.
    /// A line that is dropped without a word is lost money, so the screen
    /// shows `skipped` ("3 rows couldn't be read").
    struct Parsed: Sendable {
        var rows: [Row]
        /// Lines that look like purchases (a CSV row, or a line with a date)
        /// but had no readable date, amount or description.
        var skipped: Int
    }

    /// "3 rows couldn't be read." for the screen; nil when nothing was skipped.
    static func skippedNote(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 row couldn't be read." : "\(count) rows couldn't be read."
    }

    // MARK: - Choosing the reader

    /// Which reader a file goes to.
    enum Reader: Equatable, Sendable { case csv, text }

    /// CSV or free text? A scanned page or photo is always text. Otherwise a
    /// CSV has the same number of separators on most lines, and text pulled
    /// out of a PDF does not. The first line is not trusted: some exports put
    /// an account line ("Account,NAB Classic ...") above the header, so a
    /// run of matching lines starting at any of the first five lines counts.
    static func reader(for text: String, wasScanned: Bool = false) -> Reader {
        if wasScanned { return .text }
        let lines = text.split(whereSeparator: \.isNewline)
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .prefix(10)
        let counts = lines.map { line in
            max(line.filter { $0 == "," }.count,
                max(line.filter { $0 == ";" }.count, line.filter { $0 == "\t" }.count))
        }
        for start in 0..<min(5, max(0, counts.count - 1)) {
            let run = counts[start...]
            let reference = run.first ?? 0
            guard reference >= 2, run.count >= 2 else { continue }
            if run.filter({ $0 == reference }).count >= run.count - 1 { return .csv }
        }
        return .text
    }

    /// Reads a file with the reader `reader(for:wasScanned:)` picks. This is
    /// what the import screen runs.
    static func parse(statement text: String, wasScanned: Bool = false,
                      dateOrder: DateOrder = .auto) -> Parsed {
        switch reader(for: text, wasScanned: wasScanned) {
        case .csv: parse(csv: text, dateOrder: dateOrder)
        case .text: parse(text: text, dateOrder: dateOrder)
        }
    }

    // MARK: - CSV

    /// Reads a bank CSV. Works with a header row or without one (NAB's
    /// export has no header), and with either a signed Amount column or
    /// separate Debit/Credit columns.
    static func rows(fromCSV text: String, dateOrder: DateOrder = .auto,
                     calendar: Calendar = DayKey.calendar) -> [Row] {
        parse(csv: text, dateOrder: dateOrder, calendar: calendar).rows
    }

    /// Like `rows(fromCSV:)`, and counts the rows it could not read.
    static func parse(csv text: String, dateOrder: DateOrder = .auto,
                      calendar: Calendar = DayKey.calendar) -> Parsed {
        let grid = parseCSV(text)
        guard !grid.isEmpty else { return Parsed(rows: [], skipped: 0) }

        let layout = layout(for: grid)
        // No date or amount column: nothing in the file could be read.
        guard let dateColumn = layout.date, layout.hasAmount else {
            return Parsed(rows: [], skipped: grid.count)
        }

        let body = layout.headerRow.map { Array(grid.dropFirst($0 + 1)) } ?? grid
        let order = dateOrder == .auto
            ? detectOrder(in: body.compactMap { $0.indices.contains(dateColumn) ? $0[dateColumn] : nil })
            : dateOrder

        var out: [Row] = []
        var skipped = 0
        for fields in body {
            guard fields.indices.contains(dateColumn),
                  let date = parseDate(fields[dateColumn], order: order, calendar: calendar),
                  let money = money(in: fields, layout: layout) else { skipped += 1; continue }

            let detail = layout.detail.flatMap { fields.indices.contains($0) ? fields[$0] : nil }
                ?? longestText(in: fields, skipping: [dateColumn])
            let clean = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { skipped += 1; continue }

            out.append(Row(date: date, detail: clean, amount: money.amount,
                           currency: money.currency, kind: money.kind,
                           raw: fields.joined(separator: " ")))
        }
        return Parsed(rows: out, skipped: skipped)
    }

    /// Where the interesting columns are.
    private struct Layout {
        var headerRow: Int?
        var date: Int?
        var detail: Int?
        var amount: Int?
        var debit: Int?
        var credit: Int?
        var balance: Int?
        var hasAmount: Bool { amount != nil || debit != nil || credit != nil }
    }

    private static func layout(for grid: [[String]]) -> Layout {
        var out = Layout()

        // A header row names its columns. Look at the first few rows only:
        // some exports put the account name and a blank line on top.
        for (i, row) in grid.prefix(5).enumerated() {
            var found = Layout()
            for (j, cell) in row.enumerated() {
                let key = cell.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                if found.date == nil, matches(key, ["date", "posted", "posting", "value date", "transaction date",
                                                       "time", "timestamp", "settled"]) {
                    found.date = j
                } else if found.debit == nil, matches(key, ["debit", "withdrawal", "money out", "paid out", "spent"]) {
                    found.debit = j
                } else if found.credit == nil, matches(key, ["credit", "deposit", "money in", "paid in", "received"]) {
                    found.credit = j
                } else if found.balance == nil, matches(key, ["balance"]) {
                    found.balance = j
                } else if found.amount == nil, matches(key, ["amount", "value", "total", "transaction amount"]),
                          !key.contains("round up"), !key.contains("roundup") {
                    found.amount = j
                } else if found.detail == nil, matches(key, ["description", "details", "narrative", "merchant",
                                                            "particulars", "reference", "transaction", "payee", "name"]) {
                    found.detail = j
                }
            }
            if found.date != nil && found.hasAmount {
                found.headerRow = i
                return found
            }
        }

        // No header. Work the columns out from what's in them.
        let sample = Array(grid.prefix(30))
        let width = sample.map(\.count).max() ?? 0
        guard width > 0 else { return out }

        var dateHits = [Int](repeating: 0, count: width)
        var moneyHits = [Int](repeating: 0, count: width)
        var textLength = [Int](repeating: 0, count: width)

        for row in sample {
            for (j, cell) in row.enumerated() where j < width {
                let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                // A date column holds only dates. A description that mentions
                // one ("... Value Date: 30/08/2026") is still text.
                let isDate = isWholeDate(trimmed)
                let isMoney = signedAmount(trimmed) != nil
                if isDate { dateHits[j] += 1 }
                if isMoney { moneyHits[j] += 1 }
                if !isMoney, !isDate {
                    textLength[j] += trimmed.count
                }
            }
        }

        out.date = dateHits.enumerated().max { $0.element < $1.element }.flatMap { $0.element > 0 ? $0.offset : nil }
        // The first money column is the transaction; a later one is usually
        // the running balance, which must not be imported as a purchase.
        let moneyColumns = moneyHits.enumerated().filter { $0.element > 0 }.map(\.offset)
        out.amount = moneyColumns.first
        if moneyColumns.count > 1 { out.balance = moneyColumns.last }
        // The shop is text: never the date, the amount or the balance.
        let taken = Set([out.date, out.amount, out.balance].compactMap { $0 })
        out.detail = textLength.enumerated().filter { !taken.contains($0.offset) }
            .max { $0.element < $1.element }.flatMap { $0.element > 0 ? $0.offset : nil }
        return out
    }

    private static func matches(_ key: String, _ options: [String]) -> Bool {
        options.contains { key == $0 || key.contains($0) }
    }

    private struct Money {
        var amount: Decimal
        var currency: String?
        var kind: Kind
    }

    private static func money(in fields: [String], layout: Layout) -> Money? {
        func cell(_ index: Int?) -> String? {
            guard let index, fields.indices.contains(index) else { return nil }
            let t = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        // Separate Debit / Credit columns: whichever is filled says which way
        // the money went, so the sign in the cell doesn't matter. Some banks
        // fill the unused one with "0.00": that is empty, not a $0 purchase.
        if layout.debit != nil || layout.credit != nil {
            if let debit = cell(layout.debit), let parsed = signedAmount(debit), parsed.amount != 0 {
                return Money(amount: abs(parsed.amount), currency: parsed.currency, kind: .spend)
            }
            if let credit = cell(layout.credit), let parsed = signedAmount(credit), parsed.amount != 0 {
                return Money(amount: abs(parsed.amount), currency: parsed.currency, kind: .moneyIn)
            }
            return nil
        }

        // One signed column: out is negative, in is positive.
        guard let raw = cell(layout.amount), let parsed = signedAmount(raw) else { return nil }
        return Money(amount: abs(parsed.amount), currency: parsed.currency,
                     kind: parsed.amount < 0 ? .spend : .moneyIn)
    }

    private static func longestText(in fields: [String], skipping: Set<Int>) -> String {
        fields.enumerated()
            .filter { !skipping.contains($0.offset) && signedAmount($0.element) == nil }
            .map(\.element)
            .max { $0.count < $1.count } ?? ""
    }

    // MARK: - Free text (PDF statements and screenshots)

    /// Finds statement lines in loose text: a date, some words, an amount.
    /// Anything without both a date and an amount is skipped, which throws
    /// away headers, page numbers and marketing without needing rules for
    /// each bank.
    /// Saves chosen rows through `TransactionLogger`. Only `.spend` rows are
    /// saved; a `.moneyIn` row is ignored. A row may match a
    /// purchase Sortd already had (the tap), but never another row from this
    /// same import: two identical lines are two purchases.
    /// One save at the end (and one every 50 rows, so a very long
    /// statement never holds much unsaved). `progress` hears rows done.
    @MainActor
    static func save(_ rows: [Row], card: Card, in context: ModelContext,
                     progress: (Int) -> Void = { _ in }) -> (added: Int, merged: Int) {
        let result = saveChecked(rows, card: card, in: context, progress: progress)
        return (result.added, result.merged)
    }

    /// `save`, and whether the final write reached disk. A failed write is in
    /// `ErrorLog`; the screen shows `.saveFailedAlert` when `saved` is false.
    @MainActor
    static func saveChecked(_ rows: [Row], card: Card, in context: ModelContext,
                            progress: (Int) -> Void = { _ in }) -> (added: Int, merged: Int, saved: Bool) {
        let span = Perf.begin("statement.save")
        var added = 0, merged = 0
        var touched: Set<UUID> = []
        let learned = (try? TransactionLogger.learnedRules(in: context)) ?? [:]
        for (i, row) in rows.enumerated() {
            // Money in (salary, a refund, a transfer) is not spending, whoever
            // calls this. The review screen already filters; this keeps the
            // rule in one place that every caller passes through.
            guard row.kind == .spend else { progress(i + 1); continue }
            let purchase = IncomingPurchase(date: row.date, merchant: row.detail, amount: row.amount,
                                            currency: row.currency ?? Spend.Money.home, card: card, source: .csv)
            do {
                let outcome = try TransactionLogger.log(purchase, in: context, excluding: touched,
                                                        learned: learned, save: false)
                touched.insert(outcome.transaction.id)
                switch outcome {
                case .added: added += 1
                case .merged: merged += 1
                }
            } catch {
                ErrorLog.report(error, where: "StatementImport.log")
            }
            if (i + 1) % 50 == 0 { context.saveReporting(where: "StatementImport.save") }
            progress(i + 1)
        }
        let saved = context.saveReporting(where: "StatementImport.save")
        span.end("\(rows.count) rows")
        return (added, merged, saved)
    }

    static func rows(fromText text: String, dateOrder: DateOrder = .auto,
                     today: Date = .now, calendar: Calendar = DayKey.calendar) -> [Row] {
        parse(text: text, dateOrder: dateOrder, today: today, calendar: calendar).rows
    }

    /// Like `rows(fromText:)`, and counts the lines that carried a date but
    /// had no readable amount or description. Lines with no date (headers,
    /// page numbers, marketing) are not statement lines and are not counted.
    static func parse(text: String, dateOrder: DateOrder = .auto,
                      today: Date = .now, calendar: Calendar = DayKey.calendar) -> Parsed {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let order = dateOrder == .auto ? detectOrder(in: lines) : dateOrder

        var out: [Row] = []
        var skipped = 0
        for line in lines {
            guard let (date, dateRange) = firstDate(in: line, order: order, today: today,
                                                    calendar: calendar) else { continue }

            // Take the date out before looking for money, or "01/09/2026"
            // donates a "2026" that reads perfectly well as an amount.
            var rest = line
            rest.replaceSubrange(dateRange, with: " ")

            guard let money = lastAmount(in: rest),
                  let detail = detail(in: rest, without: money.range) else { skipped += 1; continue }

            out.append(Row(date: date, detail: detail, amount: abs(money.amount),
                           currency: money.currency,
                           kind: money.isCredit ? .moneyIn : .spend, raw: line))
        }
        // No line had a date and an amount together: perhaps a screenshot
        // of a list that puts the day on a line of its own.
        if out.isEmpty {
            let grouped = groupedByDay(lines, order: order, today: today, calendar: calendar)
            if !grouped.rows.isEmpty { return grouped }
        }
        return Parsed(rows: out, skipped: skipped)
    }

    /// Wallet's card list and most bank apps don't print the date on the
    /// purchase's own line. Bank apps group purchases under a day header
    /// ("Fri 26 Sep"); Wallet writes the day under each purchase
    /// ("Yesterday", "Thursday", "26/09/2026"). Which of the two is decided
    /// once, from whichever comes first. Only tried when no line had both a
    /// date and an amount, so a PDF statement is never read this way.
    private static func groupedByDay(_ lines: [String], order: DateOrder, today: Date,
                                     calendar: Calendar) -> Parsed {
        enum Line { case day(Date), purchase(Row), other }
        let read: [Line] = lines.map { line in
            if let day = dayHeader(line, order: order, today: today, calendar: calendar) { return .day(day) }
            guard !isSummaryLine(line), let money = lastAmount(in: line),
                  let detail = detail(in: line, without: money.range) else { return .other }
            return .purchase(Row(date: today, detail: detail, amount: abs(money.amount), currency: money.currency,
                                 kind: money.isCredit ? .moneyIn : .spend, raw: line))
        }
        let headersFirst = read.lazy.compactMap { line -> Bool? in
            switch line {
            case .day: true
            case .purchase: false
            case .other: nil
            }
        }.first ?? true

        var out: [Row] = []
        var waiting: [Row] = []
        var current: Date?
        for line in read {
            switch line {
            case .day(let day):
                if headersFirst {
                    current = day
                } else {
                    out += waiting.map { var row = $0; row.date = day; return row }
                    waiting = []
                }
            case .purchase(var row):
                if !headersFirst {
                    waiting.append(row)
                } else if let current {
                    // Before the first header it is the balance or a banner.
                    row.date = current
                    out.append(row)
                }
            case .other:
                break
            }
        }
        // Purchases with no day under them were seen and not read: say so.
        return Parsed(rows: out, skipped: waiting.count)
    }

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// A line that is only a day: "Today", "Yesterday", "Thursday",
    /// "26/09/2026", "Fri 26 Sep". Noon that day.
    private static func dayHeader(_ line: String, order: DateOrder, today: Date, calendar: Calendar) -> Date? {
        let calendar = DayKey.gregorian(like: calendar)
        func noon(_ daysBack: Int) -> Date? {
            calendar.date(byAdding: .day, value: -daysBack, to: today)
                .flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) }
        }
        let word = line.lowercased().trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        if word == "today" { return noon(0) }
        if word == "yesterday" { return noon(1) }
        // Wallet names the day for the last week: the latest one before today.
        if let target = weekdays.firstIndex(of: word) {
            let back = (calendar.component(.weekday, from: today) - 1 - target + 7) % 7
            return noon(back == 0 ? 7 : back)
        }
        guard let (date, range) = firstDate(in: line, order: order, today: today, calendar: calendar) else { return nil }
        var rest = line
        rest.removeSubrange(range)
        // Nothing else but a weekday name ("Fri", "Friday,").
        guard !rest.contains(where: \.isNumber) else { return nil }
        let words = rest.lowercased().split { !$0.isLetter }.map(String.init)
        guard words.allSatisfy({ w in w.count >= 3 && weekdays.contains { $0.hasPrefix(w) } }) else { return nil }
        return date
    }

    /// A balance or total at the top of a bank app's screen, not a purchase.
    private static func isSummaryLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return ["balance", "available", "limit", "total", "owing"].contains { lower.contains($0) }
    }

    private static func detail(in line: String, without range: Range<String.Index>) -> String? {
        var text = line
        text.replaceSubrange(range, with: " ")
        let clean = text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—\u{2212}|\t"))
        // A line of pure punctuation isn't a merchant.
        guard clean.count >= 2, clean.contains(where: \.isLetter) else { return nil }
        return clean
    }

    // MARK: - Dates

    /// Decides day-first vs month-first once, from every date in the file.
    /// A 13+ in the first position proves day-first; in the second, month-first.
    /// With no proof either way, day-first: Sortd's markets write it that way.
    static func detectOrder(in lines: [String]) -> DateOrder {
        var dayFirst = 0
        var monthFirst = 0
        let pattern = #"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return .dayFirst }

        for line in lines {
            let ns = line as NSString
            for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let a = Int(ns.substring(with: match.range(at: 1))) ?? 0
                let b = Int(ns.substring(with: match.range(at: 2))) ?? 0
                if a > 12, b <= 12 { dayFirst += 1 }
                if b > 12, a <= 12 { monthFirst += 1 }
            }
        }
        if monthFirst > dayFirst { return .monthFirst }
        return .dayFirst
    }

    /// True when the whole cell is a date, with an optional time after it.
    /// "01/09/2026 12:30" and "2026-09-01T12:34:56+10:00" are dates; a
    /// description that merely contains one is not.
    static func isWholeDate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let (_, range) = firstDate(in: trimmed, order: .dayFirst) else { return false }
        var rest = trimmed
        rest.removeSubrange(range)
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty { return true }
        let time = #"^[Tt\s]*[0-9]{1,2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?\s*([AaPp][Mm])?\s*(Z|UTC|GMT|[+-][0-9]{2}(:?[0-9]{2})?)?$"#
        return rest.range(of: time, options: .regularExpression) != nil
    }

    /// Parses one date cell. Handles 01/09/2026, 2026-09-01, 2026-09-01T12:34:56+10:00,
    /// 1 Sep 2026, 01-Sep-2026, Sep 1 2026 and two-digit years.
    static func parseDate(_ text: String, order: DateOrder, today: Date = .now,
                          calendar: Calendar = DayKey.calendar) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let (date, _) = firstDate(in: trimmed, order: order, today: today, calendar: calendar) else { return nil }
        return date
    }

    private static let monthNames: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    private static func firstDate(in line: String, order: DateOrder, today: Date = .now,
                                  calendar: Calendar = DayKey.calendar) -> (Date, Range<String.Index>)? {
        // Statements print Gregorian years. On a Buddhist or Japanese phone
        // calendar, 2026 was read as 1483 or 4044 CE and a year-less line
        // took year 2569 and was dropped. Only the time zone is the phone's.
        let calendar = DayKey.gregorian(like: calendar)
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        // [0-9], not \d: \d also matches full-width (１２) and Arabic (١٢)
        // digits, which Int() can't read, and the unwraps below would trap.

        // yyyy-mm-dd — never ambiguous, so try it first. No \b at the ends:
        // an ISO 8601 stamp is "2026-09-01T12:34:56", and "01T" has no boundary.
        if let regex = try? NSRegularExpression(pattern: #"(?<![0-9])([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})(?![0-9])"#),
           let m = regex.firstMatch(in: line, range: full) {
            let y = Int(ns.substring(with: m.range(at: 1)))!
            let mo = Int(ns.substring(with: m.range(at: 2)))!
            let d = Int(ns.substring(with: m.range(at: 3)))!
            if let date = make(year: y, month: mo, day: d, calendar: calendar), let r = Range(m.range, in: line) {
                return (date, r)
            }
        }

        // d/m/y or m/d/y, decided by `order`.
        if let regex = try? NSRegularExpression(pattern: #"\b([0-9]{1,2})[/\-.]([0-9]{1,2})[/\-.]([0-9]{2,4})\b"#),
           let m = regex.firstMatch(in: line, range: full) {
            let a = Int(ns.substring(with: m.range(at: 1)))!
            let b = Int(ns.substring(with: m.range(at: 2)))!
            let y = year(Int(ns.substring(with: m.range(at: 3)))!)
            // Even in a month-first file, 25/12 can only be day-first.
            let dayFirst = order == .dayFirst ? a <= 31 : a > 12
            let day = dayFirst ? a : b
            let month = dayFirst ? b : a
            if let date = make(year: y, month: month, day: day, calendar: calendar), let r = Range(m.range, in: line) {
                return (date, r)
            }
        }

        // 1 Sep 2026 / 1 September 26 / 01-Sep-2026 / 01/Sep/2026 / Sep 1, 2026. After the numeric form, so
        // "03/09/2026 CAFE 12 MARKET ST" isn't read as 12 March.
        if let regex = try? NSRegularExpression(
            pattern: #"\b([0-9]{1,2})(?:\s+|[-/])([A-Za-z]{3,9})\.?(?:[\s\-/]+)?([0-9]{2,4})?\b"#, options: .caseInsensitive),
           let m = regex.firstMatch(in: line, range: full),
           let month = month(ns.substring(with: m.range(at: 2))) {
            let d = Int(ns.substring(with: m.range(at: 1)))!
            let noYear = m.range(at: 3).location == NSNotFound
            let y = noYear
                ? calendar.component(.year, from: today)
                : year(Int(ns.substring(with: m.range(at: 3)))!)
            if var date = make(year: y, month: month, day: d, calendar: calendar), let r = Range(m.range, in: line) {
                // "28 Dec" on a statement read in January is last December.
                if noYear, date > today.addingTimeInterval(86_400), let earlier = make(year: y - 1, month: month, day: d, calendar: calendar) {
                    date = earlier
                }
                return (date, r)
            }
        }
        if let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z]{3,9})\.?\s+([0-9]{1,2})(?:,)?\s*([0-9]{2,4})?\b"#, options: .caseInsensitive),
           let m = regex.firstMatch(in: line, range: full),
           let month = month(ns.substring(with: m.range(at: 1))) {
            let d = Int(ns.substring(with: m.range(at: 2)))!
            let noYear = m.range(at: 3).location == NSNotFound
            let y = noYear
                ? calendar.component(.year, from: today)
                : year(Int(ns.substring(with: m.range(at: 3)))!)
            if var date = make(year: y, month: month, day: d, calendar: calendar), let r = Range(m.range, in: line) {
                // "28 Dec" on a statement read in January is last December.
                if noYear, date > today.addingTimeInterval(86_400), let earlier = make(year: y - 1, month: month, day: d, calendar: calendar) {
                    date = earlier
                }
                return (date, r)
            }
        }

        return nil
    }

    private static let fullMonthNames = ["january", "february", "march", "april", "may", "june", "july",
                                         "august", "september", "october", "november", "december"]

    /// "Sep", "Sept" or "September" — the whole word, so MARKET, DECATHLON and
    /// JUNCTION aren't months.
    private static func month(_ name: String) -> Int? {
        let word = name.lowercased()
        if let n = monthNames[word] { return n }
        return fullMonthNames.firstIndex(of: word).map { $0 + 1 }
    }

    /// 26 → 2026, 99 → 1999. Statements are never a century old.
    private static func year(_ value: Int) -> Int {
        value >= 100 ? value : (value <= 69 ? 2000 + value : 1900 + value)
    }

    private static func make(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), year >= 1900, year <= 2200 else { return nil }
        let calendar = DayKey.gregorian(like: calendar)
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        guard let date = calendar.date(from: c) else { return nil }
        // Reject 31 February and friends, which Calendar would roll forward.
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return date
    }

    // MARK: - Amounts

    struct Amount {
        var amount: Decimal
        var currency: String?
        var isCredit: Bool
        var range: Range<String.Index>
    }

    /// The amount on a statement line. Bank apps and statements disagree
    /// about how to mark money in: `+200.00`, `200.00 CR`, or nothing at
    /// all. Money out shows up as `(12.50)`, `12.50-`, `12.50 DR` or `-12.50`.
    /// A line with no sign at all is spending — that is what a statement is
    /// mostly made of.
    ///
    /// Cents after a comma ("12,50", "1.234,50") are read the European way,
    /// tried first so "-12,50" is not cut to 12. That needs exactly two
    /// digits after the comma and nothing number-like after them, so
    /// "1,234.50" is still thousands. Indian lakh grouping ("1,23,456.00")
    /// is one number too, not ₹1.
    static func lastAmount(in line: String) -> Amount? {
        let european = #"(?<ewhole>\d{1,3}(?:\.\d{3})+|\d+),(?<ecents>\d{2})(?![\d]|[.,]\d)"#
        let plain = #"(?<whole>\d{1,3}(?:,\d{3})+|\d{1,2}(?:,\d{2})+,\d{3}|\d+)(?:\.(?<cents>\d{2}))?"#
        let pattern = #"(?<![\w.])(?<open>\()?\s*(?<sign>[-+\x{2212}])?\s*(?<sym>A\$|S\$|US\$|NZ\$|RM|₹|£|€|\$)?\s*(?:"#
            + european + "|" + plain + #")\s*(?<close>\))?\s*(?<suffix>CR|DR|-)?(?![\w])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }

        func has(_ m: NSTextCheckingResult, _ name: String) -> Bool {
            m.range(withName: name).location != NSNotFound
        }

        // Prefer a match with decimals, a currency symbol or a sign: on
        // "MCDONALDS 123 GEORGE ST 12.50" the street number isn't money.
        // When a line has two of those, the first is the purchase and the
        // later one is the running balance ("WOOLWORTHS 12.50 1,034.20").
        let money = matches.filter { has($0, "cents") || has($0, "ecents") || has($0, "sym") || has($0, "sign") }
        let best = money.first ?? matches.last!

        func group(_ name: String) -> String? {
            let r = best.range(withName: name)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        let whole = (group("whole") ?? group("ewhole") ?? "0").filter(\.isNumber)
        let cents = group("cents") ?? group("ecents") ?? "00"
        guard let value = Decimal(string: "\(whole).\(cents)") else { return nil }
        guard let range = Range(best.range, in: line) else { return nil }

        let bracketed = group("open") == "(" && group("close") == ")"
        let suffix = group("suffix")?.uppercased()
        let sign = group("sign")

        let isCredit: Bool
        if bracketed || suffix == "DR" || suffix == "-" {
            isCredit = false
        } else if suffix == "CR" || sign == "+" {
            isCredit = true
        } else {
            isCredit = false
        }

        return Amount(amount: value, currency: currency(for: group("sym")),
                      isCredit: isCredit, range: range)
    }

    /// A single cell that is only an amount, with its sign.
    static func signedAmount(_ text: String) -> (amount: Decimal, currency: String?)? {
        // Excel, Numbers and some locales write a true minus (U+2212); some
        // exports an en dash. Both mean the ASCII hyphen here.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
        guard !trimmed.isEmpty else { return nil }
        // Must be money and nothing else, or a description column with a
        // house number in it would be read as an amount. An ISO code may sit
        // before or after the number ("AUD -58.30", "12.00 SGD"). Cents after
        // a dot ("1,234.50"), or after a comma ("-12,50", "1.234,50"), the
        // European way, which is why `parseCSV` reads ";" files at all.
        // Indian lakh grouping ("1,23,456.00") is thousands too.
        let number = #"(?:(\d{1,3}(?:,\d{3})*|\d{1,2}(?:,\d{2})+,\d{3}|\d+)(?:\.(\d{1,2}))?|(\d{1,3}(?:\.\d{3})*|\d+),(\d{1,2}))"#
        let pattern = #"^\(?\s*[-+]?\s*(?:([A-Za-z]{3})\s*)?(A\$|S\$|US\$|NZ\$|RM|₹|£|€|\$)?\s*[-+]?\s*"# + number
            + #"\s*\)?\s*(CR|DR)?\s*([A-Za-z]{3})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = trimmed as NSString
        guard let m = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else { return nil }

        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        // Three letters that are not a real currency are words ("KFC 12").
        let codes = [group(1), group(8)].compactMap { $0?.uppercased() }
        guard codes.allSatisfy({ isoCurrencyCodes.contains($0) }), codes.count <= 1 else { return nil }
        let whole = (group(3) ?? group(5) ?? "0").filter(\.isNumber)
        let cents = (group(4) ?? group(6)).map { $0.count == 1 ? $0 + "0" : $0 } ?? "00"
        guard var value = Decimal(string: "\(whole).\(cents)") else { return nil }

        let negative = trimmed.contains("-") || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
        let suffix = group(7)?.uppercased()
        if negative || suffix == "DR" { value = -value }
        if suffix == "CR" { value = abs(value) }
        return (value, codes.first ?? currency(for: group(2)))
    }

    private static let isoCurrencyCodes = Set(Locale.commonISOCurrencyCodes)

    private static func currency(for symbol: String?) -> String? {
        switch symbol?.uppercased() {
        case "A$": "AUD"
        case "S$": "SGD"
        case "US$": "USD"
        case "NZ$": "NZD"
        case "RM": "MYR"
        case "₹": "INR"
        case "£": "GBP"
        case "€": "EUR"
        default: nil
        }
    }

    // MARK: - CSV splitting

    /// Splits CSV, honouring quotes and doubled quotes. Picks the delimiter
    /// from the first line: some banks in Europe use semicolons, and a tab
    /// export is common from spreadsheets.
    static func parseCSV(_ text: String) -> [[String]] {
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        guard let first = body.split(whereSeparator: \.isNewline).first else { return [] }
        let delimiter: Character = {
            let counts: [(Character, Int)] = [
                (",", first.filter { $0 == "," }.count),
                (";", first.filter { $0 == ";" }.count),
                ("\t", first.filter { $0 == "\t" }.count),
            ]
            return counts.max { $0.1 < $1.1 }?.0 ?? ","
        }()

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = body.makeIterator()
        var pending: Character?

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
                continue
            }
            switch ch {
            case "\"": inQuotes = true
            case delimiter:
                row.append(field); field = ""
            case "\n", "\r":
                if !field.isEmpty || !row.isEmpty {
                    row.append(field); rows.append(row); row = []; field = ""
                }
            default:
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }
}
