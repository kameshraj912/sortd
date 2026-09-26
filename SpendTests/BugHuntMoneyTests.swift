import Testing
import Foundation
import SwiftData
@testable import Spend

// Bug hunt 26 Sep 2026, money-parsing area. One failing test per finding.
// Each result below was reproduced by compiling the real parser sources
// (Parsing.swift, QuickEntry.swift, BankAlerts.swift, WalletTapText,
// GenericReceipts) into a command-line harness and running the inputs.
//
// Nothing in this file touches Spend/ or any other test file.

@MainActor
struct BugHuntMoneyTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private let nab = BankAlerts.Bank(name: "NAB", domain: "nab.com.au", currency: "AUD")

    // MARK: 1. Bank alert refund words are matched as substrings anywhere

    /// A purchase alert at an RSL club ("RETURNED SERVICES LEAGUE") is read as
    /// a refund, because "returned" is looked for as a plain substring across
    /// the whole email, footer included. The purchase never reaches the list;
    /// if an earlier purchase of the same amount exists, that one is marked
    /// refunded instead, so the total goes down for money that was spent.
    ///
    /// Known bug: `BankAlerts.read` (Spend/Services/BankAlerts.swift:124) checks `refundWords` with
    /// `contains($0, text)` — no word boundary, no restriction to the sentence about the money.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-01: bank alert refund words matched inside merchant names and footers"))
    func aPurchaseAtAnRSLClubIsNotARefund() throws {
        let rsl = BankAlerts.read(subject: "Purchase alert",
                                  body: "You spent A$45.00 at RETURNED SERVICES LEAGUE CLUB on 26/09 using your card ending 1234.",
                                  bank: nab)
        #expect(rsl?.isRefund == false, "a purchase at an RSL club was read as a refund")

        let footer = BankAlerts.read(subject: "Purchase alert",
                                     body: "You spent A$45.00 at COLES on 26/09 using your card ending 1234. "
                                         + "Reward points will be credited to your account within 3 days.",
                                     bank: nab)
        #expect(footer?.isRefund == false, "a rewards footer turned a purchase into a refund")

        let noRefund = BankAlerts.read(subject: "Purchase alert",
                                       body: "You spent $58.30 at NON REFUNDABLE FARES PTY on 26/09.",
                                       bank: nab)
        #expect(noRefund?.isRefund == false, "'non refundable' in a shop name read as a refund")

        // End to end: the RSL purchase must be a row in the store.
        let ctx = try store()
        let msg = EmailParsers.Message(id: "rsl-1", from: "alerts@nab.com.au", subject: "Purchase alert",
                                       body: "You spent A$45.00 at RETURNED SERVICES LEAGUE CLUB on 26/09 using your card ending 1234.",
                                       date: .now)
        let summary = try EmailSync.importRecords(EmailParsers.parse(msg), in: ctx)
        #expect(summary.added == 1, "the RSL purchase was not added: \(summary)")
        #expect(try ctx.fetch(FetchDescriptor<Transaction>()).audTotal == 45)
    }

    // MARK: 2. Baht, peso, won, dong and yuan signs are not currencies

    /// `Money.supported` lists THB, PHP, KRW and CNY, but their signs are not
    /// in `AmountParser.markers`, so "฿350" is 350 with no currency and is
    /// booked in the home currency (A$350 for a ฿350 dinner, about A$15).
    /// "CN¥88" is worse: the "¥" is read as yen, so yuan become yen.
    @Test
    func bahtPesoWonAndYuanSignsNameTheirCurrency() async throws {
        #expect(AmountParser.parse("฿350")?.currency == "THB", "฿350 has no currency")
        #expect(AmountParser.parse("₱250")?.currency == "PHP", "₱250 has no currency")
        #expect(AmountParser.parse("₩15000")?.currency == "KRW", "₩15000 has no currency")
        #expect(AmountParser.parse("CN¥88")?.currency == "CNY", "CN¥88 is not CNY")

        // Through the Wallet tap line and the intent, as a real tap arrives.
        let parts = WalletTapText.parse("Bangkok Cafe ฿350.00 NAB Visa Debit")
        #expect(parts.amount.flatMap { AmountParser.parse($0)?.currency } == "THB",
                "Wallet text ฿350.00 lost its currency: \(String(describing: parts))")
        let yuan = WalletTapText.parse("Shanghai Cafe CN¥88.00 NAB Visa Debit")
        #expect(yuan.amount.flatMap { AmountParser.parse($0)?.currency } == "CNY",
                "Wallet text CN¥88.00 read as yen: \(String(describing: yuan))")

        let ctx = try store()
        let out = try await LogPurchaseIntent.handle(merchant: "Bangkok Cafe", amount: "฿350.00", card: "NAB Visa Debit",
                                                     in: ctx, book: CardBook(), now: Date(timeIntervalSince1970: 1_790_000_000))
        let saved = try #require(out.transaction)
        #expect(saved.currencyCode == "THB", "a ฿350 tap was saved in \(saved.currencyCode)")
    }

    // MARK: 3. Narrow no-break space and apostrophe thousands

    /// French iOS writes "12 345,67" with a narrow no-break space (U+202F)
    /// and Swiss German writes "1'234.50". `AmountParser` only knows space
    /// and U+00A0 as group separators, so it stops at the first group:
    /// "12 345,67" → 12, "1'234.50" → 1. `QuickEntry` reads the same text
    /// as two numbers and keeps the last one: 345.67 and 234.50.
    ///
    /// Known bug: `AmountParser.parse` regex (Spend/Services/Parsing.swift:64) and
    /// `QuickEntry.amountPattern` (Spend/Services/QuickEntry.swift:158) don't allow U+202F or "'" between groups.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-03: U+202F and apostrophe thousands lose everything after the first group"))
    func narrowSpaceAndApostropheThousandsAreRead() {
        #expect(AmountParser.parse("12\u{202F}345,67")?.amount == Decimal(string: "12345.67"), "fr_FR thousands read as 12")
        #expect(AmountParser.parse("1'234.50")?.amount == Decimal(string: "1234.50"), "de_CH thousands read as 1")
        #expect(QuickEntry.read("watch 1'234.50")?.amount == Decimal(string: "1234.50"))
        #expect(QuickEntry.read("coffee 12\u{202F}345,67")?.amount == Decimal(string: "12345.67"))

        // Wallet text from a Swiss phone: the amount is cut at the apostrophe
        // and the rest of the line is taken for the card name.
        let parts = WalletTapText.parse("Zurich Cafe CHF 1'234.50 NAB Visa Debit")
        #expect(parts.amount.flatMap { AmountParser.parse($0)?.amount } == Decimal(string: "1234.50"),
                "Swiss Wallet text read as \(String(describing: parts))")
    }

    // MARK: 4. Receipt totals with dot thousands or three decimals

    /// Indonesian receipts write "Rp25.000" (dot thousands). The receipt
    /// total regex requires two decimals and has no closing boundary, so it
    /// takes "Rp25.00" and books IDR 25 for a 25,000 rupiah purchase.
    /// "Rp 1.250.000" becomes IDR 1.25. The same missing boundary reads
    /// "Total: $12.345" as 12.34.
    ///
    /// Known bug: `GenericReceipts.total` money regex (Spend/Services/GenericReceipts.swift:76) ends in
    /// `\.\d{2}` with no `\b`, and only knows comma thousands.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-04: Rp25.000 is read as IDR 25.00; a third decimal is cut, not rejected"))
    func rupiahDotThousandsAreNotCents() {
        let rp = GenericReceipts.total(in: "Total Rp25.000")
        #expect(rp?.amount == "25000" || rp?.amount == "25000.00", "Rp25.000 read as \(String(describing: rp))")
        let big = GenericReceipts.total(in: "Total Rp 1.250.000")
        #expect(big?.amount == "1250000" || big?.amount == "1250000.00", "Rp 1.250.000 read as \(String(describing: big))")
        let three = GenericReceipts.total(in: "Total: $12.345")
        #expect(three == nil || three?.amount == "12.35", "$12.345 read as \(String(describing: three))")
    }

    // MARK: 5. Zero-decimal currencies never parse from emails

    /// Yen, won and rupiah are written without cents. Both the receipt total
    /// regex and every bank-alert amount pattern require ".dd", so a yen
    /// receipt ("Total ¥1,200") and a yen bank alert ("JPY 1,200 at TOKYO
    /// RAMEN") produce nothing. The purchase is silently missed, every time.
    ///
    /// Known bug: `GenericReceipts.total` (Spend/Services/GenericReceipts.swift:76) and
    /// `BankAlerts.amount` (Spend/Services/BankAlerts.swift:136-141) require two decimals for every currency.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-05: JPY, KRW and IDR amounts without cents are never read from emails"))
    func zeroDecimalTotalsAreRead() {
        #expect(GenericReceipts.total(in: "Total ¥1,200")?.currency == "JPY", "yen receipt dropped")
        #expect(GenericReceipts.total(in: "Total KRW 15,000")?.currency == "KRW", "won receipt dropped")
        #expect(GenericReceipts.total(in: "Total: IDR 25,000")?.currency == "IDR", "rupiah receipt dropped")
        let alert = BankAlerts.read(subject: "Purchase alert",
                                    body: "You spent JPY 1,200 at TOKYO RAMEN on 26/09 with your card ending 1234.",
                                    bank: nab)
        #expect(alert?.currency == "JPY" && alert?.amount == "1200", "yen bank alert dropped: \(String(describing: alert))")
    }

    // MARK: 6. An ISO-coded amount anywhere in the body beats the purchase amount

    /// `BankAlerts.amount` tries the "AUD 58.30" pattern over the whole
    /// email before it tries "$58.30". A subject that states the purchase in
    /// dollars and a body that mentions a limit or balance with a code gives
    /// the limit as the amount. Sample shape, not a verified bank email.
    ///
    /// Known bug: `BankAlerts.amount` (Spend/Services/BankAlerts.swift:136-143) ranks patterns, not positions.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-06: a coded amount later in the body wins over the $ amount in the subject"))
    func theFirstAmountInTheAlertIsThePurchase() {
        let r = BankAlerts.read(subject: "You spent $9.00 at COLES",
                                body: "Your card ending 1234 was used at COLES on 26/09. Your daily limit is AUD 1,000.00.",
                                bank: nab)
        #expect(r?.amount == "9.00", "the daily limit was taken as the purchase: \(String(describing: r))")
    }
}
