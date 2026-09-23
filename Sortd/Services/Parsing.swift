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

        // The number itself, not every digit in the text: "Rs. 500" kept the
        // "." from "RS." and read 0.5. Spaced thousands ("1 234,50") count.
        guard let r = upper.range(of: #"[0-9]{1,3}(?:[ \x{00A0}][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9][0-9.,]*[0-9]|[0-9]"#,
                                  options: .regularExpression) else { return nil }
        let number = upper[r].filter { $0 != " " && $0 != "\u{00A0}" }

        // The last separator is the decimal point when 1–2 digits follow it
        // ("1.234,56", "4,5", "58.30"); with 3 it's thousands ("1,299").
        let cleaned: String
        if let last = number.lastIndex(where: { $0 == "." || $0 == "," }),
           (1...2).contains(number.distance(from: last, to: number.endIndex) - 1) {
            cleaned = number[..<last].filter(\.isNumber) + "." + number[number.index(after: last)...]
        } else {
            cleaned = number.filter(\.isNumber)
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
