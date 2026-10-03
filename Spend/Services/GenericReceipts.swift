import Foundation
import FoundationModels

/// Shared receipt-text helpers: the total, currency and card digits in a
/// block of text. Used by the receipt camera (`ReceiptScanner`) and the
/// on-device reading below.
///
/// Guardrail: an amount is only accepted if it appears word-for-word in the
/// text, so nothing is invented.
nonisolated enum GenericReceipts {

    /// The best "total" amount: grand totals beat plain totals, and the last
    /// one wins (receipts list subtotals first).
    static func total(in text: String) -> (currency: String, amount: String)? {
        // Currency codes must be real uppercase codes: "Total GST 4.09" is a tax line, not money in "GST".
        // EFTPOS slips write a code and a sign together ("TOTAL AUD $45.00"); the code wins.
        let signs = #"A\$|AU\$|S\$|US\$|NZ\$|C\$|HK\$|\$"#
        let money = #"((?-i:[A-Z]{3})\s?(?:"# + signs + #")|"# + signs
            + #"|RM|Rp|₹|£|€|¥|(?-i:[A-Z]{3}))\s?(\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2})"#
        let tiers = [
            #"(?:grand total|total charged|amount charged|amount paid|total paid|you paid|payment of|purchase of|charged)"#,
            #"(?:order total|total amount|total due|amount due|total \(incl[^)]*\))"#,
            #"(?:total)"#,
        ]
        for label in tiers {
            // A whole word: "SUBTOTAL" and "SUB TOTAL" are not the total.
            let pattern = notInsideWord + label + #"\s*[:\-–]?\s*"# + money
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            // Last valid match wins (receipts list subtotals first).
            for m in matches.reversed() {
                var symbol = ns.substring(with: m.range(at: 1)).filter { !$0.isWhitespace }
                if symbol.count > 3, symbol.prefix(3).allSatisfy({ $0.isLetter && $0.isUppercase }) {
                    symbol = String(symbol.prefix(3))
                }
                if symbol.count == 3, symbol.allSatisfy(\.isLetter), !Locale.commonISOCurrencyCodes.contains(symbol) { continue }
                let value = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ",", with: "")
                guard let d = Decimal(string: value), d > 0 else { continue }
                return (currencyCode(symbol), value)
            }
        }
        return nil
    }

    /// Put before a total label: not part of a longer word, and not "SUB TOTAL".
    static let notInsideWord = #"(?<![a-z])(?<!sub )(?<!sub-)"#

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

    /// "ending in 1234", "•••• 1234", "**** 1234", "xxxx1234", "card no. 1234".
    static func last4(in text: String) -> String? {
        let pattern = #"(?:ending(?: in)?|ends in|[•*xX]{2,}|card (?:no\.?|number)\s?[:#]?)\s*(\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// True when `amount` (e.g. "42.50") is written in the text, with or
    /// without a thousands comma. Used to reject any invented amount.
    static func appears(_ amount: String, in text: String) -> Bool {
        guard let d = Decimal(string: amount) else { return false }
        // Whole number, not part of a bigger one: "5.00" must not match "$15.00".
        func standalone(_ s: String) -> Bool {
            let p = #"(?<![\d.,])"# + NSRegularExpression.escapedPattern(for: s) + #"(?![\d])"#
            return text.range(of: p, options: .regularExpression) != nil
        }
        let plain = String(format: "%.2f", NSDecimalNumber(decimal: d).doubleValue)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let grouped = f.string(from: NSDecimalNumber(decimal: d)) ?? plain
        let n = NSDecimalNumber(decimal: d)
        let isWhole = n.doubleValue == n.doubleValue.rounded()
        let whole = isWhole ? String(Int(n.doubleValue)) : nil
        f.minimumFractionDigits = 0
        let groupedWhole = isWhole ? f.string(from: n) : nil
        let oneDecimal = String(format: "%.1f", NSDecimalNumber(decimal: d).doubleValue)
        return [plain, grouped, whole, groupedWhole, oneDecimal].compactMap { $0 }.contains(where: standalone)
    }
}

// MARK: - On-device AI

/// What the on-device model is asked to fill in.
@Generable(description: "Details of a purchase or refund found in the text of a receipt")
struct ReceiptFields {
    @Guide(description: "True only if this text confirms a payment that has already been taken from the reader, or a refund already made. False for promotions, newsletters, shipping or delivery updates, declined or failed payments, reminders about future charges, statements, and account notices.")
    var isReceipt: Bool
    @Guide(description: "True only if the text says money was returned to the reader (a refund or reversal). An order being picked up, shipped or delivered is not a refund.")
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

    /// Reads the text of a paper receipt (from the camera) with the on-device
    /// model. Same guardrail as above: the total must appear in the text,
    /// or no amount is returned. Returns nil when the model can't run or fails.
    /// The date is left to `ReceiptScanner.date(in:)`.
    static func read(text: String) async -> ReceiptReading? {
        guard isAvailable, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let session = LanguageModelSession(instructions: """
            You read the text of one paper receipt, taken with a phone camera, and extract the purchase. \
            Only use facts written in the text. If a detail isn't there, leave it empty. Never guess an amount. \
            The total is the final amount paid, not a subtotal, tax (GST) or change.
            """)
        do {
            let fields = try await session.respond(to: String(text.prefix(3500)), generating: ReceiptFields.self,
                                                   options: GenerationOptions(temperature: 0)).content
            let amount = fields.total.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
            let checked = (Decimal(string: amount) ?? 0) > 0 && GenericReceipts.appears(amount, in: text)
            let merchant = fields.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = fields.cardLast4.filter(\.isNumber)
            return ReceiptReading(
                merchant: merchant.isEmpty ? nil : merchant,
                amount: checked ? amount : nil,
                currency: checked && fields.currency.count == 3 ? fields.currency.uppercased() : nil,
                last4: digits.count == 4 && text.contains(digits) ? digits : nil,
                date: nil)
        } catch {
            log.error("On-device receipt scan reading failed: \(error.localizedDescription)")
            return nil
        }
    }
}
