import Foundation
import FoundationModels

/// What the on-device model is asked to pull out of one typed line.
@Generable(description: "A purchase someone typed in their own words")
struct QuickEntryFields {
    @Guide(description: "The shop, restaurant, app or service paid, as a short proper name (for example Nando's, Uber, Woolworths). If no business is named, a short plain description of what was bought (for example Coffee, Parking).")
    var merchant: String
    @Guide(description: "The amount paid, digits only with up to two decimals, e.g. 5.50 or 20. Convert number words: \"twenty bucks\" is 20. Empty if no amount is given.")
    var amount: String
    @Guide(description: "Three-letter currency code only if the text names or shows one (sgd, S$, £, euros), else empty.")
    var currency: String
    @Guide(description: "How many days ago it happened: 0 for today or no date, 1 for yesterday or last night, 2 for the day before yesterday, up to 30.")
    var daysAgo: Int
    @Guide(description: "The best category for the purchase.", .anyOf(SpendCategory.allCases.map(\.name)))
    var category: String
}

/// Reads a typed line with Apple Intelligence, on the device.
///
/// `QuickEntry` stays the source of truth for anything it can read with
/// certainty (a written number, a currency symbol, "yesterday"). The model
/// adds what a pattern can't: a tidy shop name out of a sentence, amounts
/// written as words, and a category. The result still lands in the Add form
/// for checking, never straight in the store.
enum QuickEntryAI {
    struct Reading: Equatable, Sendable {
        var merchant: String
        var amount: Decimal?
        var currency: String?
        var daysAgo: Int
        var category: SpendCategory?
    }

    static var isAvailable: Bool { ReceiptAI.isAvailable }

    static func read(_ input: String) async -> Reading? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailable, !text.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: """
            You turn one short line someone typed about a purchase into its details. \
            Only use what the line says. Never invent an amount or a date.
            """)
        do {
            let fields = try await session.respond(to: String(text.prefix(300)), generating: QuickEntryFields.self,
                                                   options: GenerationOptions(temperature: 0)).content
            return merge(fields, typed: text)
        } catch {
            log.error("Quick entry reading failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The model's answer, checked against the line and the plain reader.
    static func merge(_ fields: QuickEntryFields, typed text: String) -> Reading? {
        let plain = QuickEntry.read(text)

        // A written number beats the model's reading of it.
        let modelAmount = Decimal(string: fields.amount.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ""))
        let amount = plain?.amount ?? modelAmount.flatMap { $0 > 0 && $0 < 1_000_000 ? $0 : nil }

        // Only keep a currency the line actually shows.
        let code = fields.currency.uppercased()
        let modelCurrency = code.count == 3 && Money.supported.contains(code) && mentionsCurrency(code, in: text) ? code : nil

        let merchant = fields.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = merchant.isEmpty ? plain?.merchant ?? "" : String(merchant.prefix(60))
        guard !name.isEmpty || amount != nil else { return nil }

        return Reading(
            merchant: name,
            amount: amount,
            currency: plain?.currency ?? modelCurrency,
            daysAgo: plain.flatMap { $0.daysAgo > 0 ? $0.daysAgo : nil }
                ?? (mentionsWhen(text) ? min(max(fields.daysAgo, 0), 30) : 0),
            category: SpendCategory.allCases.first { $0.name == fields.category }.flatMap { $0 == .other ? nil : $0 })
    }

    /// "sgd", "S$", "euros"… anything in the line that points at `code`.
    private static func mentionsCurrency(_ code: String, in text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains(code.lowercased()) { return true }
        let hints: [String: [String]] = [
            "SGD": ["s$", "sing"], "AUD": ["a$", "aussie"], "USD": ["us$", "usd", "us dollar"],
            "GBP": ["£", "pound", "quid"], "EUR": ["€", "euro"], "MYR": ["rm", "ringgit"],
            "INR": ["₹", "rupee"], "NZD": ["nz$"], "HKD": ["hk$"], "JPY": ["¥", "yen"],
        ]
        return hints[code]?.contains { has($0, in: lower) } ?? false
    }

    /// Only trust the model's date when the line talks about time at all.
    static func mentionsWhen(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = ["ago", "yesterday", "last", "night", "week", "morning", "day",
                     "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                     "mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        return words.contains { has($0, in: lower) }
    }

    /// `word` as a whole word (or symbol) in `text`, so "rm" isn't found in "farm".
    private static func has(_ word: String, in text: String) -> Bool {
        guard word.first?.isLetter == true else { return text.contains(word) }
        let pattern = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
