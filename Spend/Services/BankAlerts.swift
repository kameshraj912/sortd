import Foundation

/// Reads "you just spent $X at Y" emails from banks.
///
/// This is the gap the website already advertises: Sortd says it reads
/// "receipts and bank alerts", and until now the only bank with a parser
/// was Standard Chartered. Bank alerts matter more than receipts, because
/// they cover the card spending that no merchant emails you about, and
/// they're the only source that reports a refund.
///
/// **A warning worth reading before trusting this.** The Standard Chartered
/// parser was written against real emails. These were not — they are built
/// from the shapes bank alerts take, not from a verified sample of each
/// bank's wording. Every bank is free to change its template tomorrow, and
/// some of them phrase things in ways nobody has thought of.
///
/// So the design is deliberately defensive rather than clever:
///
/// * Structure first, bank second. One set of patterns covers the common
///   phrasings, instead of a bespoke regex per bank that breaks silently
///   the moment a word changes.
/// * An alert has to give an amount **and** a merchant before it counts.
///   A balance notification, a login alert or a "your statement is ready"
///   email produces nothing rather than a £0 purchase.
/// * Money in is never a purchase. Refunds, reversals, credits and
///   transfers in are either recorded as refunds or dropped.
/// * When anything is unclear, return nothing. A missed purchase is a small
///   annoyance; an invented one puts a number in front of somebody that
///   they cannot explain, and that costs their trust in every other number.
nonisolated enum BankAlerts {

    struct Bank: Sendable, Equatable {
        let name: String
        /// Matched against the sender address, lowercased.
        let domain: String
        /// What the bank bills in, used when the email omits a currency.
        let currency: String
    }

    /// Banks whose alert emails Sortd looks at. The list matches the
    /// presets in `Banks.swift` so the two don't drift apart.
    static let known: [Bank] = [
        // Australia
        .init(name: "NAB", domain: "nab.com.au", currency: "AUD"),
        .init(name: "CommBank", domain: "commbank.com.au", currency: "AUD"),
        .init(name: "ANZ", domain: "anz.com", currency: "AUD"),
        .init(name: "Westpac", domain: "westpac.com.au", currency: "AUD"),
        .init(name: "ING", domain: "ing.com.au", currency: "AUD"),
        .init(name: "Up", domain: "up.com.au", currency: "AUD"),
        .init(name: "ubank", domain: "ubank.com.au", currency: "AUD"),
        .init(name: "Macquarie", domain: "macquarie.com", currency: "AUD"),
        .init(name: "Bendigo", domain: "bendigobank.com.au", currency: "AUD"),
        .init(name: "St.George", domain: "stgeorge.com.au", currency: "AUD"),
        // Singapore
        .init(name: "DBS", domain: "dbs.com", currency: "SGD"),
        .init(name: "POSB", domain: "posb.com.sg", currency: "SGD"),
        .init(name: "OCBC", domain: "ocbc.com", currency: "SGD"),
        .init(name: "UOB", domain: "uob.com.sg", currency: "SGD"),
        .init(name: "Trust", domain: "trustbank.sg", currency: "SGD"),
        .init(name: "GXS", domain: "gxs.com.sg", currency: "SGD"),
        // Malaysia
        .init(name: "Maybank", domain: "maybank.com", currency: "MYR"),
        .init(name: "CIMB", domain: "cimb.com", currency: "MYR"),
    ]

    static func bank(for sender: String) -> Bank? {
        let domain = EmailParsers.senderDomain(sender)
        return known.first { EmailParsers.isDomain(domain, within: $0.domain) }
    }

    /// The Gmail search terms for every bank above.
    static var gmailTerms: [String] {
        known.map { "from:\($0.domain)" }
    }

    // MARK: - What an alert turned out to be

    struct Reading: Equatable, Sendable {
        var merchant: String
        var amount: String
        var currency: String
        var last4: String?
        /// True for a refund, reversal or credit.
        var isRefund: Bool
    }

    /// Emails a bank sends that are not a purchase. Checked before anything
    /// else, because several of them do contain a dollar amount and would
    /// otherwise read as spending.
    private static let notAPurchase = [
        "statement is ready", "statement is now available", "e-statement",
        "your balance", "balance alert", "low balance",
        "log ?in", "logged in", "sign ?in alert", "new device",
        "password", "security alert", "verify your", "one-time password", "otp",
        "payment is due", "minimum payment", "due date",
        "direct debit will", "scheduled payment",
        "interest rate", "terms and conditions", "privacy policy",
        "salary", "payroll",
    ]

    /// Words that mean the money came back.
    private static let refundWords = [
        "refund", "reversed", "reversal", "credited to", "credit to your",
        "returned", "chargeback", "cancelled transaction",
    ]

    static func read(subject: String, body: String, bank: Bank) -> Reading? {
        let text = tidy(subject + "\n" + body)

        // A bank email that isn't about a purchase is very often still full
        // of numbers, so this check comes first.
        guard !notAPurchase.contains(where: { contains($0, text) }) else { return nil }

        guard let money = amount(in: text) else { return nil }
        guard let merchant = merchant(in: text), !merchant.isEmpty else { return nil }

        return Reading(merchant: merchant,
                       amount: money.amount,
                       currency: money.currency ?? bank.currency,
                       last4: last4(in: text),
                       isRefund: refundWords.contains { contains($0, text) })
    }

    // MARK: - The pieces

    /// The amount, with its currency when the email says one.
    ///
    /// Bank alerts write money as "A$58.30", "AUD 58.30", "SGD58.30" or
    /// plain "$58.30". Cents are required: a bare "$58" is far more often a
    /// balance or a limit than a purchase, and guessing wrong there is
    /// exactly the kind of invented number this file is trying to avoid.
    static func amount(in text: String) -> (amount: String, currency: String?)? {
        let patterns = [
            #"\b((?-i:[A-Z]{3}))\s?\$?\s?([\d,]+\.\d{2})\b"#,  // AUD 58.30 / SGD$58.30 (capitals only)
            #"\b(A|S|US|NZ|HK)\$\s?([\d,]+\.\d{2})\b"#,        // A$58.30
            #"()\$\s?([\d,]+\.\d{2})\b"#,                      // $58.30
            #"()\bRM\s?([\d,]+\.\d{2})\b"#,                    // RM58.30
        ]
        for pattern in patterns {
            guard let m = match(pattern, text) else { continue }
            let raw = m[1].trimmingCharacters(in: .whitespaces).uppercased()
            // "payment for $58.30": a word before the amount isn't a currency.
            if raw.count == 3, !Locale.commonISOCurrencyCodes.contains(raw) { continue }
            let code: String? = switch raw {
            case "": nil
            case "A": "AUD"
            case "S": "SGD"
            case "US": "USD"
            case "NZ": "NZD"
            case "HK": "HKD"
            default: raw.count == 3 ? raw : nil
            }
            return (m[2].replacingOccurrences(of: ",", with: ""), code)
        }
        return nil
    }

    /// Who was paid.
    ///
    /// Banks write this as "at MERCHANT", "to MERCHANT" or "merchant:
    /// MERCHANT", and then run straight into the next sentence. Each pattern
    /// stops at a full stop, a line break, or a word that starts the next
    /// clause ("on", "using", "from your"), because "at COLES on 01/09" has
    /// to give "COLES" and not "COLES on 01/09".
    static func merchant(in text: String) -> String? {
        let patterns = [
            #"(?:merchant|payee)\s*[:\-]\s*([^\n\.]{2,60})"#,
            #"\bat\s+([^\n\.]{2,60}?)(?=\s+(?:on|using|with|from|for|via)\b|[\.\n]|$)"#,
            #"\bto\s+([^\n\.]{2,60}?)(?=\s+(?:on|using|with|from|for|via)\b|[\.\n]|$)"#,
            // Refunds run the other way: "a refund of $38.00 from KMART".
            // Last, so a purchase's "at" or "to" always wins.
            #"\bfrom\s+([^\n\.]{2,60}?)(?=\s+(?:on|using|with|to|for|via|has|was)\b|[\.\n]|$)"#,
        ]
        for pattern in patterns {
            guard let m = match(pattern, text) else { continue }
            let cleaned = clean(m[1])
            // "at your account", "to your card" — that's the bank talking
            // about itself, not a shop.
            guard cleaned.count >= 2,
                  cleaned.rangeOfCharacter(from: .letters) != nil,
                  !contains(#"^(your|the|a)\b"#, cleaned.lowercased()) else { continue }
            return cleaned
        }
        return nil
    }

    /// The card's last four digits, however the bank writes it.
    static func last4(in text: String) -> String? {
        let patterns = [
            #"(?:ending|ending in|ending with)\s*\**\s*(\d{4})\b"#,
            #"\*{2,}\s?(\d{4})\b"#,
            #"x{2,}\s?(\d{4})\b"#,
            #"\bcard\s+(?:no\.?|number)?\s*\**(\d{4})\b"#,
        ]
        for pattern in patterns {
            if let m = match(pattern, text) { return m[1] }
        }
        return nil
    }

    // MARK: - Text helpers

    /// Bank emails arrive with hard wraps, non-breaking spaces and runs of
    /// whitespace. Flatten it so one pattern can cross what used to be a
    /// line break.
    static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trims the punctuation and filler banks leave on the end of a name.
    private static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n.,;:-–—*'\"()"))
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }

    private static func contains(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        let ns = text as NSString
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}
