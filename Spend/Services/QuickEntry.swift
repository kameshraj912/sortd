import Foundation

/// "coffee 5.50" → a purchase.
///
/// The fastest way to log something by hand is one line of plain text, and
/// the thing this competes with isn't another app — it's not bothering.
/// Somebody standing at a counter will type six characters; they will not
/// fill in four fields.
///
/// It reads a merchant, an amount, an optional currency and a rough date.
/// Everything it finds goes into the normal Add screen for the person to
/// check, so a wrong guess costs a glance rather than a wrong total.
///
/// Deliberately small. It does not try to understand language — it looks
/// for a number, takes the words around it as the merchant, and stops.
/// Anything cleverer would be wrong more often, and wrong is expensive.
nonisolated enum QuickEntry {

    struct Reading: Equatable, Sendable {
        var merchant: String
        var amount: Decimal
        var currency: String?
        /// Days back from today: 0 today, 1 yesterday.
        var daysAgo: Int
    }

    /// Words that say when, not what. Stripped from the merchant.
    private static let whenWords: [(String, Int)] = [
        ("the day before yesterday", 2),
        ("day before yesterday", 2),
        ("yesterday", 1),
        ("last night", 1),
        ("today", 0),
        ("this morning", 0),
        ("tonight", 0),
    ]

    /// Filler that means nothing once the amount is known.
    private static let filler = ["for", "at", "on", "spent", "paid", "cost", "was", "a", "an", "the"]

    static func read(_ input: String) -> Reading? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // When, first: "yesterday" must come out before it can be mistaken
        // for part of a shop's name.
        var rest = text
        var daysAgo = 0
        for (phrase, days) in whenWords {
            guard let range = rest.range(of: phrase, options: [.caseInsensitive]) else { continue }
            daysAgo = days
            rest.removeSubrange(range)
            break
        }

        if daysAgo == 0, let when = relativeDay(in: rest) {
            daysAgo = when.days
            rest.removeSubrange(when.range)
        }

        guard let money = amount(in: rest) else { return nil }
        rest = rest.replacingCharacters(in: money.range, with: " ")

        let merchant = tidyMerchant(rest)
        guard !merchant.isEmpty else { return nil }

        return Reading(merchant: merchant, amount: money.amount,
                       currency: money.currency, daysAgo: daysAgo)
    }

    // MARK: - Pieces

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// "last friday", "on monday", "3 days ago": days back from `today`.
    /// Worked out here, not by the language model, which is poor at dates.
    static func relativeDay(in text: String, today: Date = .now,
                            calendar: Calendar = .current) -> (days: Int, range: Range<String.Index>)? {
        if let r = text.range(of: #"\b(\d{1,2})\s+days?\s+ago\b"#, options: [.regularExpression, .caseInsensitive]),
           let n = Int(text[r].prefix { $0.isNumber }), n <= 60 {
            return (n, r)
        }
        // Full names alone ("friday"); short ones only after last/on ("on sat"),
        // so a shop like "Sun Kee" isn't read as a date.
        let full = weekdays.joined(separator: "|")
        let short = weekdays.map { String($0.prefix(3)) }.joined(separator: "|")
        guard let r = text.range(of: #"\b(?:(?:last|on)\s+)?(?:"# + full + #")\b|\b(?:last|on)\s+(?:"# + short + #")\b"#,
                                 options: [.regularExpression, .caseInsensitive]) else { return nil }
        let phrase = text[r].lowercased()
        guard let target = weekdays.firstIndex(where: { phrase.hasSuffix($0) || phrase.hasSuffix(String($0.prefix(3))) }) else { return nil }
        let todayIndex = calendar.component(.weekday, from: today) - 1
        var back = (todayIndex - target + 7) % 7
        // "friday" on a Friday means today; "last friday" means a week ago.
        if back == 0, phrase.hasPrefix("last") { back = 7 }
        return (back, r)
    }

    private struct Money {
        var amount: Decimal
        var currency: String?
        var range: Range<String.Index>
    }

    /// The number, with a currency when one is written. The last number
    /// wins, because "7 eleven 4.50" is a shop called 7 Eleven and an
    /// amount of 4.50, not the other way round.
    private static func amount(in text: String) -> Money? {
        let pattern = #"(?:(?<!\p{L})(A\$|S\$|US\$|NZ\$|HK\$|RM|₹|£|€|\$)\s*)?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s*(aud|sgd|usd|nzd|hkd|myr|inr|gbp|eur)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .filter { $0.range(at: 2).location != NSNotFound }
        guard let m = matches.last, let range = Range(m.range, in: text) else { return nil }

        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        // "1,299" is thousands; "4,50" is a decimal comma.
        let raw = group(2) ?? ""
        let digits = raw.range(of: #"^\d{1,3}(,\d{3})+"#, options: .regularExpression) != nil
            ? raw.replacingOccurrences(of: ",", with: "")
            : raw.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: digits), value > 0 else { return nil }

        let code = group(3)?.uppercased() ?? currency(for: group(1))
        return Money(amount: value, currency: code, range: range)
    }

    private static func currency(for symbol: String?) -> String? {
        switch symbol?.uppercased() {
        case "A$": "AUD"
        case "S$": "SGD"
        case "US$": "USD"
        case "NZ$": "NZD"
        case "HK$": "HKD"
        case "RM": "MYR"
        case "₹": "INR"
        case "£": "GBP"
        case "€": "EUR"
        default: nil
        }
    }

    /// What's left after the amount and the date, minus the filler, tidied
    /// into something that looks like a name.
    private static func tidyMerchant(_ text: String) -> String {
        let words = text
            .replacingOccurrences(of: #"[^\p{L}\p{N}&'’\-\s]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        // Filler only counts as filler at the edges: "at" in the middle of
        // "Bar at the End" is part of the name.
        var kept = words
        while let f = kept.first, filler.contains(f.lowercased()) { kept.removeFirst() }
        while let l = kept.last, filler.contains(l.lowercased()) { kept.removeLast() }
        guard !kept.isEmpty else { return "" }

        return kept
            .map { word in
                // Leave anything already capitalised alone (KFC, McDonald's).
                word.contains(where: \.isUppercase) ? word : word.capitalized
            }
            .joined(separator: " ")
    }
}
