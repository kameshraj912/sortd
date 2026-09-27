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

    @Parameter(title: "Transaction", description: "The whole Wallet transaction as text, if you have it.")
    var transaction: String?

    /// iOS hands the Wallet automation a Transaction, which Shortcuts can't
    /// turn into text ("couldn't convert from Transaction to Text"). So each
    /// part can be set on its own: drag the transaction's Amount, Merchant
    /// and Card into these.
    @Parameter(title: "Amount", description: "The transaction's amount.")
    var amount: String?

    @Parameter(title: "Shop", description: "The transaction's merchant.")
    var merchant: String?

    @Parameter(title: "Card", description: "The card that was tapped.")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant) in Sortd") {
            \.$card
            \.$transaction
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // #8 (spec 2026-09-26): never crash the process if the store can't
        // open — queue the already-resolved fields instead.
        guard case .success(let container) = SpendStore.containerForIntent() else {
            let resolved = Self.resolvedFields(transaction: transaction, amount: amount, merchant: merchant, card: card)
            let message = await TapQueue.saveForLater(merchant: resolved.merchant, amount: resolved.amount, card: resolved.card)
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
        let r = try await Self.handle(transaction, amount: amount, merchant: merchant, card: card,
                                      in: container.mainContext, book: .shared)
        // The app may not be running: update the widget before Shortcuts ends.
        WidgetBridge.refresh(from: container.mainContext)
        return .result(dialog: IntentDialog(stringLiteral: r.message))
    }

    /// Combines the free-text transaction with any fields set on their own
    /// (explicit fields win: they came straight from the transaction, not
    /// from text somebody had to format). Pure, so both `handle` and
    /// `perform`'s store-failure fallback can reuse it — a tap queued for
    /// later gets the same resolved fields it would otherwise have logged.
    ///
    /// A lone card name in the free text ("Visa Debit ••4821", known bug
    /// U6) is never accepted as a merchant: `WalletTapText.parse` has
    /// already put it in `card`, and text that only names a card is not a
    /// shop even when parsing found nothing else at all.
    nonisolated static func resolvedFields(transaction text: String?, amount: String?, merchant: String?,
                                           card: String?) -> (merchant: String?, amount: String?, card: String?) {
        var parts = WalletTapText.parse(text ?? "")
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if parts.merchant == nil, parts.amount == nil, !raw.isEmpty, !WalletTapText.looksLikeCard(raw) {
            parts.merchant = String(raw.prefix(60))
        }
        func kept(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
        if let amount = kept(amount) { parts.amount = amount }
        if let merchant = kept(merchant) { parts.merchant = merchant }
        if let card = kept(card) { parts.card = card }
        return (parts.merchant, parts.amount, parts.card)
    }

    @MainActor
    static func handle(_ text: String?, amount: String? = nil, merchant: String? = nil, card: String? = nil,
                       in context: ModelContext, book: CardBook,
                       now: Date = .now, debugForceSaveFailure: Bool = false) async throws -> LogPurchaseIntent.Outcome {
        let resolved = resolvedFields(transaction: text, amount: amount, merchant: merchant, card: card)
        let result = try await LogPurchaseIntent.handle(merchant: resolved.merchant, amount: resolved.amount,
                                                        card: resolved.card, in: context, book: book, now: now,
                                                        debugForceSaveFailure: debugForceSaveFailure)
        // A real Wallet tap reached the app and was kept (a ▶ test run has no
        // purchase; a legacy "Send a Test Tap" row is not a real tap).
        if result.transaction != nil, resolved.merchant != LogPurchaseIntent.legacyTestMerchant {
            Analytics.shared.track(.applePayTapLogged, ["merged": .bool(result.merged)])
        }
        return result
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
        // "CN¥" before the bare "¥" alternative, so yuan keep their "CN" and
        // aren't cut down to a yen sign.
        let marker = #"(?:[A-Z]{0,2}\$|CN¥|€|£|¥|₹|฿|₱|₩|RM|Rs\.?|[A-Z]{3})"#
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
