import Foundation

/// Common banks and cards, so adding a card is one tap: name, currency,
/// country and the words Wallet uses are filled in. Grouped by country and
/// shown for the user's own country first.
nonisolated struct BankPreset: Identifiable, Hashable, Sendable {
    let name: String
    let country: String
    let currency: String
    /// Lowercase words that appear in this bank's card names in Apple Wallet.
    let words: [String]
    var id: String { "\(country)-\(name)" }

    static let all: [BankPreset] = [
        // Australia
        .init(name: "NAB", country: "AU", currency: "AUD", words: ["nab", "national australia"]),
        .init(name: "CommBank", country: "AU", currency: "AUD", words: ["commbank", "commonwealth"]),
        .init(name: "ANZ", country: "AU", currency: "AUD", words: ["anz"]),
        .init(name: "Westpac", country: "AU", currency: "AUD", words: ["westpac"]),
        .init(name: "ING", country: "AU", currency: "AUD", words: ["ing"]),
        .init(name: "Macquarie", country: "AU", currency: "AUD", words: ["macquarie"]),
        .init(name: "Up", country: "AU", currency: "AUD", words: ["up bank", "up "]),
        .init(name: "ubank", country: "AU", currency: "AUD", words: ["ubank"]),
        .init(name: "St.George", country: "AU", currency: "AUD", words: ["st.george", "st george"]),
        .init(name: "Bendigo", country: "AU", currency: "AUD", words: ["bendigo"]),
        // Singapore
        .init(name: "DBS", country: "SG", currency: "SGD", words: ["dbs"]),
        .init(name: "POSB", country: "SG", currency: "SGD", words: ["posb"]),
        .init(name: "OCBC", country: "SG", currency: "SGD", words: ["ocbc"]),
        .init(name: "UOB", country: "SG", currency: "SGD", words: ["uob"]),
        .init(name: "Standard Chartered", country: "SG", currency: "SGD", words: ["standard chartered", "stanchart", "sc"]),
        .init(name: "Citibank", country: "SG", currency: "SGD", words: ["citi"]),
        .init(name: "HSBC", country: "SG", currency: "SGD", words: ["hsbc"]),
        .init(name: "Maybank", country: "SG", currency: "SGD", words: ["maybank"]),
        .init(name: "CIMB", country: "SG", currency: "SGD", words: ["cimb"]),
        .init(name: "Trust", country: "SG", currency: "SGD", words: ["trust"]),
        .init(name: "GXS", country: "SG", currency: "SGD", words: ["gxs"]),
        .init(name: "YouTrip", country: "SG", currency: "SGD", words: ["youtrip", "you trip"]),
        // Malaysia
        .init(name: "Maybank", country: "MY", currency: "MYR", words: ["maybank"]),
        .init(name: "CIMB", country: "MY", currency: "MYR", words: ["cimb"]),
        .init(name: "Public Bank", country: "MY", currency: "MYR", words: ["public bank"]),
        .init(name: "RHB", country: "MY", currency: "MYR", words: ["rhb"]),
        // India
        .init(name: "HDFC Bank", country: "IN", currency: "INR", words: ["hdfc"]),
        .init(name: "ICICI Bank", country: "IN", currency: "INR", words: ["icici"]),
        .init(name: "SBI", country: "IN", currency: "INR", words: ["sbi", "state bank"]),
        .init(name: "Axis Bank", country: "IN", currency: "INR", words: ["axis"]),
        .init(name: "Kotak", country: "IN", currency: "INR", words: ["kotak"]),
        .init(name: "IDFC First", country: "IN", currency: "INR", words: ["idfc"]),
        .init(name: "IndusInd", country: "IN", currency: "INR", words: ["indusind"]),
        .init(name: "Yes Bank", country: "IN", currency: "INR", words: ["yes bank"]),
        // United States
        .init(name: "Chase", country: "US", currency: "USD", words: ["chase"]),
        .init(name: "Bank of America", country: "US", currency: "USD", words: ["bank of america", "bofa"]),
        .init(name: "Wells Fargo", country: "US", currency: "USD", words: ["wells fargo"]),
        .init(name: "Capital One", country: "US", currency: "USD", words: ["capital one"]),
        .init(name: "Apple Card", country: "US", currency: "USD", words: ["apple card"]),
        .init(name: "Citi", country: "US", currency: "USD", words: ["citi"]),
        .init(name: "Discover", country: "US", currency: "USD", words: ["discover"]),
        // United Kingdom
        .init(name: "Monzo", country: "GB", currency: "GBP", words: ["monzo"]),
        .init(name: "Starling", country: "GB", currency: "GBP", words: ["starling"]),
        .init(name: "Barclays", country: "GB", currency: "GBP", words: ["barclays"]),
        .init(name: "HSBC", country: "GB", currency: "GBP", words: ["hsbc"]),
        .init(name: "Lloyds", country: "GB", currency: "GBP", words: ["lloyds"]),
        .init(name: "NatWest", country: "GB", currency: "GBP", words: ["natwest"]),
        .init(name: "Santander", country: "GB", currency: "GBP", words: ["santander"]),
        // Anywhere
        .init(name: "Wise", country: "", currency: "", words: ["wise"]),
        .init(name: "Revolut", country: "", currency: "", words: ["revolut"]),
        .init(name: "American Express", country: "", currency: "", words: ["amex", "american express"]),
    ]

    /// The user's country first, then global cards, then everything else.
    static func sorted(for country: String) -> [BankPreset] {
        all.filter { $0.country == country } + all.filter { $0.country.isEmpty } +
            all.filter { !$0.country.isEmpty && $0.country != country }
    }

    /// The bank a Wallet card name belongs to, if we know it.
    static func match(_ walletName: String) -> BankPreset? {
        let name = " " + walletName.lowercased() + " "
        return all.first { p in p.words.contains { w in w.count <= 3 ? name.contains(" \(w.trimmingCharacters(in: .whitespaces)) ") : name.contains(w) } }
    }

    /// Name that fits on a card tile or a row next to a switch.
    var shortName: String { Self.short(name) }

    static func short(_ bank: String) -> String {
        ["Standard Chartered": "StanChart", "American Express": "Amex", "Bank of America": "BofA"][bank] ?? bank
    }

    /// A new card from this preset. Blank currency/country (Wise, Revolut)
    /// take the phone's.
    func card(credit: Bool) -> CardInfo {
        let cur = currency.isEmpty ? Money.home : currency
        let ctry = country.isEmpty ? (Locale.current.region?.identifier ?? "AU") : country
        let label = "\(name) \(credit ? "Credit" : "Debit")"
        let short = "\(shortName) \(credit ? "Credit" : "Debit")"
        return CardInfo(name: label, shortName: short, bank: name, isCredit: credit,
                        currency: cur, country: ctry, walletWords: words)
    }
}

