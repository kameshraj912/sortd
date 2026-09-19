import SwiftUI

/// The cards Raj pays with. Stored on `Transaction` as a raw string, so the
/// raw values must never change once there is real data.
/// A card, by id. What each id means (name, bank, last 4 digits…) lives in
/// `CardBook`, which Raj edits in Settings. The ids below are the cards the
/// app started with; they stay valid because old purchases store them.
nonisolated struct Card: RawRepresentable, Hashable, Codable, Identifiable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    var id: String { rawValue }

    static let nab = Card(rawValue: "nab")
    static let scDebit = Card(rawValue: "scDebit")
    static let stanchart = Card(rawValue: "stanchart")
    static let youtrip = Card(rawValue: "youtrip")
    static let maybank = Card(rawValue: "maybank")
    static let cimb = Card(rawValue: "cimb")
    /// Paid with a card the app doesn't know (or the receipt didn't say).
    static let other = Card(rawValue: "other")

    /// Cards shown on Home and in pickers, in Raj's order.
    @MainActor static var mine: [Card] { CardBook.shared.active.map(\.card) }

    @MainActor private var info: CardInfo? { CardBook.shared.info(self) }

    @MainActor var name: String { info?.name ?? (self == .other ? "Card not known" : rawValue) }
    @MainActor var shortName: String { info?.shortName ?? "Other" }
    @MainActor var shortLabel: String { shortName }
    @MainActor var isCredit: Bool { info?.isCredit ?? false }
    /// Currency the card is billed in. Only a fallback — the purchase
    /// currency depends on where Raj is, not on the card.
    @MainActor var homeCurrency: String { info?.currency ?? "AUD" }
    @MainActor var flag: String { info.map { CardInfo.flag(for: $0.country) } ?? "💳" }

    /// Matches the name Wallet gives a card ("NAB Visa Debit",
    /// "Standard Chartered Journey", "SC Jumpstart Debit" …).
    @MainActor static func match(_ walletName: String?) -> Card {
        CardBook.shared.match(walletName)
    }
}

/// Everything Raj sets for one card.
nonisolated struct CardInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var shortName: String
    var bank: String = ""
    var isCredit: Bool = false
    /// ISO code, e.g. "AUD". Any currency with daily rates works.
    var currency: String = "AUD"
    /// ISO country code for the flag, e.g. "AU".
    var country: String = "AU"
    /// Last 4 digits as printed on bank emails and receipts. A card can
    /// have more than one (a replaced card, or a virtual card number).
    var last4: [String] = []
    /// Last 4 of the Apple Pay Device Account Number. Apple Pay pays with its
    /// own number, so receipts for Apple Pay purchases often show these
    /// digits instead of the card's. Optional so older saved cards still load.
    var applePayLast4: [String]? = nil

    /// Every set of digits that means this card.
    var allLast4: [String] { last4 + (applePayLast4 ?? []) }
    /// Words from the card's name in Apple Wallet, used to recognise taps.
    var walletWords: [String] = []
    var archived: Bool = false

    var card: Card { Card(rawValue: id) }

    static func flag(for country: String) -> String {
        let base: UInt32 = 127397
        let scalars = country.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : "💳"
    }

    /// The cards Raj had before cards were editable. Used once, only for
    /// ids his existing purchases already point to.
    static let legacy: [CardInfo] = [
        CardInfo(id: "nab", name: "NAB Debit", shortName: "NAB Debit", bank: "NAB",
                 currency: "AUD", country: "AU", walletWords: ["nab", "national australia"]),
        CardInfo(id: "scDebit", name: "StanChart Debit", shortName: "SC Debit", bank: "Standard Chartered",
                 currency: "SGD", country: "SG",
                 walletWords: ["standard chartered", "stanchart", "sc", "jumpstart", "bonus$aver", "bonussaver"]),
        CardInfo(id: "stanchart", name: "StanChart Credit", shortName: "SC Credit", bank: "Standard Chartered",
                 isCredit: true, currency: "SGD", country: "SG",
                 walletWords: ["standard chartered", "stanchart", "chartered", "sc", "journey", "smart"]),
        CardInfo(id: "youtrip", name: "YouTrip", shortName: "YouTrip", bank: "YouTrip",
                 currency: "SGD", country: "SG", walletWords: ["youtrip", "you trip"]),
        CardInfo(id: "maybank", name: "Maybank Debit", shortName: "Maybank", bank: "Maybank",
                 currency: "SGD", country: "SG", walletWords: ["maybank"]),
        CardInfo(id: "cimb", name: "CIMB", shortName: "CIMB", bank: "CIMB",
                 currency: "SGD", country: "SG", walletWords: ["cimb"]),
    ]
}

/// Raj's cards. Kept as JSON in UserDefaults (a handful of small records,
/// no schema migrations). Views read it through `Card`, and because it is
/// @Observable they update when a card is edited.
@MainActor @Observable
final class CardBook {
    static let shared = CardBook()

