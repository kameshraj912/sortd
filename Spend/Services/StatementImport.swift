import Foundation

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

    // MARK: - CSV

    /// Reads a bank CSV. Works with a header row or without one (NAB's
    /// export has no header), and with either a signed Amount column or
    /// separate Debit/Credit columns.
    static func rows(fromCSV text: String, dateOrder: DateOrder = .auto) -> [Row] {
        let grid = parseCSV(text)
        guard !grid.isEmpty else { return [] }

        let layout = layout(for: grid)
        guard let dateColumn = layout.date, layout.hasAmount else { return [] }

        let body = layout.headerRow.map { Array(grid.dropFirst($0 + 1)) } ?? grid
        let order = dateOrder == .auto
            ? detectOrder(in: body.compactMap { $0.indices.contains(dateColumn) ? $0[dateColumn] : nil })
            : dateOrder

        var out: [Row] = []
        for fields in body {
            guard fields.indices.contains(dateColumn),
                  let date = parseDate(fields[dateColumn], order: order) else { continue }
            guard let money = money(in: fields, layout: layout) else { continue }

            let detail = layout.detail.flatMap { fields.indices.contains($0) ? fields[$0] : nil }
                ?? longestText(in: fields, skipping: [dateColumn])
            let clean = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }

            out.append(Row(date: date, detail: clean, amount: money.amount,
                           currency: money.currency, kind: money.kind,
                           raw: fields.joined(separator: " ")))
        }
        return out
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
                if found.date == nil, matches(key, ["date", "posted", "posting", "value date", "transaction date"]) {
                    found.date = j
                } else if found.debit == nil, matches(key, ["debit", "withdrawal", "money out", "paid out", "spent"]) {
                    found.debit = j
                } else if found.credit == nil, matches(key, ["credit", "deposit", "money in", "paid in", "received"]) {
                    found.credit = j
                } else if found.balance == nil, matches(key, ["balance"]) {
                    found.balance = j
                } else if found.amount == nil, matches(key, ["amount", "value", "transaction amount"]) {
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
                if parseDate(trimmed, order: .dayFirst) != nil { dateHits[j] += 1 }
                if signedAmount(trimmed) != nil { moneyHits[j] += 1 }
                if signedAmount(trimmed) == nil, parseDate(trimmed, order: .dayFirst) == nil {
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
        out.detail = textLength.enumerated().max { $0.element < $1.element }.flatMap { $0.element > 0 ? $0.offset : nil }
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
        // the money went, so the sign in the cell doesn't matter.
        if layout.debit != nil || layout.credit != nil {
            if let debit = cell(layout.debit), let parsed = signedAmount(debit) {
                return Money(amount: abs(parsed.amount), currency: parsed.currency, kind: .spend)
            }
            if let credit = cell(layout.credit), let parsed = signedAmount(credit) {
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
    static func rows(fromText text: String, dateOrder: DateOrder = .auto,
                     today: Date = .now) -> [Row] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let order = dateOrder == .auto ? detectOrder(in: lines) : dateOrder

        var out: [Row] = []
        for line in lines {
            guard let (date, dateRange) = firstDate(in: line, order: order, today: today) else { continue }

            // Take the date out before looking for money, or "01/09/2026"
            // donates a "2026" that reads perfectly well as an amount.
            var rest = line
            rest.replaceSubrange(dateRange, with: " ")

            guard let money = lastAmount(in: rest) else { continue }
            guard let detail = detail(in: rest, without: money.range) else { continue }

            out.append(Row(date: date, detail: detail, amount: abs(money.amount),
                           currency: money.currency,
                           kind: money.isCredit ? .moneyIn : .spend, raw: line))
        }
        return out
    }

    private static func detail(in line: String, without range: Range<String.Index>) -> String? {
        var text = line
        text.replaceSubrange(range, with: " ")
        let clean = text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—|\t"))
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

    /// Parses one date cell. Handles 01/09/2026, 2026-09-01, 1 Sep 2026,
    /// Sep 1 2026 and two-digit years.
    static func parseDate(_ text: String, order: DateOrder, today: Date = .now) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let (date, _) = firstDate(in: trimmed, order: order, today: today) else { return nil }
        return date
    }

    private static let monthNames: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    private static func firstDate(in line: String, order: DateOrder,
                                  today: Date = .now) -> (Date, Range<String.Index>)? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        // [0-9], not \d: \d also matches full-width (１２) and Arabic (١٢)
        // digits, which Int() can't read, and the unwraps below would trap.

        // yyyy-mm-dd — never ambiguous, so try it first.
        if let regex = try? NSRegularExpression(pattern: #"\b([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})\b"#),
           let m = regex.firstMatch(in: line, range: full) {
            let y = Int(ns.substring(with: m.range(at: 1)))!
            let mo = Int(ns.substring(with: m.range(at: 2)))!
            let d = Int(ns.substring(with: m.range(at: 3)))!
            if let date = make(year: y, month: mo, day: d), let r = Range(m.range, in: line) {
                return (date, r)
            }
        }

        // 1 Sep 2026 / 1 September 26 / Sep 1, 2026
        if let regex = try? NSRegularExpression(
            pattern: #"\b([0-9]{1,2})\s+([A-Za-z]{3,9})\.?\s*([0-9]{2,4})?\b"#, options: .caseInsensitive),
           let m = regex.firstMatch(in: line, range: full),
           let month = month(ns.substring(with: m.range(at: 2))) {
            let d = Int(ns.substring(with: m.range(at: 1)))!
            let y = m.range(at: 3).location == NSNotFound
                ? Calendar.current.component(.year, from: today)
                : year(Int(ns.substring(with: m.range(at: 3)))!)
            if let date = make(year: y, month: month, day: d), let r = Range(m.range, in: line) {
                return (date, r)
            }
        }
        if let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z]{3,9})\.?\s+([0-9]{1,2})(?:,)?\s*([0-9]{2,4})?\b"#, options: .caseInsensitive),
           let m = regex.firstMatch(in: line, range: full),
           let month = month(ns.substring(with: m.range(at: 1))) {
            let d = Int(ns.substring(with: m.range(at: 2)))!
            let y = m.range(at: 3).location == NSNotFound
                ? Calendar.current.component(.year, from: today)
                : year(Int(ns.substring(with: m.range(at: 3)))!)
            if let date = make(year: y, month: month, day: d), let r = Range(m.range, in: line) {
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
            if let date = make(year: y, month: month, day: day), let r = Range(m.range, in: line) {
                return (date, r)
            }
        }

        return nil
    }

    private static func month(_ name: String) -> Int? {
        monthNames[String(name.lowercased().prefix(4))] ?? monthNames[String(name.lowercased().prefix(3))]
    }

    /// 26 → 2026, 99 → 1999. Statements are never a century old.
    private static func year(_ value: Int) -> Int {
        value >= 100 ? value : (value <= 69 ? 2000 + value : 1900 + value)
    }

    private static func make(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), year >= 1900, year <= 2200 else { return nil }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        guard let date = Calendar.current.date(from: c) else { return nil }
        // Reject 31 February and friends, which Calendar would roll forward.
        let back = Calendar.current.dateComponents([.year, .month, .day], from: date)
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
    static func lastAmount(in line: String) -> Amount? {
        let pattern = #"(?<![\w.])(?<open>\()?\s*(?<sign>[-+])?\s*(?<sym>A\$|S\$|US\$|NZ\$|RM|₹|£|€|\$)?\s*(?<whole>\d{1,3}(?:,\d{3})+|\d+)(?:\.(?<cents>\d{2}))?\s*(?<close>\))?\s*(?<suffix>CR|DR|-)?(?![\w])"#
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
        let money = matches.filter { has($0, "cents") || has($0, "sym") || has($0, "sign") }
        let best = money.first ?? matches.last!

        func group(_ name: String) -> String? {
            let r = best.range(withName: name)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        let whole = (group("whole") ?? "0").replacingOccurrences(of: ",", with: "")
        let cents = group("cents") ?? "00"
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Must be money and nothing else, or a description column with a
        // house number in it would be read as an amount.
        let pattern = #"^\(?\s*-?\s*(A\$|S\$|US\$|NZ\$|RM|₹|£|€|\$)?\s*-?\s*(\d{1,3}(?:,\d{3})*|\d+)(?:\.(\d{1,2}))?\s*\)?\s*(CR|DR)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = trimmed as NSString
        guard let m = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else { return nil }

        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let whole = (group(2) ?? "0").replacingOccurrences(of: ",", with: "")
        let cents = group(3).map { $0.count == 1 ? $0 + "0" : $0 } ?? "00"
        guard var value = Decimal(string: "\(whole).\(cents)") else { return nil }

        let negative = trimmed.contains("-") || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
        let suffix = group(4)?.uppercased()
        if negative || suffix == "DR" { value = -value }
        if suffix == "CR" { value = abs(value) }
        return (value, currency(for: group(1)))
    }

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
