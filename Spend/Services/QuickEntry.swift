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
        let daysAgo = takeWhen(from: &rest) ?? 0

        guard let money = amount(in: rest) else { return nil }
        rest = rest.replacingCharacters(in: money.range, with: " ")

        let merchant = tidyMerchant(rest)
        guard !merchant.isEmpty else { return nil }

        return Reading(merchant: merchant, amount: money.amount,
                       currency: money.currency, daysAgo: daysAgo)
    }

    /// Days back when the line says when ("yesterday", "this morning",
    /// "last friday"), or nil when it names no time at all. "today" is 0,
    /// not nil: the line did say when.
    static func daysAgo(in text: String) -> Int? {
        var rest = text
        return takeWhen(from: &rest)
    }

    /// True when the line has a number written with a minus ("refund -5").
    /// Such a line is refused rather than read as a purchase of 5.
    static func hasNegativeAmount(in text: String) -> Bool {
        matches(in: text).contains { $0.negative }
    }

    /// How an amount goes into the Add form: "5.50" and "20", never "5.5",
    /// which looks like a different number on a money screen. Works on the
    /// Decimal itself, so no size of number can overflow it.
    static func fieldText(_ amount: Decimal) -> String {
        var value = amount, cents = Decimal(), whole = Decimal()
        NSDecimalRound(&cents, &value, 2, .plain)
        NSDecimalRound(&whole, &cents, 0, .plain)
        return cents.formatted(.number
            .precision(.fractionLength(cents == whole ? 0 : 2))
            .grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }

    // MARK: - Pieces

    /// Takes the first "when" phrase out of `text` and returns its days back.
    private static func takeWhen(from text: inout String) -> Int? {
        for (phrase, days) in whenWords {
            // Whole words only: "todays florist" is a shop, not today.
            let words = phrase.split(separator: " ")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
            let pattern = #"(?<![\p{L}\p{N}'’])"# + words + #"(?![\p{L}\p{N}]|['’]\p{L})"#
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            text.removeSubrange(range)
            return days
        }
        if let when = relativeDay(in: text) {
            text.removeSubrange(when.range)
            return when.days
        }
        return nil
    }

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// "last friday", "on monday", "3 days ago": days back from `today`.
    /// Worked out here, not by the language model, which is poor at dates.
    static func relativeDay(in text: String, today: Date = .now,
                            calendar: Calendar = .current) -> (days: Int, range: Range<String.Index>)? {
        if let r = text.range(of: #"\b(\d{1,2})\s+days?\s+ago\b"#, options: [.regularExpression, .caseInsensitive]),
           let n = Int(text[r].prefix { $0.isNumber }), n <= 60 {
            return (n, r)
        }
        // After last/on, any weekday ("on sat", "last friday"). A full name on
        // its own only at the end of the line ("coffee 5 friday"), so a shop
        // like "Ruby Tuesday" or "Sunday Market" isn't read as a date.
        let full = weekdays.joined(separator: "|")
        let short = weekdays.map { String($0.prefix(3)) }.joined(separator: "|")
        let pattern = #"\b(?:last|on)\s+(?:"# + full + "|" + short + #")\b"#
            + #"|\b(?:"# + full + #")\b(?=[\s\p{P}]*$)"#
        guard let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
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

    /// Anything this big is a typo or a phone number, not a purchase typed
    /// at a counter.
    static let limit: Decimal = 1_000_000

    /// One number in the line that could be the amount.
    private struct Found {
        var amount: Decimal
        var currency: String?
        var range: Range<String.Index>
        var negative: Bool
        /// Written like money: decimals, a thousands comma or a currency.
        var moneyLike: Bool
    }

    /// Numbers glued to a letter, "/" or "-" are not amounts: "7-eleven",
    /// "3/9", "2kg", "x2". A minus in front ("-5") is kept as a match so the
    /// line can be refused. "5k" is 5000.
    private static let amountPattern = #"(?<![\p{L}\p{N}/.\-−])(?<!\d,)([-−])?(?:(A\$|S\$|US\$|NZ\$|HK\$|RM|₹|£|€|\$)\s*)?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:[.,]\d{1,2})?)(k)?(?:\s*(aud|sgd|usd|nzd|hkd|myr|inr|gbp|eur)(?!\p{L}))?(?![\p{L}\p{N}/\-−]|[.,]\d)"#

    private static func matches(in text: String) -> [Found] {
        guard let regex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let raw = group(3), let range = Range(m.range, in: text) else { return nil }
            // "1,299" is thousands; "4,50" is a decimal comma.
            let digits = raw.range(of: #"^\d{1,3}(,\d{3})+"#, options: .regularExpression) != nil
                ? raw.replacingOccurrences(of: ",", with: "")
                : raw.replacingOccurrences(of: ",", with: ".")
            guard var value = Decimal(string: digits) else { return nil }
            if group(4) != nil { value *= 1000 }
            let code = group(5)?.uppercased() ?? currency(for: group(2))
            return Found(amount: value, currency: code, range: range, negative: group(1) != nil,
                         moneyLike: group(2) != nil || group(5) != nil || raw.contains(where: { $0 == "." || $0 == "," }))
        }
    }

    /// The amount, with a currency when one is written. A number written
    /// like money (4.50, $5, 12 sgd) wins over a bare one; otherwise the last
    /// number wins, because "7 eleven 4" is a shop called 7 Eleven and an
    /// amount of 4, not the other way round.
    private static func amount(in text: String) -> Money? {
        let found = matches(in: text)
        // Never flip "-5" into a purchase of 5.
        guard !found.contains(where: \.negative) else { return nil }
        guard let pick = found.last(where: \.moneyLike) ?? found.last,
              pick.amount > 0, pick.amount < limit else { return nil }
        return Money(amount: pick.amount, currency: pick.currency, range: pick.range)
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
            // A date like "3/9" is not part of the name.
            .replacingOccurrences(of: #"(?<![\p{L}\p{N}])\d{1,2}/\d{1,2}(?:/\d{2,4})?(?![\p{L}\p{N}])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}&'’\-\s]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            // A lone dash or apostrophe left behind is not a word.
            .filter { !$0.allSatisfy { "-'’".contains($0) } }

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
