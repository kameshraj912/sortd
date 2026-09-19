import Foundation
import FoundationModels

/// Reading receipts from any sender, not just the ones `EmailParsers` knows.
///
/// Order of trust:
/// 1. Known senders — exact rules in `EmailParsers` (most accurate).
/// 2. Apple's on-device model (Apple Intelligence) reads the email and
///    returns merchant, total, currency, card digits, refund or not.
/// 3. A plain rule for phones without Apple Intelligence: a "Total"-type
///    line with an amount.
///
/// Guardrails for 2 and 3: promotions are skipped, and an amount is only
/// accepted if it appears word-for-word in the email, so nothing is invented.
nonisolated enum GenericReceipts {

    // MARK: Search

    /// Gmail search for receipts from anyone: Gmail's own Purchases category
    /// plus common receipt subjects, never promotions or social.
    static let gmailQuery = """
        (category:purchases OR subject:(receipt OR invoice OR "order confirmation" OR "your order" OR "payment received" \
        OR "payment confirmation" OR "transaction alert" OR "you paid" OR "refund")) -category:promotions -category:social
        """

    // MARK: Rule-based fallback

    /// Subjects that are marketing, not purchases.
    static func looksLikePromotion(_ subject: String) -> Bool {
        let s = subject.lowercased()
        let words = ["% off", "sale", "deal", "offer", "newsletter", "discount", "coupon", "promo", "save up to",
                     "free shipping", "don't miss", "last chance", "new arrivals", "we miss you", "rate your", "review your"]
        return words.contains { s.contains($0) }
    }

    /// Emails about an order that aren't the payment itself: shipping and
    /// delivery updates, failed or declined payments, reminders of future
    /// charges, statements, account notices, and replies.
    static func isNotAPurchase(_ subject: String) -> Bool {
        let s = subject.lowercased()
        if s.hasPrefix("re:") || s.hasPrefix("re :") { return true }
        // "Your refund is on its way" is a refund, not a delivery update.
        if s.contains("refund") && !s.contains("declined") && !s.contains("failed") { return false }
        let words = ["shipped", "shipping", "dispatched", "out for delivery", "delivered", "on its way", "on the way",
                     "picked up", "ready for pickup", "ready for collection", "is here", "has arrived", "scheduled",
                     "arriving", "tracking", "parcel", "declined", "failed", "unsuccessful", "couldn't process",
                     "could not process", "payment in", "will be charged", "upcoming", "renews soon", "reminder",
                     "statement", "certificate", "welcome", "restored", "cancelled", "canceled", "password",
                     "verify", "security", "sign-in", "sign in", "survey", "feedback"]
        return words.contains { s.contains($0) }
    }

    /// Worth reading at all (by the model or the rule).
    static func worthReading(_ msg: EmailParsers.Message) -> Bool {
        !looksLikePromotion(msg.subject) && !isNotAPurchase(msg.subject)
    }

    /// A purchase from any receipt-shaped email, or nothing.
    static func parse(_ msg: EmailParsers.Message) -> EmailRecord? {
        guard worthReading(msg) else { return nil }
        let text = EmailParsers.normalize(msg.body)
        guard let (currency, amount) = total(in: text) else { return nil }
        let refund = isRefund(subject: msg.subject, text: text)
        return EmailRecord(
            id: "\(msg.id)-0", kind: refund ? "refund" : "purchase",
            merchant: merchant(from: msg.from, subject: msg.subject), rawMerchant: merchant(from: msg.from, subject: msg.subject),
            platform: nil, amount: amount, currency: currency, card: "other",
            last4: last4(in: text), date: iso.string(from: msg.date),
            note: "Read from email · check the amount", subscription: nil)
    }

    /// The best "total" amount: grand totals beat plain totals, and the last
    /// one wins (receipts list subtotals first).
    static func total(in text: String) -> (currency: String, amount: String)? {
        let money = #"(A\$|AU\$|S\$|US\$|NZ\$|C\$|HK\$|RM|Rp|₹|£|€|¥|\$|[A-Z]{3})\s?(\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2})"#
        let tiers = [
            #"(?:grand total|total charged|amount charged|amount paid|total paid|you paid|payment of|purchase of|charged)"#,
            #"(?:order total|total amount|total due|amount due|total \(incl[^)]*\))"#,
            #"(?:total)"#,
        ]
        for label in tiers {
            let pattern = label + #"\s*[:\-–]?\s*"# + money
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            if let m = matches.last {
                let symbol = ns.substring(with: m.range(at: 1))
                let value = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ",", with: "")
                guard let d = Decimal(string: value), d > 0 else { continue }
                return (currencyCode(symbol), value)
            }
        }
        return nil
    }

    static func currencyCode(_ symbol: String) -> String {
        switch symbol.uppercased() {
        case "A$", "AU$": "AUD"
        case "S$": "SGD"
        case "US$": "USD"
        case "NZ$": "NZD"
        case "C$": "CAD"
        case "HK$": "HKD"
        case "RM": "MYR"
        case "RP": "IDR"
        case "₹": "INR"
        case "£": "GBP"
        case "€": "EUR"
        case "¥": "JPY"
        // A bare "$" is the user's own dollar if they use one, else US dollars.
        case "$": ["AUD", "SGD", "NZD", "CAD", "HKD", "USD"].contains(Money.home) ? Money.home : "USD"
        default: symbol.count == 3 ? symbol.uppercased() : Money.home
        }
    }

    static func isRefund(subject: String, text: String) -> Bool {
        let s = subject.lowercased()
        return s.contains("refund") || s.contains("reversal") || s.contains("reversed")
            || text.range(of: #"\b(refunded|has been refunded|refund of)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "ending in 1234", "•••• 1234", "**** 1234", "xxxx1234", "card no. 1234".
    static func last4(in text: String) -> String? {
        let pattern = #"(?:ending(?: in)?|ends in|[•*xX]{2,}|card (?:no\.?|number)\s?[:#]?)\s*(\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// "Your receipt from Grab" → "Grab"; otherwise the sender's name without
    /// "no-reply", "Receipts" and similar.
    static func merchant(from: String, subject: String) -> String {
        if let r = subject.range(of: #"(?i)(?:receipt|invoice|order|payment)(?: confirmation)? (?:from|with|at) (.+?)(?:[.!#]|$)"#, options: .regularExpression) {
            let tail = String(subject[r])
            if let from = tail.range(of: #"(?i) (?:from|with|at) "#, options: .regularExpression) {
                return tail[from.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " .!#"))
            }
        }
        var name = from.components(separatedBy: "<").first?.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) ?? from
        if name.isEmpty || name.contains("@") {
            // No display name: use the domain, e.g. "orders@grab.com" → "Grab".
            let domain = from.components(separatedBy: "@").last?.components(separatedBy: ".").first ?? from
            name = domain.capitalized
        }
        for noise in [" Receipts", " Receipt", " Orders", " Order", " Billing", " Payments", " Team", " no-reply", " noreply", " Notifications"] {
            name = name.replacingOccurrences(of: noise, with: "", options: .caseInsensitive)
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// True when `amount` (e.g. "42.50") is written in the email, with or
    /// without a thousands comma. Used to reject any invented amount.
    static func appears(_ amount: String, in text: String) -> Bool {
        guard let d = Decimal(string: amount) else { return false }
        let plain = String(format: "%.2f", NSDecimalNumber(decimal: d).doubleValue)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let grouped = f.string(from: NSDecimalNumber(decimal: d)) ?? plain
        return text.contains(plain) || text.contains(grouped)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - On-device AI

/// What the on-device model is asked to fill in.
@Generable(description: "Details of a purchase or refund found in an email")
struct ReceiptFields {
    @Guide(description: "True only if this email confirms a payment that has already been taken from the reader, or a refund already made. False for promotions, newsletters, shipping or delivery updates, declined or failed payments, reminders about future charges, statements, and account notices.")
    var isReceipt: Bool
    @Guide(description: "True only if the email says money was returned to the reader (a refund or reversal). An order being picked up, shipped or delivered is not a refund.")
    var isRefund: Bool
    @Guide(description: "The business that took the payment, as a short name: the store, restaurant, app or service (for example Amazon, Uber, Netflix). Never a product name. Not the payment company or bank.")
    var merchant: String
    @Guide(description: "The final total actually charged, digits only with two decimals, e.g. 42.50. Empty if there isn't one.")
    var total: String
    @Guide(description: "Three-letter currency code of the total, e.g. AUD, SGD, USD, GBP.")
    var currency: String
    @Guide(description: "The last 4 digits of the card used, if shown. Empty otherwise.")
    var cardLast4: String
}

enum ReceiptAI {
    /// Whether Apple Intelligence can run here (supported device, turned on, model ready).
    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    /// Reads one email with the on-device model. Returns nil when the model
    /// says it isn't a receipt, or when its answer can't be checked against
    /// the email text.
    static func read(_ msg: EmailParsers.Message) async -> EmailRecord? {
        guard isAvailable, GenericReceipts.worthReading(msg) else { return nil }
        let text = EmailParsers.normalize(msg.body)
        let session = LanguageModelSession(instructions: """
            You read one email and extract the purchase it confirms. Only use facts written in the email. \
            If a detail isn't in the email, leave it empty. Never guess an amount.
            """)
        let prompt = """
            From: \(msg.from)
            Subject: \(msg.subject)

            \(text.prefix(3500))
            """
        do {
            let fields = try await session.respond(to: prompt, generating: ReceiptFields.self,
                                                   options: GenerationOptions(temperature: 0)).content
            let amount = fields.total.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
            guard fields.isReceipt, let d = Decimal(string: amount), d > 0,
                  GenericReceipts.appears(amount, in: text) else { return nil }
            let currency = fields.currency.count == 3 ? fields.currency.uppercased() : GenericReceipts.total(in: text)?.currency ?? Money.home
            let merchant = fields.merchant.isEmpty ? GenericReceipts.merchant(from: msg.from, subject: msg.subject) : fields.merchant
            let digits = fields.cardLast4.filter(\.isNumber)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return EmailRecord(
                id: "\(msg.id)-0", kind: fields.isRefund ? "refund" : "purchase", merchant: merchant, rawMerchant: merchant,
                platform: nil, amount: amount, currency: currency, card: "other",
                last4: digits.count == 4 && text.contains(digits) ? digits : GenericReceipts.last4(in: text),
                date: f.string(from: msg.date), note: "Read from email · check the amount", subscription: nil)
        } catch {
            log.error("On-device receipt reading failed: \(error.localizedDescription)")
            return nil
        }
    }
}