    private(set) var cards: [CardInfo]
    private let defaults: UserDefaults
    private static let key = "cards.v1"

    init(defaults: UserDefaults = .standard) {
        // Tests run inside the app on the simulator; keep their cards apart
        // so they never overwrite the real ones.
        var defaults = defaults
        if defaults == .standard, ProcessInfo.processInfo.environment["SPEND_IN_MEMORY"] == "1",
           let scratch = UserDefaults(suiteName: "spend.tests") {
            scratch.removePersistentDomain(forName: "spend.tests")
            scratch.set(try? JSONEncoder().encode(CardInfo.legacy), forKey: Self.key)
            defaults = scratch
        }
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([CardInfo].self, from: data) {
            cards = saved
        } else {
            cards = []
        }
    }

    var active: [CardInfo] { cards.filter { !$0.archived } }

    func info(_ card: Card) -> CardInfo? { cards.first { $0.id == card.rawValue } }

    func upsert(_ info: CardInfo) {
        if let i = cards.firstIndex(where: { $0.id == info.id }) { cards[i] = info } else { cards.append(info) }
        save()
    }

    /// Cards with purchases are archived (hidden, history kept); unused ones go.
    func remove(_ info: CardInfo, hasPurchases: Bool) {
        if hasPurchases, let i = cards.firstIndex(where: { $0.id == info.id }) {
            cards[i].archived = true
        } else {
            cards.removeAll { $0.id == info.id }
        }
        save()
    }

    func move(from: IndexSet, to: Int) {
        var list = active
        list.move(fromOffsets: from, toOffset: to)
        cards = list + cards.filter(\.archived)
        save()
    }

    func replaceAll(_ list: [CardInfo]) {
        cards = list
        save()
    }

    /// Adds the original cards (NAB, SC…) when purchases point at them but
    /// the card isn't in the list yet: after the update, or when a Gmail
    /// script with a CARD_MAP sends them. Never re-adds a card Raj removed
    /// (removed cards stay in the list as archived). New users, whose
    /// purchases use their own card ids, are unaffected.
    func adoptLegacy(usedIds: Set<String>) {
        let known = Set(cards.map(\.id))
        let missing = CardInfo.legacy.filter { usedIds.contains($0.id) && !known.contains($0.id) }
        guard !missing.isEmpty else { return }
        cards += missing
        save()
    }

    /// Card for the last 4 digits on a receipt, if Raj has told us.
    func card(last4: String?) -> Card? {
        guard let last4, !last4.isEmpty else { return nil }
        return cards.first { $0.allLast4.contains(last4) }?.card
    }

    /// Every group of exactly 4 digits in the text ("•••• 4821", "…4821").
    nonisolated static func digitGroups(in text: String?) -> [String] {
        guard let text else { return [] }
        return text.split(whereSeparator: { !$0.isASCII || !$0.isNumber })
            .filter { $0.count == 4 }.map(String.init)
    }

    /// The one card whose saved digits (card or Apple Pay) appear in the text.
    func card(digitsIn text: String?) -> Card? {
        let groups = Set(Self.digitGroups(in: text))
        guard !groups.isEmpty else { return nil }
        let hits = active.filter { !groups.isDisjoint(with: $0.allLast4) }
        return hits.count == 1 ? hits[0].card : nil
    }

    /// Scores each card by how many of its Wallet words appear in the name;
    /// "debit"/"credit" in the name breaks ties between cards of one bank.
    func match(_ walletName: String?) -> Card {
        let name = " " + (walletName ?? "").lowercased() + " "
        guard name.trimmingCharacters(in: .whitespaces).count > 0 else { return .other }
        // Card digits are proof: Apple Pay's own number or the card's.
        if let card = card(digitsIn: walletName) { return card }
        return candidates(walletName).first?.card ?? .other
    }

