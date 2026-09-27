import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID = UUID()
    var date: Date = Date.now
    /// Cleaned name shown in the UI.
    var merchant: String = ""
    /// Exactly what the source gave us, for debugging parsers.
    var rawMerchant: String = ""
    var amount: Decimal = 0
    var currencyCode: String = "AUD"
    /// `amount` in the home currency (`Money.home`; the name is from when it
    /// was always AUD). Nil until an exchange rate for that day is known.
    var audAmount: Decimal?
    var cardRaw: String = Card.other.rawValue
    var categoryRaw: String = SpendCategory.other.rawValue
    var sourceRaw: String = TxnSource.manual.rawValue
    /// Every source that has reported this purchase, comma separated.
    var seenInRaw: String = ""
    var note: String = ""
    var createdAt: Date = Date.now
    /// "doordash" / "uber" / "apple" when bought through a platform.
    var platform: String?
    /// A refund or bank reversal cancelled this purchase.
    var refunded: Bool = false
    /// From App Store / subscription receipts: when it renews next, and
    /// "monthly" / "yearly". Used to predict upcoming payments.
    var renewsOn: Date?
    var billingPeriod: String?
    /// The Gmail account an email purchase came from, so disconnecting it
    /// can remove its purchases.
    var sourceAccount: String?
    /// Last 4 digits a receipt or bank alert carried that matched none of
    /// Raj's cards, while it waits for "Which card?" (Home) to be answered.
    /// Non-nil only until then: picking a card clears it on every purchase
    /// that shares the digits, "Not one of mine" just empties the queue and
    /// leaves this as is (spec 2026-09-27).
    var unmatchedLast4: String?

    init(date: Date, merchant: String, rawMerchant: String? = nil, amount: Decimal,
         currencyCode: String, card: Card, category: SpendCategory, source: TxnSource,
         note: String = "") {
        self.date = date
        self.merchant = merchant
        self.rawMerchant = rawMerchant ?? merchant
        self.amount = amount
        self.currencyCode = currencyCode
        self.audAmount = currencyCode == Money.home ? amount : nil
        self.cardRaw = card.rawValue
        self.categoryRaw = category.rawValue
        self.sourceRaw = source.rawValue
        self.seenInRaw = source.rawValue
        self.note = note
    }

    var card: Card {
        get { Card(rawValue: cardRaw) }
        set { cardRaw = newValue.rawValue }
    }

    var category: SpendCategory {
        get { SpendCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var source: TxnSource {
        get { TxnSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var seenIn: [TxnSource] {
        seenInRaw.split(separator: ",").compactMap { TxnSource(rawValue: String($0)) }
    }

    func markSeen(in source: TxnSource) {
        guard !seenIn.contains(source) else { return }
        seenInRaw = (seenIn + [source]).map(\.rawValue).joined(separator: ",")
    }

    /// Best available AUD value. Falls back to the raw amount so totals never
    /// silently drop a purchase while a rate is still loading. Refunded
    /// purchases count as zero.
    /// Card name, or where it came from when the receipt doesn't say
    /// (DoorDash and Uber emails don't name the card).
    @MainActor var paidWithLabel: String {
        guard card == .other else { return card.shortName }
        switch platform {
        case "doordash": return "DoorDash"
        case "uber": return "Uber"
        case "apple": return "App Store"
        default: return "Card not known"
        }
    }

    var audValue: Decimal {
        // Not converted yet (offline, or a currency without daily rates):
        // leave it out of totals rather than count it one-for-one.
        if audAmount == nil, currencyCode != Money.home { return 0 }
        return refunded ? 0 : (audAmount ?? amount)
    }
    var needsRate: Bool { audAmount == nil }
    /// A tap that arrived without an amount.
    var needsReview: Bool { amount == 0 }

    /// Prefixed onto `note` when a tap saved with too little to log
    /// cleanly — blank amount, blank shop, or (known bug U6) a lone card
    /// name where Wallet should have sent more (spec 2026-09-26, "Apple
    /// Pay logging — failsafes"). A marker in the existing free-text
    /// field, not a new schema column: no migration is needed for this
    /// first pass (the spec's own open question 4 on whether to promote it
    /// to a real field later).
    static let needsCheckTag = "⚑ "

    /// True for a tap that landed with too little to log cleanly.
    /// `needsReview` (amount missing) already flags one such case on its
    /// own; this also catches a blank shop or a card-only tap, which still
    /// have a real amount and so wouldn't trip `needsReview`. Editing the
    /// note away un-flags it — the point where a person has looked and
    /// either fixed it or decided it's fine.
    var needsCheck: Bool { needsReview || note.hasPrefix(Self.needsCheckTag) }

    /// Rows the removed "Send a Test Tap" button left behind
    /// (`LogPurchaseIntent.legacyTestMerchant`), and the Apple Pay health
    /// check's own runs (`ApplePayHealthCheck.merchant`). Old installs may
    /// still have the first kind; the second is made on purpose whenever
    /// "Check the Shortcut" runs. Neither must ever appear in Activity (any
    /// day, search or a card's own list), Home's Recent list, Insights,
    /// budgets or totals — only `ApplePayStatus` still needs to see them
    /// (it already excludes them itself, `realTaps`), so screens that
    /// resolve the Apple Pay status query `Transaction` unfiltered, not
    /// through this.
    static var excludingLegacyTest: Predicate<Transaction> {
        let test = LogPurchaseIntent.legacyTestMerchant
        let check = ApplePayHealthCheck.merchant
        return #Predicate<Transaction> { $0.merchant != test && $0.rawMerchant != test
            && $0.merchant != check && $0.rawMerchant != check }
    }
}

extension Collection where Element == Transaction {
    /// Purchases still waiting on an exchange rate, for Home's "+1
    /// converting" note: they are left out of `audTotal` until the rate lands.
    /// A currency with no daily rate (`Money.supported`) never converts, so
    /// it only counts for a week; then "converting" would be a lie.
    var pendingConversions: Int { pendingConversions(now: .now) }

    func pendingConversions(now: Date) -> Int {
        let cutoff = now.addingTimeInterval(-7 * 86400)
        return count { $0.needsRate && !$0.refunded && (Money.supported.contains($0.currencyCode) || $0.date > cutoff) }
    }
}

/// A merchant → category mapping Raj taught the app by recategorising.
@Model
final class MerchantRule {
    /// Normalised merchant key (see `MerchantName.key`).
    @Attribute(.unique) var key: String = ""
    var categoryRaw: String = SpendCategory.other.rawValue
    var updatedAt: Date = Date.now

    init(key: String, category: SpendCategory) {
        self.key = key
        self.categoryRaw = category.rawValue
    }

    var category: SpendCategory { SpendCategory(rawValue: categoryRaw) ?? .other }
}

/// An email record already imported, so re-syncs never add it twice.
@Model
final class ImportedRecord {
    @Attribute(.unique) var id: String = ""
    var importedAt: Date = Date.now
    /// Gmail account it came from, so disconnecting can forget it.
    var account: String?

    init(id: String, account: String? = nil) {
        self.id = id
        self.account = account
    }
}

/// Cached SGD→AUD (etc.) rate for one day.
@Model
final class FXRate {
    /// "SGD-2026-09-18"
    @Attribute(.unique) var key: String = ""
    var rate: Decimal = 1

    init(key: String, rate: Decimal) {
        self.key = key
        self.rate = rate
    }
}
