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
/// money coming in, bill reminders and offers. Only a spend word with one
/// amount and a shop is a purchase; anything else is `.notAPurchase` and saves nothing,
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

    // MARK: - Refusals, on every notification

    /// Phrases that say a notification is not a purchase. Checked on every
    /// notification, before Wallet's reader or this one (review, 8 Oct
    /// 2026): a short bank line ("Available balance $1,204.11", "Get $20
    /// cashback") is not a sentence, and Wallet's reader logged it. Phrases,
    /// not bare words, so a shop Wallet names on its own line ("Balance
    /// Yoga") still logs.
    static func refusal(_ text: String) -> WalletNotification.Reading? {
        if any(codePhrases, in: text) { return .notAPurchase }
        if has(WalletNotification.notCompletedPattern, in: text) || has(#"\bblocked\b"#, in: text) { return .notCompleted }
        if any(offerPhrases, in: text) || any(laterPhrases, in: text) || any(notDonePhrases, in: text) {
            return .notAPurchase
        }
        // A refund "credited to your card" is still a refund, as in Wallet's reader.
        if !has(WalletNotification.refundPattern, in: text), any(moneyInPhrases, in: text) { return .moneyIn }
        if any(accountPhrases, in: text) { return .notAPurchase }
        // A balance alone is an alert; a balance after a purchase's own
        // amount ("You spent $23.40 at DOORDASH. Available balance $976.60")
        // is the purchase, read below.
        if any(balancePhrases, in: text), clearAmountCount(in: text) < 2 { return .notAPurchase }
        return nil
    }

    /// How many different clear amounts the text holds, up to 3.
    private static func clearAmountCount(in text: String) -> Int {
        var rest = text, count = 0
        while count < 3, let m = WalletTapText.money(in: rest), WalletTapText.isClearAmount(m) {
            count += 1
            rest = rest.replacingOccurrences(of: m, with: " ")
        }
        return count
    }

    /// One-time codes and approvals. A code message can carry an amount and
    /// a shop ("for a payment of $31.80 to UBER").
    private static let codePhrases = [
        #"\b(?:otp|netcode|one[- ]time (?:pass(?:word|code)|code)|verification code|security code)\b"#,
        #"\bcode\s*(?:is\s*)?:?\s*\d{4,}"#,
        #"\b(?:do not|don['’]t|never) share\b"#,
        #"\bto (?:approve|confirm|verify|authori[sz]e)\b"#,
        #"\bapprove (?:your|this|the)\b"#,
        #"\bdid you (?:just )?(?:try|make|attempt)\b"#,
    ]
    /// Offers: "spend $100" in an offer is not a purchase.
    private static let offerPhrases = [
        #"\bcash ?back\b"#, #"\boffers?\b"#, #"\bwin\b"#, #"\bbonus points?\b"#,
        #"\b(?:earn|collect)\s+(?:\d|double|triple|bonus|extra|up to|points)"#,
        #"\d\s?%\s?(?:off|back)\b"#, #"\blast chance\b"#, #"\band save\b"#,
    ]
    /// Money that is owed or will move later: a bill, a scheduled payment.
    private static let laterPhrases = [
        #"\b(?:is|are) due\b"#, #"\bdue\s+(?:on|by|date|today|tomorrow|in|\d)"#, #"\b(?:bill|payment) due\b"#,
        #"\boverdue\b"#, #"\bscheduled\b"#, #"\bauto-?pay\b"#, #"\bmake a payment\b"#, #"\blate fees?\b"#,
        #"\bwill be (?:paid|charged|debited|taken|deducted|processed|withdrawn)\b"#, #"\bminimum (?:re)?payment\b"#,
    ]
    /// Not finished, or undone.
    private static let notDonePhrases = [
        #"\b(?:pending|on hold|pre-?auth\w*|reversed|reversal|cancell?ed)\b"#, #"\bhold (?:of|for|on)\b"#,
    ]
    /// Money coming to the person. Not a bare "received" or "deposit":
    /// Wallet's short lines can carry those around a real purchase.
    private static let moneyInPhrases = [
        #"\b(?:you(?:['’]ve| have)? received|received from|sent you|paid you|deposited|deposit (?:to|into)|credited|salary|transfer from)\b"#,
        #"\binto your (?:\w+ )?account\b"#, #"\bha(?:s|ve) arrived\b"#,
    ]
    /// A balance.
    private static let balancePhrases = [
        #"\b(?:available|account|current|your) balance\b"#, #"\bbalance\s*(?::|is\b|was\b|of\b|now\b)"#,
        #"\bavail(?:able)?\.? bal\b"#,
    ]
    /// Limits, interest and money moved between the person's own accounts
    /// or to their own card.
    private static let accountPhrases = [
        #"\b(?:credit|card|spending) limit\b"#, #"\blimit (?:is|was|has|increased|decreased|raised|lowered|changed|now)\b"#,
        #"\blimit increase\b"#,
        #"\binterest (?:paid|charged|earned|credited|of|rate)\b"#, #"\d\s+interest\b"#,
        #"\btransfer (?:from|to|of)\b"#, #"\btransferred\b"#,
        #"\bfrom your \w+ account\b"#, #"\bto (?:your |\w+ )?savings\b"#, #"\bsavings (?:account|ending|acc)\b"#,
        #"\b(?:paid|moved|sent)\b.{0,30}?\bto your\b"#,
    ]

    // MARK: - Reading

    /// Money coming in that `refusal` leaves alone because Wallet's short
    /// lines could carry it. A bank's sentence can't: a bare "received" is
    /// money in, and so is a bare "deposit" with no spend word (paying a
    /// booking deposit is spending).
    private static let receivedPattern = #"\breceived\b"#
    private static let depositPattern = #"\bdeposit\b"#
    /// Words that say money left the account. Not "spend": that is an
    /// offer's word ("Spend $50 and get 10% back").
    private static let spendPattern =
        #"\b(?:spent|purchases?|paid|payment (?:of|to)|charged|transaction (?:of|at)|debited|used at|card purchase)\b"#

    /// What the bank's notification says. `isKnownCard` is a `CardBook`
    /// match, for a card named only by its name ("with YouTrip").
    static func read(_ text: String, isKnownCard: (String) -> Bool = { _ in false }) -> WalletNotification.Reading {
        if let refused = refusal(text) { return refused }
        let spend = has(spendPattern, in: text)
        let refund = has(WalletNotification.refundPattern, in: text)
        if !refund, has(receivedPattern, in: text) || (!spend && has(depositPattern, in: text)) { return .moneyIn }
        guard refund || spend, let amount = WalletTapText.money(in: text),
              let value = AmountParser.parse(amount)?.amount, value > 0 else { return .notAPurchase }
        // Two amounts are not one purchase ("$23.40 at DOORDASH and $5.00
        // at UBER", a weekly total), unless the second is the balance. No
        // shop is not a purchase either: "You've spent $500 this week".
        guard !hasSecondAmount(text, besides: amount),
              let shop = merchant(in: text, amount: amount, refund: refund) else { return .notAPurchase }
        let signed = refund && !AmountParser.isNegative(amount) ? "-" + amount : amount
        return .payment(amount: signed, merchant: shop, card: card(in: text, isKnownCard: isKnownCard))
    }

    /// Another clear amount in the text, other than one straight after
    /// "balance" or "bal".
    private static func hasSecondAmount(_ text: String, besides amount: String) -> Bool {
        let rest = text.replacingOccurrences(of: amount, with: " ")
        guard let second = WalletTapText.money(in: rest), WalletTapText.isClearAmount(second),
              let at = rest.range(of: second) else { return false }
        let before = String(rest[..<at.lowerBound])
        return before.range(of: #"\bbal(?:ance)?(?:\s+(?:is|of|now))?[\s:.\-]*$"#,
                            options: [.regularExpression, .caseInsensitive]) == nil
    }

    // MARK: - Shop

    /// The shop: what follows "at", "to", "@" or "with merchant" (and
    /// "from" for a refund), the first one after the amount, else the first
    /// anywhere; never "to your…". A refund with none takes the name before
    /// "refunded" ("DOORDASH refunded $5.00"). Cut where the sentence moves
    /// on ("on", "with", "for", "is", "in", "card", a date, another amount,
    /// "—", "?"), with a trailing full stop and "Pty Ltd" taken off.
    private static func merchant(in text: String, amount: String, refund: Bool) -> String? {
        let marker = (refund ? #"\b(?:from|at|to)\s+"# : #"\b(?:at|to)\s+"#) + #"|@\s*|\bwith merchant\s+"#
        guard let regex = try? NSRegularExpression(pattern: marker, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            // "to your card ending 4821" names the person's card, not a shop.
            .filter { ns.substring(from: $0.range.upperBound).range(of: #"^(?:your|you|my)\b"#,
                                                                     options: [.regularExpression, .caseInsensitive]) == nil }
        let amountEnd = ns.range(of: amount).upperBound
        var name: String
        if let hit = matches.first(where: { $0.range.location >= amountEnd }) ?? matches.first {
            name = ns.substring(from: hit.range.upperBound)
        } else if refund, let shape = text.range(of: #"(?m)^[^\n]+?(?=\s+(?:has\s+)?refunded\b)"#,
                                                  options: [.regularExpression, .caseInsensitive]) {
            name = String(text[shape])
        } else {
            return nil
        }
        if let cut = name.range(of: stopPattern, options: [.regularExpression, .caseInsensitive]) {
            name = String(name[..<cut.lowerBound])
        }
        // "at DOORDASH $5.00": no amount is part of the name.
        if let other = WalletTapText.money(in: name), let at = name.range(of: other) {
            name = String(name[..<at.lowerBound])
        }
        name = name.trimmingCharacters(in: trailing)
        if let pty = name.range(of: #"\s+pty\.?\s+ltd\.?$"#, options: [.regularExpression, .caseInsensitive]) {
            name = String(name[..<pty.lowerBound]).trimmingCharacters(in: trailing)
        }
        return name.isEmpty ? nil : name
    }

    /// Where the shop's name ends.
    private static let stopPattern =
        #"\s+(?:on|with|using|for|was|via|card|ending|is|has|will|in|refunded|bal(?:ance)?|avail(?:able)?)\b|\s*[—–]|\?|[.,;!]\s|\n|\s\d{1,2}[ /.-](?:\d{1,2}\b|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b)"#

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

    private static func any(_ patterns: [String], in text: String) -> Bool {
        patterns.contains { has($0, in: text) }
    }
}