    /// Cards whose Wallet words appear in the name, best first.
    func candidates(_ walletName: String?) -> [CardInfo] {
        let name = " " + (walletName ?? "").lowercased() + " "
        var scored: [(CardInfo, Int)] = []
        for c in active {
            var score = 0
            // "debit", "credit", "visa"… say nothing about which bank; the
            // debit/credit tie-break below handles them.
            for raw in c.walletWords {
                let w = raw.trimmingCharacters(in: .whitespaces)
                guard !w.isEmpty, !Self.genericWords.contains(w) else { continue }
                let needle = w.count <= 3 ? " \(w) " : w   // "sc" must be a word
                if name.contains(needle) { score += 2 }
            }
            guard score > 0 else { continue }
            if name.contains("credit") { score += c.isCredit ? 1 : -1 }
            if name.contains("debit") { score += c.isCredit ? -1 : 1 }
            if score > 0 { scored.append((c, score)) }
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private static let genericWords: Set<String> = ["debit", "credit", "card", "visa", "mastercard", "atm", "platinum"]

    private func save() {
        if let data = try? JSONEncoder().encode(cards) { defaults.set(data, forKey: Self.key) }
        // Apple Pay taps run in the background and the app is closed right
        // after: write now, or a card made by a tap is lost.
        defaults.synchronize()
    }
}

enum TxnSource: String, CaseIterable, Codable {
    case tap        // Wallet tap automation
    case email      // Gmail pipeline
    case csv        // statement import
    case bank       // open banking
    case manual

    var label: String {
        switch self {
        case .tap: "Apple Pay tap"
        case .email: "Email receipt"
        case .csv: "Statement import"
        case .bank: "Bank feed"
        case .manual: "Added by hand"
        }
    }

    var symbol: String {
        switch self {
        case .tap: "wave.3.right"
        case .email: "envelope"
        case .csv: "doc.text"
        case .bank: "building.columns"
        case .manual: "hand.point.up.left"
        }
    }

    /// Higher wins when two sources describe the same purchase.
    var trust: Int {
        switch self {
        case .bank: 5
        case .csv: 4
        case .email: 3
        case .tap: 2
        case .manual: 1
        }
    }
}

enum SpendCategory: String, CaseIterable, Identifiable, Codable {
    case foodDelivery
    case eatingOut
    case groceries
    case transport
    case subscriptions
    case shopping
    case entertainment
    case housing
    case bills
    case health
    case travel
    case education
    case transfers
    case other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .foodDelivery: "Food Delivery"
        case .eatingOut: "Eating Out"
        case .groceries: "Groceries"
        case .transport: "Transport"
        case .subscriptions: "Subscriptions"
        case .shopping: "Shopping"
        case .entertainment: "Entertainment"
        case .housing: "Rent & Housing"
        case .bills: "Bills"
        case .health: "Health"
        case .travel: "Travel"
        case .education: "Education"
        case .transfers: "Transfers"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .foodDelivery: "takeoutbag.and.cup.and.straw.fill"
        case .eatingOut: "fork.knife"
        case .groceries: "cart.fill"
        case .transport: "car.fill"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .shopping: "bag.fill"
        case .entertainment: "ticket.fill"
        case .housing: "house.fill"
        case .bills: "bolt.fill"
        case .health: "cross.case.fill"
        case .travel: "airplane"
        case .education: "graduationcap.fill"
        case .transfers: "arrow.left.arrow.right"
        case .other: "square.grid.2x2.fill"
        }
    }

    /// One clear colour per category, used for its icon, bars and chart
    /// segments. Neighbours in spending (food delivery vs eating out) are
    /// far apart in hue, and colour is always paired with the icon/name.
    /// Category colour for the current appearance. In Dark Mode it is a
    /// lighter, slightly softer version (Material: saturated colours
    /// "vibrate" on dark; Apple: give custom colours bright and dim variants).
    var color: Color {
        let base = UIColor(lightColor)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? base.forDarkBackground : base })
    }

    private var lightColor: Color {
        switch self {
        case .foodDelivery: Color(red: 0.94, green: 0.39, blue: 0.24)   // orange
        case .eatingOut: Color(red: 0.96, green: 0.65, blue: 0.14)      // amber
        case .groceries: Color(red: 0.13, green: 0.63, blue: 0.42)      // green
        case .transport: Color(red: 0.31, green: 0.66, blue: 0.87)      // sky
        case .subscriptions: Color(red: 0.36, green: 0.29, blue: 0.90)  // purple
        case .shopping: Color(red: 0.90, green: 0.34, blue: 0.60)       // pink
        case .entertainment: Color(red: 0.69, green: 0.31, blue: 0.85)  // violet
        case .housing: Color(red: 0.62, green: 0.42, blue: 0.29)        // brown
        case .bills: Color(red: 0.83, green: 0.63, blue: 0.09)          // mustard
        case .health: Color(red: 0.90, green: 0.28, blue: 0.30)         // red
        case .travel: Color(red: 0.08, green: 0.72, blue: 0.65)         // teal
        case .education: Color(red: 0.23, green: 0.44, blue: 0.88)      // blue
        case .transfers: Color(red: 0.39, green: 0.45, blue: 0.55)      // slate
        case .other: Color(red: 0.58, green: 0.64, blue: 0.72)          // grey
        }
    }

    /// Food Delivery + Eating Out — the numbers Raj wants to watch.
    var isFood: Bool { self == .foodDelivery || self == .eatingOut }
}

extension UIColor {
    /// Lighter and a little less saturated, for use on dark backgrounds.
    var forDarkBackground: UIColor {
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &sat, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: sat * 0.82, brightness: min(1, b * 1.06 + 0.06), alpha: a)
    }
}
