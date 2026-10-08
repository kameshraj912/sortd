import Foundation
import SwiftData

/// Which Apple Pay automation trigger ran: the Wallet tap trigger (a till)
/// or, on iOS 27, Wallet's notification (a till, an app or a website), or
/// a bank app's own notification (8 Oct 2026: the person added their bank's
/// app to the shortcut, `BankNotice`). Stored on `Transaction.tapOrigins` as
/// these letters.
nonisolated enum TapTrigger: String, Sendable {
    case tap = "t"
    case notification = "n"
    case bank = "b"
}

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
    /// The Gmail account an old email purchase came from. Nothing writes it
    /// any more; the stored field stays so old rows still load and back up.
    var sourceAccount: String?
    /// Last 4 digits an old email receipt carried that matched none of the
    /// person's cards. Nothing writes it any more (the "Which card?" prompt
    /// is gone); the stored field stays so old rows still load.
    var unmatchedLast4: String?
    /// Which Apple Pay automation triggers have reported this purchase:
    /// "t" for the Wallet tap trigger (a till), "n" for Wallet's
    /// notification (iOS 27; also apps and websites), "b" for a bank app's
    /// notification (8 Oct 2026), in that order ("tn", "tnb"). Nil for
    /// rows that never came from either, and for tap rows logged before
    /// 2 Oct 2026 (read as "t"). Optional, so SwiftData migrates on its own.
    var tapOrigins: String?

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

    /// The tap trigger has reported this row. A tap row from before
    /// `tapOrigins` existed counts.
    var seenByTapTrigger: Bool {
        if let tapOrigins { return tapOrigins.contains(TapTrigger.tap.rawValue) }
        return seenIn.contains(.tap)
    }

    /// Wallet's notification has reported this row.
    var seenByNotification: Bool { tapOrigins?.contains(TapTrigger.notification.rawValue) == true }

    /// A bank app's notification has reported this row.
    var seenByBank: Bool { tapOrigins?.contains(TapTrigger.bank.rawValue) == true }

    /// This trigger has reported this row.
    func seen(by trigger: TapTrigger) -> Bool {
        switch trigger {
        case .tap: seenByTapTrigger
        case .notification: seenByNotification
        case .bank: seenByBank
        }
    }

    /// Adds a trigger to `tapOrigins`, always written "t", "n", then "b".
    func markOrigin(_ trigger: TapTrigger) {
        let tap = seenByTapTrigger || trigger == .tap
        let notification = seenByNotification || trigger == .notification
        let bank = seenByBank || trigger == .bank
        tapOrigins = (tap ? TapTrigger.tap.rawValue : "") + (notification ? TapTrigger.notification.rawValue : "")
            + (bank ? TapTrigger.bank.rawValue : "")
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

    /// The name a tap with no shop is saved under (`LogPurchaseIntent`).
    nonisolated static let unknownMerchant = "Unknown merchant"

    /// A tap that came with no shop name: saved as `unknownMerchant`, or
    /// blank in a row made some other way.
    var lacksShop: Bool {
        let raw = rawMerchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty || raw == Self.unknownMerchant
            || merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

/// An email record the removed Gmail sync had imported. Nothing writes these
/// any more; the model stays so old data still loads and backs up.
@Model
final class ImportedRecord {
    @Attribute(.unique) var id: String = ""
    var importedAt: Date = Date.now
    /// The Gmail account it came from.
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
