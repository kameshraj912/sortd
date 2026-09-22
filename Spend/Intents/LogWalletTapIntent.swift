import AppIntents
import SwiftData

/// One-field version of Log Purchase for the Wallet automation: pick the
/// Transaction once and Sortd pulls out the amount, shop and card itself.
/// Shortcuts turns the transaction into text; its exact layout isn't
/// documented, so `WalletTapText` reads it loosely.
struct LogWalletTapIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Wallet Tap"
    static let description = IntentDescription(
        "Logs an Apple Pay tap in Sortd. In a Wallet automation, set Transaction to the Shortcut Input.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Transaction", description: "Pick Shortcut Input (the Wallet transaction).")
    var transaction: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$transaction) in Sortd")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = try await Self.handle(transaction, in: SpendStore.container.mainContext, book: .shared)
        // The app may not be running: update the widget before Shortcuts ends.
        WidgetBridge.refresh(from: SpendStore.container.mainContext)
        return .result(dialog: IntentDialog(stringLiteral: r.message))
    }

    @MainActor
    static func handle(_ text: String?, in context: ModelContext, book: CardBook,
                       now: Date = .now) async throws -> LogPurchaseIntent.Outcome {
        var parts = WalletTapText.parse(text ?? "")
        // Test runs send nothing; any text at all is a real tap, so never drop it.
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if parts.merchant == nil, parts.amount == nil, !raw.isEmpty {
            parts.merchant = String(raw.prefix(60))
        }
        return try await LogPurchaseIntent.handle(merchant: parts.merchant, amount: parts.amount,
                                                  card: parts.card, in: context, book: book, now: now)
    }
}

/// Splits the text Shortcuts makes from a Wallet transaction into amount,
/// merchant and card. Pure, so it's tested.
nonisolated enum WalletTapText {
    struct Parts: Equatable { var amount: String?; var merchant: String?; var card: String? }

    static func parse(_ text: String) -> Parts {
        // Fields may come one per line, as "Key: value" pairs, or on one
        // line separated by commas.
        var lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count == 1, lines[0].contains(", ") {
            lines = lines[0].components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var parts = Parts()
        var rest: [String] = []
        for line in lines {
            if let (key, value) = keyValue(line) {
                switch key {
                case "amount": parts.amount = value; continue
                case "merchant": parts.merchant = value; continue
                case "card", "card or pass", "pass": parts.card = value; continue
                case "name", "transaction", "date", "time": continue
                default: break
                }
            }
            if looksLikeDate(line) { continue }
            if parts.amount == nil, let money = money(in: line) {
                parts.amount = money
                // "Seven Seeds A$4.50 NAB Visa Debit": keep what's around it.
                let leftover = line.replacingOccurrences(of: money, with: "\n")
                    .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                rest.append(contentsOf: leftover)
            } else {
                rest.append(line)
            }
        }
        // The card is the last line that names a card; the shop is the first other one.
        if parts.card == nil, let i = rest.lastIndex(where: looksLikeCard) { parts.card = rest.remove(at: i) }
        if parts.merchant == nil, let first = rest.first { parts.merchant = first }
        return parts
    }

    private static func keyValue(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard key.count <= 14, !key.contains(where: \.isNumber), !value.isEmpty else { return nil }
        return (key, value)
    }

    /// A money amount inside the text: a currency sign or code next to the
    /// number, or a number with cents. "Cafe 21" and "Zone 3" are not money.
    static func money(in s: String) -> String? {
        let sign = #"(?:-|−)?"#
        let marker = #"(?:[A-Z]{0,2}\$|€|£|¥|₹|RM|Rs\.?|[A-Z]{3})"#
        // Grouped thousands ("1,234.50", "1.234,50") or a plain run of digits
        // ("1234.50" — the old pattern stopped at 3 digits and read A$123).
        let number = #"(?:\d{1,3}(?:[,.\s]\d{3})+|\d+)(?:[.,]\d{2})?"#
        let patterns = [
            sign + marker + #"\s?"# + number,                  // A$4.50, SGD 6.20, -$5
            sign + number + #"\s?(?:[A-Z]{3})\b"#,             // 6.20 SGD
            sign + #"\d+[.,]\d{2}\b"#,                          // 4.50
        ]
        let ns = s as NSString
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p) else { continue }
            // Every match, not just the first: in "NAB 4821 A$4.50" the first
            // hit ("NAB 4821") is rejected and the real amount comes after it.
            for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let hit = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
                // A bare code must be a real currency ("THB 120", not "ABC 12").
                if let code = hit.uppercased().split(whereSeparator: { !$0.isLetter }).first, code.count == 3,
                   !hit.contains("$"), AmountParser.currency(in: String(code)) == nil { continue }
                return hit
            }
        }
        return nil
    }

    static func looksLikeCard(_ s: String) -> Bool {
        let words = Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !words.isDisjoint(with: ["card", "visa", "mastercard", "amex", "debit", "credit", "eftpos", "unionpay", "rupay"]) {
            return true
        }
        // "••4821", "…4821", "*4821": a masked card number.
        return s.range(of: #"[•·…*]\s?\d{4}\b"#, options: .regularExpression) != nil
    }

    static func looksLikeDate(_ s: String) -> Bool {
        s.range(of: #"^\d{1,2}[ /.-](\d{1,2}|[A-Za-z]{3,9})[ /.-]\d{2,4}|^\d{4}-\d{2}-\d{2}|\b\d{1,2}:\d{2}\b"#,
                options: .regularExpression) != nil
    }
}