extension CardBook {
    /// Filler words a masked-digit phrase leaves behind once its digits are
    /// stripped ("ending 4821", "card ending in 4821") — none of them is a
    /// card name on its own. Left over alone, they must never become a
    /// brand-new saved card (ApplePayHunt item 4); a real card word next to
    /// one of these ("NAB Visa Debit ending 4821") is unaffected, since only
    /// the *fully* filtered name is checked against this, not each word.
    private static let maskedDigitFillerWords: Set<String> = [
        "ending", "card", "no", "no.", "number", "num", "in", "with", "using", "on", "via", "pay", "apple",
    ]

    /// For Apple Pay taps: the matching card, or a new one named after the
    /// card in Wallet, so nobody has to add cards by hand first.
    func matchOrCreate(_ walletName: String?) -> Card {
        // A blank field — empty, or one of Shortcuts' own placeholder
        // strings for an unfilled variable (spec 2026-09-26, failsafe #13)
        // — is not a card name and must never create one.
        guard !TapField.isBlank(walletName) else { return .other }
        // Saved digits settle it, even if the name says otherwise.
        if let byDigits = card(digitsIn: walletName) { return byDigits }
        var found = match(walletName)
        var ambiguous = false
        let digits = Self.digitGroups(in: walletName)
        // Keep the name without the digits and dots ("NAB Visa Debit ••4821").
        let name = (walletName ?? "")
            .split(separator: " ")
            // Drop the number part: "••••", "4821", "…4821".
            .filter { word in !word.contains(where: \.isNumber) && !word.allSatisfy { "•·….*-".contains($0) } }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "•·…-*")))
        // A masked-digit phrase ("ending 4821", "card ending in 4821") with
        // no real card word left once its digits and filler words are both
        // gone must match an existing card by digits alone or create
        // nothing — not save "ending" as if it were the card's own name.
        let onlyFiller = !name.isEmpty && name.split(separator: " ")
            .allSatisfy { Self.maskedDigitFillerWords.contains($0.lowercased()) }
        // "CommBank Credit" must not land on the CommBank debit card.
        let lower = name.lowercased()
        if let info = self.info(found), (lower.contains("credit") && !info.isCredit) || (lower.contains("debit") && info.isCredit) {
            found = .other
        }
        if found != .other, let d = digits.last {
            // Digits no card owns. With one possible card, it's that card's
            // Apple Pay number: remember it. With several (two NAB cards, or a
            // new device like a Watch), don't guess: make a card for the digits.
            // (One card can have several: iPhone and Watch each get their own.)
            let possible = candidates(walletName)
            if possible.count == 1, var info = self.info(found) {
                if (info.applePayLast4 ?? []).count < 4 {
                    info.applePayLast4 = (info.applePayLast4 ?? []) + [d]
                    upsert(info)
                }
                return found
            }
            found = .other
            ambiguous = true
        }
        if found != .other { return found }
        guard name.count >= 2, !onlyFiller else { return found }
        let bank = BankPreset.match(name)
        // Two cards could fit: name the new one by its digits so it's easy to tell apart.
        let label = ambiguous ? "\(name) ••\(digits.last ?? "")" : name
        var info = CardInfo(
            name: label, shortName: String(label.prefix(18)), bank: bank?.name ?? "",
            isCredit: lower.contains("credit"),
            currency: (bank?.currency).flatMap { $0.isEmpty ? nil : $0 } ?? LocalCurrency.forNewCard(),
            country: (bank?.country).flatMap { $0.isEmpty ? nil : $0 } ?? (Locale.current.region?.identifier ?? "AU"),
            walletWords: [lower] + (bank?.words ?? []))
        if let d = digits.last { info.applePayLast4 = [d] }
        upsert(info)
        return info.card
    }
}
