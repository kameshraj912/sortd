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
/// one. Refusal phrases run on Wallet's short lines too; bare refusal words
/// only on a bank's sentence (see `refusal`). Pure, so it is tested
/// without a store.
nonisolated enum BankNotice {
    // MARK: - Sentence or Wallet's short lines

    /// Words a bank's sentence carries and Wallet's short lines don't.
    private static let sentenceWordPattern =
        #"\b(?:spent|spend|purchases?|paid|payments?|charged|transactions?|debited|used at|received|deposit(?:ed)?|credited|balance|declined|refunds?|otp|verification code|cashback|due|transfer)\b"#

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

    // MARK: - Refusals

    /// What says a notification is not a purchase, in two strengths (review,
    /// 8 Oct 2026):
    /// - **Phrases** ("available balance", "is pending", "interest paid",
    ///   "was cancelled") run on every notification, Wallet's short lines
    ///   too, one line at a time (`lineRefusal`), so a short bank line
    ///   ("Available balance $1,204.11") is never logged by Wallet's reader.
    ///   A phrase never spans a line break.
    /// - **Bare words** ("pending", "interest", "offer", "win", "scheduled",
    ///   "hold", "cancelled", "salary", "blocked", "upcoming", "requires")
    ///   run only on a bank's sentence (`refusal`). On Wallet's lines they
    ///   would block real shops: "The Pending Co", "Interest Cafe", "Hold On
    ///   Pizza", "Salary Men Ramen".
    static func refusal(_ text: String) -> WalletNotification.Reading? {
        refusal(in: text, bareWords: true)
    }

    /// The phrases only, on each line of Wallet's short lines on its own.
    static func lineRefusal(_ text: String) -> WalletNotification.Reading? {
        for line in text.split(whereSeparator: \.isNewline) {
            if let refused = refusal(in: String(line), bareWords: false) { return refused }
        }
        return nil
    }

    private static func refusal(in text: String, bareWords: Bool) -> WalletNotification.Reading? {
        func hits(_ phrases: [String], _ words: [String]) -> Bool {
            any(phrases, in: text) || (bareWords && any(words, in: text))
        }
        if hits(codePhrases, codeWords) { return .notAPurchase }
        if has(WalletNotification.notCompletedPattern, in: text) || hits(blockedPhrases, blockedWords) { return .notCompleted }
        if hits(offerPhrases, offerWords) || hits(laterPhrases, laterWords) || hits(notDonePhrases, notDoneWords) {
            return .notAPurchase
        }
        // A refund "credited to your card" is still a refund, as in Wallet's reader.
        let refund = has(WalletNotification.refundPattern, in: text)
        if !refund, hits(moneyInPhrases, moneyInWords) { return .moneyIn }
        if any(accountPhrases, in: text) || (bareWords && !refund && any(accountWords, in: text)) { return .notAPurchase }
        // A balance alone is an alert; a balance after a purchase's own
        // amount ("You spent $23.40 at DOORDASH. Available balance $976.60")
        // is the purchase, read below.
        if any(balancePhrases, in: text), clearAmountCount(in: text) < 2 { return .notAPurchase }
        return nil
    }

    /// How many different clear amounts the text holds, up to 3.
    static func clearAmountCount(in text: String) -> Int {
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
        #"\b(?:approve|confirm) (?:your|this|the)\b"#,
        #"\bdid you (?:just )?(?:try|make|attempt)\b"#,
        #"\brequires? (?:authentication|approval|verification)\b"#,
    ]
    private static let codeWords = [#"\brequires\b"#]
    private static let blockedPhrases = [#"\b(?:was|been|transaction|card|payment) blocked\b"#]
    private static let blockedWords = [#"\bblocked\b"#]
    /// Offers: "spend $100" in an offer is not a purchase.
    private static let offerPhrases = [
        #"\bcash ?back\b"#, #"\bbonus points?\b"#, #"\bearn\s+(?:double|triple|bonus|extra|up to)\b"#,
        #"\bearn\s+\d[\d,]*\s+(?:bonus\s+)?points\b"#,
        #"\d\s?%\s?(?:off|back)\b"#, #"\blast chance\b"#, #"\band save\b"#, #"\bspecial offer\b"#,
    ]
    private static let offerWords = [#"\boffers?\b"#, #"\bwin\b"#, #"\b(?:earn|collect)\s+(?:\d|points)"#]
    /// Money that is owed or will move later: a bill, a scheduled payment.
    private static let laterPhrases = [
        #"\b(?:is|are) due\b"#, #"\bdue\s+(?:on|by|date|today|tomorrow|in|\d)"#, #"\b(?:bill|payment) due\b"#,
        #"\boverdue\b"#, #"\b(?:is|was|been) scheduled\b"#, #"\bscheduled (?:payment|transfer|debit)\b"#,
        #"\bpayment scheduled\b"#, #"\bauto-?pay\b"#, #"\bmake a payment\b"#, #"\blate fees?\b"#,
        #"\bwill be (?:paid|charged|debited|taken|deducted|processed|withdrawn|made)\b"#,
        #"\bminimum (?:re)?payment\b"#, #"\bupcoming (?:payment|bill|charge|debit)\b"#,
    ]
    private static let laterWords = [#"\bscheduled\b"#, #"\bcoming up\b"#, #"\bgoes out\b"#, #"\bupcoming\b"#]
    /// Not finished, or undone.
    private static let notDonePhrases = [
        #"\bpending (?:transaction|payment|purchase|charge)\b"#, #"\b(?:is|was|still|transaction|payment) pending\b"#,
        #"\bon hold\b"#, #"\bhold (?:placed|of)\b"#, #"\bpre-?auth\w*"#, #"\bauthori[sz]ation hold\b"#, #"\breversal\b"#,
        #"\b(?:was|been|transaction|payment|purchase) (?:reversed|cancell?ed|voided|reverted)\b"#,
    ]
    private static let notDoneWords = [
        #"\b(?:pending|reversed|cancell?ed|voided|reverted|authori[sz]ation)\b"#, #"\bhold (?:for|on)\b"#,
    ]
    /// Money coming to the person. Not a bare "received" or "deposit":
    /// Wallet's short lines can carry those around a real purchase.
    private static let moneyInPhrases = [
        #"\b(?:you(?:['’]ve| have)? received|received from|sent you|paid you|deposited|deposit (?:to|into)|credited|transfer from)\b"#,
        #"\binto your (?:\w+ )?account\b"#, #"\bha(?:s|ve) arrived\b"#,
        #"\bsalary (?:paid|received|credited|deposit\w*|payment)\b"#,
    ]
    private static let moneyInWords = [#"\bsalary\b"#]
    /// A balance.
    private static let balancePhrases = [
        #"\b(?:available|account|current|your|low) balance\b"#, #"\bbalance\s*(?::|is\b|was\b|of\b|now\b)"#,
        #"\bavail(?:able)?\.? bal\b"#,
    ]
    /// Limits, interest and money moved between the person's own accounts
    /// or to their own card.
    private static let accountPhrases = [
        #"\b(?:credit|card|spending) limit\b"#, #"\blimit (?:is|was|has|increased|decreased|raised|lowered|changed|now)\b"#,
        #"\blimit increase\b"#,
        #"\binterest (?:paid|charged|earned|credited|of|rate)\b"#,
        #"\btransfer (?:from|to|of)\b"#, #"\btransferred\b"#,
        #"\bfrom your \w+ account\b"#, #"\bto (?:your |\w+ )?savings\b"#, #"\bsavings (?:account|ending|acc)\b"#,
        #"\b(?:paid|moved|sent)\b.{0,30}?\bto your\b"#, #"\bmoved (?:to|from|into)\b"#,
        #"\byou (?:exchanged|converted)\b"#,
    ]
    /// "$25.00 interest", and a payment to a card ("to ANZ Credit Card",
    /// "to NAB Low Rate Card"): paying off the person's own card. Not after
    /// "with" or "using", where the card is the one that paid.
    private static let accountWords = [
        #"\d\s+interest\b"#,
        #"\bto\s+(?!your\b|my\b)(?:(?!with\b|using\b|on\b|via\b|at\b)[^\s.,;]+\s+){0,4}?(?:credit\s+)?card\b"#,
    ]

    // MARK: - Wallet's short lines: a bank's status, not a shop

    /// Words of a bank's status line ("Payment received", "Incoming PayNow",
    /// "Low balance", "Fee charged", "Hold placed").
    private static let statusWords: Set<String> = [
        "received", "incoming", "money", "added", "balance", "bal", "interest", "fee", "fees", "charged", "transfer",
        "transferred", "moved", "sent", "repayment", "payment", "payments", "spend", "spending", "reminder", "upcoming",
        "authorisation", "authorization", "hold", "reverted", "voided", "exchanged", "converted", "paynow", "osko",
        "bpay", "giro", "payid", "paylah", "salary",
    ]
    /// Words that ride along with a status word without naming a shop.
    private static let statusFiller: Set<String> = [
        "low", "new", "your", "alert", "notice", "this", "that", "week", "weekly", "month", "monthly", "today",
        "tomorrow", "successful", "successfully", "complete", "completed", "placed", "card", "account", "transaction",
        "a", "an", "the", "of", "to", "from", "in", "has", "been", "is", "was", "on", "for", "you", "we", "made",
    ]
    /// A top-up is a status only under a bank's own title: "Myki · Top up ·
    /// A$20.00" is a purchase.
    private static let topUpWords: Set<String> = ["top", "up", "topup"]

    /// Banks and money apps whose app may send a notification titled with
    /// just their name. With `CardBook`'s own banks, from `LogWalletTapIntent`.
    static let bankNames: Set<String> = Set(BankPreset.all.map { $0.name.lowercased() })
        .union(["anz", "commbank", "nab", "westpac", "dbs", "ocbc", "uob", "revolut", "wise", "youtrip"])

    /// The words of one line with its amounts and clock times taken out.
    private static func words(_ line: String) -> [String] {
        var rest = WalletTapText.withoutClockTimes(line)
        for _ in 0..<4 {
            guard let m = WalletTapText.money(in: rest) else { break }
            rest = rest.replacingOccurrences(of: m, with: " ")
        }
        return rest.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// A line that is only a bank's status: at least one status word and
    /// nothing else that could be a shop's name.
    private static func isStatusLine(_ line: String, topUp: Bool) -> Bool {
        let w = words(line)
        let status = topUp ? statusWords.union(topUpWords) : statusWords
        return w.contains(where: status.contains) && w.allSatisfy { status.contains($0) || statusFiller.contains($0) }
    }

    /// Wallet's short lines that are a bank's status, not a purchase
    /// (review, 8 Oct 2026). Any of:
    /// (a) a line that is only a status ("Payment received", "Money in",
    ///     "Interest"); a shop with such a word in its name ("Interest
    ///     Cafe", "Hold On Pizza") has other words and is not one;
    /// (b) two clear amounts ("You exchanged £100.00 to €115.20");
    /// (c) a title that is just a bank's name, with no line under it that
    ///     could be a shop ("YouTrip · Top up successful · S$200.00").
    /// `rest` is the subtitle's and body's lines.
    static func isBankStatus(title: String, rest: [String], bankNames extra: Set<String> = []) -> Bool {
        let all = ([title] + rest).filter { !$0.isEmpty }
        if all.contains(where: { isStatusLine($0, topUp: false) }) { return true }
        if clearAmountCount(in: all.joined(separator: "\n")) >= 2 { return true }
        let name = title.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, bankNames.union(extra).contains(name) else { return false }
        let notAName = statusWords.union(topUpWords).union(statusFiller)
        return !rest.contains { line in words(line).contains { !notAName.contains($0) } }
    }

    // MARK: - Reading

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
        // No spend word is not a purchase: "Payment received · $120.00"
        // from a bank's app (9 Oct 2026; it used to read as money in, which
        // also saved nothing).
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
    /// on ("on", "with", "for", "is", "in", "and", "of", "card", a date,
    /// another amount, "—", "?"), with a trailing full stop and "Pty Ltd" taken off.
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
    /// "is", "in", "and", "of" only in lower case ("Bread In Common", "House
    /// Of Pho" keep theirs), and "balance" only before an amount ("The
    /// Balance Yoga Studio" keeps it).
    private static let stopPattern =
        #"(?-i:\s+(?:is|in|and|of)\b)|\s+(?:on|with|using|for|was|via|card|ending|has|will|refunded)\b|\s+(?:avail(?:able)?\.?\s+)?bal(?:ance)?\b(?=\s*(?::|is\b|of\b|now\b)?\s*[-−]?(?:[A-Z]{0,3}\$|[€£¥₹]|\d|[A-Z]{3}\s?\d))|\s*[—–]|\?|[.,;!]\s|\n|\s\d{1,2}[ /.-](?:\d{1,2}\b|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b)"#

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
