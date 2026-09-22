import Foundation

/// Turns whatever Shortcuts, an email or a CSV hands us ("A$4.50",
/// "S$1,234.00", "SGD 12.30", "4.5") into a number and, if it says, a currency.
enum AmountParser {
    struct Result: Equatable {
        var amount: Decimal
        var currency: String?
    }

    // Order matters: "US$" must be checked before "S$".
    private static let markers: [(String, String)] = [
        ("USD", "USD"), ("US$", "USD"),
        ("SGD", "SGD"), ("S$", "SGD"),
        ("AUD", "AUD"), ("AU$", "AUD"), ("A$", "AUD"),
        ("NZD", "NZD"), ("NZ$", "NZD"),
        ("HKD", "HKD"), ("HK$", "HKD"),
        ("CAD", "CAD"), ("C$", "CAD"),
        ("MYR", "MYR"), ("RM", "MYR"),
        ("INR", "INR"), ("₹", "INR"), ("RS.", "INR"),
        ("EUR", "EUR"), ("€", "EUR"),
        ("GBP", "GBP"), ("£", "GBP"),
        ("JPY", "JPY"), ("¥", "JPY"),
    ]

    private static let isoCodes = Set(Locale.commonISOCurrencyCodes)

    /// The currency the text names, if any: a known symbol, or any ISO code
    /// written on its own ("THB 120").
    static func currency(in text: String) -> String? {
        let upper = text.uppercased()
        if let m = markers.first(where: { upper.contains($0.0) }) { return m.1 }
        return upper.split(whereSeparator: { !$0.isLetter })
            .first { $0.count == 3 && isoCodes.contains(String($0)) }
            .map(String.init)
    }

    /// True when the text starts with a minus: money coming back (a refund).
    static func isNegative(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("-") || t.hasPrefix("−") || (t.hasPrefix("(") && t.hasSuffix(")"))
    }

    static func parse(_ text: String) -> Result? {
        let upper = text.uppercased()
        let currency = currency(in: text)

        // Keep digits, separators and a leading minus.
        var cleaned = upper.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard cleaned.contains(where: \.isNumber) else { return nil }

        // "1,234.56" → drop thousands commas. "4,50" (comma as decimal) →
        // "4.50". "1.234,50" (European: dot thousands, comma decimal) →
        // "1234.50" — whichever separator comes LAST is the decimal one;
        // the other (if any) is thousands grouping and gets dropped.
        let lastDot = cleaned.lastIndex(of: ".")
        let lastComma = cleaned.lastIndex(of: ",")
        switch (lastDot, lastComma) {
        case let (.some(dot), .some(comma)) where comma > dot:
            cleaned.removeAll { $0 == "." }
            if let c = cleaned.lastIndex(of: ",") {
                cleaned.replaceSubrange(c...c, with: ".")
            }
            cleaned.removeAll { $0 == "," }
        case (.some, .some):
            cleaned.removeAll { $0 == "," }
        case (nil, .some(let comma)) where cleaned.distance(from: comma, to: cleaned.endIndex) == 3:
            cleaned.replaceSubrange(comma...comma, with: ".")
            cleaned.removeAll { $0 == "," }
        default:
            cleaned.removeAll { $0 == "," }
        }

        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        // Spending is always stored positive.
        return Result(amount: abs(value), currency: currency)
    }

    private static func abs(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
}

/// Where Raj is decides the purchase currency. The phone sets its time zone
/// automatically, so Melbourne → AUD and Singapore → SGD with no input.
enum LocalCurrency {
    static func current(timeZone: TimeZone = .current) -> String {
        let id = timeZone.identifier
        if id.hasPrefix("Australia/") { return "AUD" }
        if id == "Asia/Singapore" { return "SGD" }
        if id == "Asia/Kuala_Lumpur" { return "MYR" }
        return Locale.current.currency?.identifier ?? "AUD"
    }
}

enum MerchantName {
    private static let prefixes = ["SQ *", "SQ*", "PAYPAL *", "PP*", "SP *", "SP*", "ZLR*", "LS ", "TST* ", "TST*",
                                   "SA_", "SMP_", "PADDLE.NET* ", "PADDLE.NET*", "TS/", "FP*", "DD *", "EB *", "EB*"]

    /// "SQ *CAFE BLOSSOM  MELBOURNE AU" → "Cafe Blossom"
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in prefixes where s.uppercased().hasPrefix(p) {
            s = String(s.dropFirst(p.count))
            break
        }
        // "Apple Music Individual (Monthly)", "MUJI RETAIL (AUSTRAL" (bank
        // descriptors are cut at ~20 characters): drop the bracketed tail.
        if let open = s.firstIndex(of: "("), s.distance(from: s.startIndex, to: open) >= 3 {
            s = String(s[..<open]).trimmingCharacters(in: .whitespaces)
        }
        // Drop trailing location / country codes, company suffixes and store numbers.
        let stopWords: Set<String> = ["AU", "AUS", "SG", "SGP", "MELBOURNE", "SINGAPORE", "VIC", "NSW",
                                      "PTY", "PTE", "LTD", "LT", "P", "-"]
        var words = s.split(separator: " ").map(String.init)
        while let last = words.last, words.count > 1,
              stopWords.contains(last.uppercased()) || last.allSatisfy({ $0.isNumber || $0 == "#" }) {
            words.removeLast()
        }
        s = words.joined(separator: " ")
        // Only re-case names that arrive SHOUTING; keep "McDonald's" as-is.
        if s == s.uppercased(), s.contains(where: \.isLetter) {
            s = s.capitalized
        }
        return s.isEmpty ? raw : s
    }

    /// Stable key for learning and matching: lowercase letters/digits only.
    static func key(_ raw: String) -> String {
        clean(raw).lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
