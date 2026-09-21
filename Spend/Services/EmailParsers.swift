import Foundation

/// Turns receipt and bank-alert emails into purchase records, on the phone.
/// Exact rules for known senders, each tested against real layouts.
/// Pure: no network, no clock.
///
/// If a sender changes its wording, its parser returns [] rather than guessing.
nonisolated enum EmailParsers {
    struct Message: Sendable {
        let id: String
        let from: String
        let subject: String
        let body: String
        /// When the email arrived.
        let date: Date
        /// Domains the receiving mail server proved sent this email (DKIM or
        /// DMARC pass). Nil when the source can't tell us, e.g. in tests.
        var authenticatedDomains: Set<String>? = nil
    }

    /// The sender's real domain, from "Name <a@b.com>" or "a@b.com".
    /// Lowercased. Nil when there's no address.
    nonisolated static func senderDomain(_ from: String) -> String? {
        var address = from
        if let open = from.lastIndex(of: "<"), let close = from.lastIndex(of: ">"), open < close {
            address = String(from[from.index(after: open)..<close])
        }
        guard let at = address.lastIndex(of: "@") else { return nil }
        let domain = address[address.index(after: at)...]
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ">\"'")))
            .lowercased()
        return domain.isEmpty ? nil : domain
    }

    /// True when `domain` is `known` or one of its subdomains. An exact match,
    /// so "notapple.com" or "apple.com.evil.io" don't pass for "apple.com".
    nonisolated static func isDomain(_ domain: String?, within known: String) -> Bool {
        guard let domain else { return false }
        return domain == known || domain.hasSuffix("." + known)
    }

    /// Whether the email really came from `known`. Needs the sender address to
    /// be on that domain and, when the mail server reported it, a DKIM or DMARC
    /// pass for it. Stops someone emailing a fake receipt "from" a bank.
    nonisolated static func isFrom(_ msg: Message, _ known: String) -> Bool {
        guard isDomain(senderDomain(msg.from), within: known) else { return false }
        guard let proven = msg.authenticatedDomains else { return true }
        return proven.contains { isDomain($0, within: known) }
    }

    /// Gmail search that finds every email the parsers understand.
    static let gmailQuery = [
        "from:alerts.sg@sc.com",
        "(from:no-reply@doordash.com subject:\"Order Confirmation\")",
        "(from:email.apple.com (subject:\"tax invoice\" OR subject:\"receipt\"))",
        "(from:noreply@you.co subject:\"Summary of your recent\")",
        "from:stripe.com",
        "from:invoice+statements@mail.anthropic.com",
    ].joined(separator: " OR ") + " OR " + BankAlerts.gmailTerms.joined(separator: " OR ")

    /// Senders with exact rules. Their emails never go to the general reader:
    /// if a rule finds nothing (a DoorDash promo), there's nothing to find.
    /// Checked on the address's real domain, so a look-alike sender goes to
    /// neither the rules nor the general reader.
    static let ruleDomains = ["sc.com", "doordash.com", "apple.com", "you.co", "stripe.com", "mail.anthropic.com"]

    static func knowsSender(_ from: String) -> Bool {
        let domain = senderDomain(from)
        if BankAlerts.bank(for: from) != nil { return true }
        return ruleDomains.contains { isDomain(domain, within: $0) }
    }

    /// Which parser handles a sender. Anything else is ignored, and so is an
    /// email that claims a known sender but failed the mail server's check.
    static func parse(_ msg: Message) -> [EmailRecord] {
        if isFrom(msg, "sc.com") { return stanChart(msg) }
        if isFrom(msg, "doordash.com") { return doorDash(msg) }
        if isFrom(msg, "apple.com") { return apple(msg) }
        if isFrom(msg, "you.co") { return youTrip(msg) }
        if isFrom(msg, "stripe.com") || isFrom(msg, "mail.anthropic.com") { return stripe(msg) }
        if let bank = BankAlerts.bank(for: msg.from), isFrom(msg, bank.domain) { return bankAlert(msg, bank) }
        return []
    }

    // MARK: - Standard Chartered Singapore card alerts

    static func stanChart(_ msg: Message) -> [EmailRecord] {
        let text = normalize(msg.body)
        let buy = #"charging \+?([A-Z]{3}) ([\d,]+\.\d{2}) to yr (debit|credit) card \*+(\d{4}) on (\d{2}-[A-Za-z]{3}-\d{2})\s*(\d{1,2}:\d{2}\s?[AP]M) at (.+?)\.\s+To modify"#
        let back = #"Transaction of \+?([A-Z]{3}) ([\d,]+\.\d{2}) made on your card \*+(\d{4}) on (\d{2}-[A-Za-z]{3}-\d{2})\s*(\d{1,2}:\d{2}\s?[AP]M) at (.+?) has been reversed"#
        if let m = first(buy, in: text, caseInsensitive: true) {
            let d = cleanDescriptor(m[7])
            return [record(msg, 0, kind: "purchase", merchant: d.merchant, raw: m[7], platform: d.platform,
                           amount: money(m[2]), currency: m[1].uppercased(), last4: m[4],
                           date: sgtDate(m[5], m[6]) ?? msg.date)]
        }
        if let m = first(back, in: text, caseInsensitive: true) {
            let d = cleanDescriptor(m[6])
            return [record(msg, 0, kind: "refund", merchant: d.merchant, raw: m[6], platform: d.platform,
                           amount: money(m[2]), currency: m[1].uppercased(), last4: m[3],
                           date: sgtDate(m[4], m[5]) ?? msg.date, note: "Reversed by the bank")]
        }
        return []
    }

    // MARK: - Bank alerts

    /// "You just spent $58.30 at WOOLWORTHS on your card ending 1234."
    ///
    /// The card spending nobody emails you a receipt for, and the only
    /// source that ever tells you about a refund. See `BankAlerts` for why
    /// this is deliberately cautious about what counts as a purchase.
    static func bankAlert(_ msg: Message, _ bank: BankAlerts.Bank) -> [EmailRecord] {
        guard let reading = BankAlerts.read(subject: msg.subject, body: msg.body, bank: bank) else { return [] }
        let d = cleanDescriptor(reading.merchant)
        return [record(msg, 0,
                       kind: reading.isRefund ? "refund" : "purchase",
                       merchant: d.merchant, raw: reading.merchant, platform: d.platform,
                       amount: reading.amount, currency: reading.currency,
                       last4: reading.last4, date: msg.date,
                       note: reading.isRefund ? "Reversed by the bank" : "")]
    }

    // MARK: - DoorDash order confirmations

    static func doorDash(_ msg: Message) -> [EmailRecord] {
        guard let subject = first(#"Order Confirmation for .+? from (.+)$"#, in: msg.subject, caseInsensitive: true) else { return [] }
        let text = normalize(msg.body)
        guard let total = first(#"Total Charged \$([\d,]+\.\d{2})"#, in: text, caseInsensitive: true)
                ?? first(#"Total: \$([\d,]+\.\d{2})"#, in: text, caseInsensitive: true) else { return [] }
        let restaurant = subject[1].trimmingCharacters(in: .whitespaces)
        let adjusted = matches(#"adjustments to your order"#, text)
        let paidWithApplePay = matches(#"Paid with Apple Pay"#, text)
        return [record(msg, 0, kind: "purchase", merchant: restaurant, raw: "DoorDash: " + restaurant, platform: "doordash",
                       amount: money(total[1]), currency: "AUD", last4: nil, date: msg.date,
                       note: (paidWithApplePay ? "DoorDash · paid with Apple Pay" : "DoorDash") + (adjusted ? " · order adjusted" : ""))]
    }

    // MARK: - Apple tax invoices / receipts

    static func apple(_ msg: Message) -> [EmailRecord] {
        guard matches(#"tax invoice|receipt from apple"#, msg.subject) else { return [] }
        let text = normalize(msg.body)
        let paid = first(#"(?:Visa|Mastercard|Amex|American Express)\s*[•·.]+\s*(\d{4})\s+\$([\d,]+\.\d{2})"#, in: text, caseInsensitive: true)
        guard let item = first(#"Apple Account: \S+ (.+?) (?:Renews (\d{1,2} [A-Za-z]+ \d{4}) )?\$([\d,]+\.\d{2})"#, in: text) else {
            return appleInApp(msg, text)
        }
        let title = item[1].trimmingCharacters(in: .whitespaces)
        let app = title.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespaces)
        let period: String? = matches(#"annual|year"#, title) ? "yearly" : matches(#"month"#, title) ? "monthly" : nil
        let renews = item[2].isEmpty ? nil : item[2]
        var r = record(msg, 0, kind: "purchase", merchant: app, raw: "Apple: " + title, platform: "apple",
                       amount: money(paid?[2] ?? item[3]), currency: "AUD", last4: paid?[1], date: msg.date,
                       note: "App Store · " + title)
        if renews != nil || period != nil {
            r.subscription = .init(name: app, period: period, renews: renews)
        }
        return [r]
    }

    /// Older invoice layout, used for in-app purchases.
    static func appleInApp(_ msg: Message, _ text: String) -> [EmailRecord] {
        guard let total = first(#"TOTAL \$([\d,]+\.\d{2})"#, in: text),
              let item = first(#"App Store (.+?) (?:In-App Purchase|Report a Problem|\$)"#, in: text) else { return [] }
        let card = first(#"(?:Visa|Mastercard|Amex|American Express)\s*[•·.]{2,}\s*(\d{4})"#, in: text, caseInsensitive: true)
        let title = item[1].trimmingCharacters(in: .whitespaces)
        let inApp = matches(#"In-App Purchase"#, text)
        return [record(msg, 0, kind: "purchase", merchant: title.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespaces),
                       raw: "Apple: " + title, platform: "apple", amount: money(total[1]), currency: "AUD",
                       last4: card?[1], date: msg.date, note: "App Store · " + title + (inApp ? " · in-app purchase" : ""))]
    }

    // MARK: - YouTrip daily summaries

    static func youTrip(_ msg: Message) -> [EmailRecord] {
        guard matches(#"Summary of your recent online purchases"#, msg.subject) else { return [] }
        let text = normalize(msg.body)
        // Gmail's plain text may bold the header: "(UTC+8)*." — allow the asterisk.
        // Also "(UTC+8) ." with a space, as Gmail's API gives the HTML version.
        let pattern = #"(?:\(UTC\+8\)\*?\s?\.|[AP]M)\s+(.+?)\s+([A-Z]{3}) ([\d,]+\.\d{2})\s+Ref\. No: (\S+)\s+(\d{1,2}:\d{2}\s?[AP]M)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [EmailRecord] = []
        var start = 0
        while start < ns.length,
              let m = regex.firstMatch(in: text, range: NSRange(location: start, length: ns.length - start)) {
            let g = groups(m, in: ns)
            let d = cleanDescriptor(g[1])
            var r = record(msg, out.count, kind: "purchase", merchant: d.merchant,
                           raw: g[1].components(separatedBy: "~")[0].trimmingCharacters(in: .whitespaces),
                           platform: d.platform, amount: money(g[3]), currency: g[2], last4: nil,
                           date: youTripDate(sent: msg.date, time: g[5]) ?? msg.date, note: "YouTrip · ref " + g[4])
            r.card = "youtrip"
            out.append(r)
            // Let this row's time start the next row, like the JS lastIndex trick.
            start = m.range(at: 5).location
        }
        return out
    }

    /// The summary covers the last 24 hours in Singapore time; a time later
    /// than the email means the day before.
    static func youTripDate(sent: Date, time: String) -> Date? {
        guard let t = first(#"^(\d{1,2}):(\d{2})\s?([AP]M)$"#, in: time.trimmingCharacters(in: .whitespaces), caseInsensitive: true) else { return nil }
        var sgt = Calendar(identifier: .gregorian)
        sgt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let hour = (Int(t[1])! % 12) + (t[3].uppercased() == "PM" ? 12 : 0)
        var parts = sgt.dateComponents([.year, .month, .day], from: sent)
        parts.hour = hour
        parts.minute = Int(t[2])
        guard var day = sgt.date(from: parts) else { return nil }
        if day > sent { day = day.addingTimeInterval(-86400) }
        return day
    }

    // MARK: - Stripe receipts and refunds (and Anthropic invoices)

    static func stripe(_ msg: Message) -> [EmailRecord] {
        let text = normalize(msg.body)
        // A bare "$" means the reader's own dollar (Stripe shows local currency).
        let fallback = Money.home
        if let m = first(#"Refund from (.+?) Receipt #([\d-]+) Refunded ([A-Z]{0,2}\$|[A-Z]{3} ?)([\d,]+\.\d{2})"#, in: text) {
            let to = first(#"Refunded to - (\d{4})"#, in: text)
            return [record(msg, 0, kind: "refund", merchant: tidyCompany(m[1]), raw: m[1], platform: nil,
                           amount: money(m[4]), currency: currencyFrom(m[3], fallback), last4: to?[1], date: msg.date,
                           note: "Refund · receipt #" + m[2])]
        }
        if let m = first(#"Receipt from (.+?) Receipt #([\d-]+) Amount paid ([A-Z]{0,2}\$|[A-Z]{3} ?)([\d,]+\.\d{2})"#, in: text) {
            let pm = first(#"Payment method - (\d{4})"#, in: text)
            return [record(msg, 0, kind: "purchase", merchant: tidyCompany(m[1]), raw: m[1], platform: nil,
                           amount: money(m[4]), currency: currencyFrom(m[3], fallback), last4: pm?[1], date: msg.date,
                           note: "Receipt #" + m[2])]
        }
        if let m = first(#"Refund from (.+?) ([A-Z]{0,2}\$)([\d,]+\.\d{2}) Refunded on ([A-Za-z]+ \d{1,2}, \d{4})"#, in: text) {
            let to = first(#"Refunded to - (\d{4})"#, in: text)
            return [record(msg, 0, kind: "refund", merchant: tidyCompany(m[1]), raw: m[1], platform: nil,
                           amount: money(m[3]), currency: currencyFrom(m[2], fallback), last4: to?[1], date: msg.date,
                           note: "Refund")]
        }
        if let m = first(#"Receipt from (.+?) ([A-Z]{0,2}\$)([\d,]+\.\d{2}) Paid ([A-Za-z]+ \d{1,2}, \d{4})"#, in: text) {
            let pm = first(#"Payment method - (\d{4})"#, in: text)
            let plan = first(#"\d{4} (.+?) Qty \d+"#, in: text)
            var r = record(msg, 0, kind: "purchase", merchant: tidyCompany(m[1]), raw: m[1], platform: nil,
                           amount: money(m[3]), currency: currencyFrom(m[2], fallback), last4: pm?[1], date: msg.date,
                           note: plan.map { $0[1].replacingOccurrences(of: #"^.*\d{4} "#, with: "", options: .regularExpression) } ?? "")
            r.subscription = .init(name: tidyCompany(m[1]), period: "monthly", renews: nil)
            return [r]
        }
        return []
    }

    // MARK: - Helpers (same behaviour as the JS versions)

    /// Collapse table pipes, odd spaces and newlines into single spaces.
    static func normalize(_ text: String) -> String {
        let odd: Set<Unicode.Scalar> = ["\u{00A0}", "\u{034F}", "\u{200B}", "\u{200C}", "\u{2007}", "\u{2060}"]
        let scalars = text.unicodeScalars.map { $0 == "|" || odd.contains($0) ? " " : Character($0) }
        return String(scalars)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func money(_ text: String) -> String { text.replacingOccurrences(of: ",", with: "") }

    static func currencyFrom(_ symbol: String, _ fallback: String) -> String {
        let s = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        if s.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil { return s }
        switch s {
        case "A$", "AU$": return "AUD"
        case "S$": return "SGD"
        case "US$": return "USD"
        default: return fallback
        }
    }

    /// "16-Sep-26" + "11:54 AM" in Singapore time.
    static func sgtDate(_ dmy: String, _ time: String) -> Date? {
        guard let d = first(#"^(\d{1,2})-([A-Za-z]{3})-(\d{2})$"#, in: dmy),
              let t = first(#"^(\d{1,2}):(\d{2})\s?([AP]M)$"#, in: time.trimmingCharacters(in: .whitespaces), caseInsensitive: true) else { return nil }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let month = months.firstIndex(of: d[2].lowercased()) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return cal.date(from: DateComponents(year: 2000 + Int(d[3])!, month: month + 1, day: Int(d[1]),
                                             hour: (Int(t[1])! % 12) + (t[3].uppercased() == "PM" ? 12 : 0),
                                             minute: Int(t[2])))
    }

    /// Bank descriptors -> readable name + delivery platform.
    static func cleanDescriptor(_ raw: String) -> (merchant: String, platform: String?) {
        let s = raw.components(separatedBy: "~")[0].trimmingCharacters(in: .whitespaces)
        let upper = s.uppercased()
        if upper.hasPrefix("DD *") || upper.contains("DOORDASH") { return ("DoorDash", "doordash") }
        if upper.range(of: #"UBER\s*\*\s*EATS"#, options: .regularExpression) != nil { return ("Uber Eats", "uber") }
        if upper.range(of: #"^UBER\s*\*"#, options: .regularExpression) != nil { return ("Uber", "uber") }
        return (s, nil)
    }

    /// "Iglu Brisbane (Iglu Pty Ltd)" -> "Campus Rooms"; "Anthropic, PBC" -> "Anthropic".
    static func tidyCompany(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(.*?\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #",?\s*(PBC|Pty Ltd|Pte Ltd|Inc\.?|LLC|Ltd\.?)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    private static func record(_ msg: Message, _ index: Int, kind: String, merchant: String, raw: String,
                               platform: String?, amount: String, currency: String, last4: String?,
                               date: Date, note: String = "") -> EmailRecord {
        let digits = last4.flatMap { $0.range(of: #"^\d{4}$"#, options: .regularExpression) != nil ? $0 : nil }
        return EmailRecord(id: "\(msg.id)-\(index)", kind: kind, merchant: merchant, rawMerchant: raw,
                           platform: platform, amount: amount, currency: currency, card: "other",
                           last4: digits, date: iso.string(from: date), note: note, subscription: nil)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Regex helpers: first match's groups (index 0 = whole match; missing groups = "").
    private static func first(_ pattern: String, in text: String, caseInsensitive: Bool = false) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive, .anchorsMatchLines] : [.anchorsMatchLines]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return groups(m, in: text as NSString)
    }

    private static func groups(_ m: NSTextCheckingResult, in ns: NSString) -> [String] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
