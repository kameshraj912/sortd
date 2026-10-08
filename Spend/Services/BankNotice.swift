import Foundation

/// A bank app's own notification, as the iOS 27 Notification trigger hands
/// it over when the person adds their bank's app to the shortcut (8 Oct
/// 2026, spec `2026-10-03-bank-app-notifications.md`). Some banks (ANZ,
/// CommBank) send Wallet nothing for in-app Apple Pay, and sometimes nothing
/// for a tap, but their own app does.
///
/// A bank writes a sentence ("You spent $23.40 at DOORDASH with your card
/// ending 4821."), not Wallet's short lines. This reads the amount, the shop
/// after "at", "to" or "@", and the card from its masked digits.
///
/// It refuses more than it takes: a bank app also sends codes, balances,
/// money coming in, bill reminders and offers. Only a spend word with an
/// amount is a purchase; anything else is `.notAPurchase` and saves nothing,
/// not even a "needs a check" row. A wrong purchase is worse than a missed
/// one. Pure, so it is tested without a store.
nonisolated enum BankNotice {
    // MARK: - Sentence or Wallet's short lines

    /// Words a bank's sentence carries and Wallet's short lines don't.
    private static let sentenceWordPattern =
        #"\b(?:spent|spend|purchases?|paid|payments?|charged|transactions?|debited|used at|received|deposit(?:ed)?|credited|balance|declined|refunds?|otp|verification code|cashback|due|salary|transfer)\b"#

    /// True when the text reads as a bank's sentence, not Wallet's short
    /// lines ("NAB Visa Debit\nDoorDash\nA$23.40"). One line of four words
    /// or more with a spend or money word in it, or a line of six words or
    /// more that holds an amount. A word alone is not enough: a shop Wallet
    /// names on its own line ("Balance Yoga") must not make Wallet's
    /// notification read as a bank's. A line that is only Wallet's own name
    /// ("Apple Pay", "Wallet") means the notification is Wallet's.
    static func isSentence(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.contains(where: { WalletTapText.walletNames.contains($0.lowercased()) }) { return false }
        return lines.contains { line in
            let words = line.split(separator: " ").filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
            if words >= 4, has(sentenceWordPattern, in: line) { return true }
            return words >= 6 && WalletTapText.money(in: line) != nil
        }
    }

    // MARK: - Reading

    /// One-time codes. Checked first: a code message can carry an amount
    /// and a shop ("Amount SGD 31.80 at UBER").
    private static let codePattern = #"\b(?:otp|one[- ]time (?:pass(?:word|code)|code)|verification code|do not share)\b"#
    /// Offers. Checked before the spend words: "spend $100" in an offer is
    /// not a purchase.
    private static let offerPattern = #"\b(?:cash ?back|offers?|win|won)\b|\d\s?% off\b"#
    /// A bill reminder: money that is owed, not spent yet.
    private static let duePattern = #"\b(?:is due|are due|due (?:on|by|date|today|tomorrow)|bill due|payment due|overdue)\b"#
    /// Money coming in. A bare "deposit" only counts when no spend word is
    /// there too: paying a booking deposit is spending.
    private static let moneyInPattern =
        #"\b(?:you(?:['’]ve| have)? received|received|deposited|deposit (?:to|into)|credited|salary|transfer from|sent you)\b"#
    private static let depositPattern = #"\bdeposit\b"#
    /// Words that say money left the account.
    private static let spendPattern =
        #"\b(?:spent|spend|purchases?|paid|payment (?:of|to)|charged|transaction (?:of|at)|debited|used at|card purchase)\b"#

    /// What the bank's notification says. `isKnownCard` is a `CardBook`
    /// match, for a card named only by its name ("with YouTrip").
    static func read(_ text: String, isKnownCard: (String) -> Bool = { _ in false }) -> WalletNotification.Reading {
        if has(codePattern, in: text) || has(offerPattern, in: text) { return .notAPurchase }
        if has(WalletNotification.notCompletedPattern, in: text) { return .notCompleted }
        if has(duePattern, in: text) { return .notAPurchase }
        let spend = has(spendPattern, in: text)
        // A refund is checked before money in, as in Wallet's reader: a
        // refund "credited to your card" is still a refund.
        let refund = has(WalletNotification.refundPattern, in: text)
        if !refund, has(moneyInPattern, in: text) || (!spend && has(depositPattern, in: text)) { return .moneyIn }
        guard refund || spend, let amount = WalletTapText.money(in: text),
              let value = AmountParser.parse(amount)?.amount, value > 0 else { return .notAPurchase }
        let signed = refund && !AmountParser.isNegative(amount) ? "-" + amount : amount
        return .payment(amount: signed, merchant: merchant(in: text, amount: amount, refund: refund),
                        card: card(in: text, isKnownCard: isKnownCard))
    }

    // MARK: - Shop

    /// The shop: what follows "at", "to", "@" or "with merchant" (and
    /// "from" for a refund), the first one after the amount, else the first
    /// anywhere. Cut where the sentence moves on ("on", "with", "using",
    /// "for", "card", "ending", a date), with a trailing full stop and "Pty
    /// Ltd" taken off.
    private static func merchant(in text: String, amount: String, refund: Bool) -> String? {
        let marker = (refund ? #"\b(?:from|at|to)\s+"# : #"\b(?:at|to)\s+"#) + #"|@\s*|\bwith merchant\s+"#
        guard let regex = try? NSRegularExpression(pattern: marker, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let amountEnd = ns.range(of: amount).upperBound
        guard let hit = matches.first(where: { $0.range.location >= amountEnd }) ?? matches.first else { return nil }
        var name = ns.substring(from: hit.range.upperBound)
        if let cut = name.range(of: stopPattern, options: [.regularExpression, .caseInsensitive]) {
            name = String(name[..<cut.lowerBound])
        }
        // "at DOORDASH $23.40": the amount is not part of the name.
        if let at = name.range(of: amount) { name = String(name[..<at.lowerBound]) }
        name = name.trimmingCharacters(in: trailing)
        if let pty = name.range(of: #"\s+pty\.?\s+ltd\.?$"#, options: [.regularExpression, .caseInsensitive]) {
            name = String(name[..<pty.lowerBound]).trimmingCharacters(in: trailing)
        }
        return name.isEmpty ? nil : name
    }

    /// Where the shop's name ends.
    private static let stopPattern =
        #"\s+(?:on|with|using|for|was|via|card|ending)\b|[.,;!]\s|\n|\s\d{1,2}[ /.-](?:\d{1,2}\b|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b)"#

    private static let trailing = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,;:!"))

    // MARK: - Card

    /// Masked card digits: "ending 4821", "ending in 4821", "•••• 4821",
    /// "x4821", "*4821".
    private static let maskedDigitsPattern = #"(?:\bending(?:\s+in)?|[•·…*]+|\b[xX]+)\s?(\d{4})\b"#

    /// The card's last four digits, else a name `isKnownCard` matches ("with
    /// YouTrip", or a line of its own such as the bank's name), else nil.
    private static func card(in text: String, isKnownCard: (String) -> Bool) -> String? {
        let ns = text as NSString
        if let regex = try? NSRegularExpression(pattern: maskedDigitsPattern),
           let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: m.range(at: 1))
        }
        var fragments: [String] = []
        if let regex = try? NSRegularExpression(pattern: #"\b(?:with|using|on)\s+(?:your\s+|my\s+|the\s+)?([^.,;\n]+)"#,
                                                options: [.caseInsensitive]) {
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                fragments.append(ns.substring(with: m.range(at: 1)).trimmingCharacters(in: trailing))
            }
        }
        // A line with no amount, such as the bank's name as the title.
        fragments += text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: trailing) }
            .filter { WalletTapText.money(in: $0) == nil }
        return fragments.first { !$0.isEmpty && isKnownCard($0) }
    }

    private static func has(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
