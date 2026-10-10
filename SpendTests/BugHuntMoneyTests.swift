import Testing
import Foundation
import SwiftData
@testable import Spend

// Bug hunt 26 Sep 2026, money-parsing area. One failing test per finding.
// Each result below was reproduced by compiling the real parser sources
// (Parsing.swift, QuickEntry.swift, WalletTapText, GenericReceipts) into a
// command-line harness and running the inputs. The bank-alert cases went with
// the Gmail feature on 2 Oct 2026.
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

    // MARK: 5. Zero-decimal currencies never parse from receipt text

    /// Yen, won and rupiah are written without cents. The receipt total
    /// regex requires ".dd", so a yen receipt ("Total ¥1,200") produces
    /// nothing. The purchase is silently missed, every time.
    ///
    /// Known bug: `GenericReceipts.total` (Spend/Services/GenericReceipts.swift) requires two decimals for every currency.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-05: JPY, KRW and IDR amounts without cents are never read from receipts"))
    func zeroDecimalTotalsAreRead() {
        #expect(GenericReceipts.total(in: "Total ¥1,200")?.currency == "JPY", "yen receipt dropped")
        #expect(GenericReceipts.total(in: "Total KRW 15,000")?.currency == "KRW", "won receipt dropped")
        #expect(GenericReceipts.total(in: "Total: IDR 25,000")?.currency == "IDR", "rupiah receipt dropped")
    }

    // MARK: - Bug hunt 8 Oct 2026 (money-parsing). Each result below was
    // reproduced by compiling Parsing.swift, QuickEntry.swift, AmountEntry.swift,
    // GenericReceipts.swift (lines 10-103), ReceiptScanner.total, Pace.swift and
    // Outcome.line into a command-line harness and running the inputs.

    private func scratch() -> UserDefaults {
        let name = "hunt-money-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: 6. A leading-dot amount is 100 times too big

    /// ".50" typed for fifty cents saves $50. The amount field lets a leading
    /// "." or "," in (`AmountEntry.isTypeable`), but `AmountParser.parse`'s
    /// number pattern must start with a digit, so it skips the separator and
    /// reads "50". ".5" saves $5. The Add sheet (`parsedAmount`) and the
    /// purchase detail (`committedAmount`) both save it; BudgetSheet is fine
    /// because `limitInput` puts a "0" in front first.
    ///
    /// Fixed 10 Oct 2026, was: `AmountParser.parse` (Spend/Services/Parsing.swift:86-87) has no
    /// alternative for `[.,][0-9]{1,2}` with nothing before it.
    @Test(.bug("hunt-money-06: .50 is read as 50 and saved as fifty dollars"))
    func aLeadingDotAmountIsCents() {
        #expect(AddTransactionView.isTypeable(".50"), "the field refuses it; then there is no bug")
        #expect(AmountParser.parse(".50")?.amount == Decimal(string: "0.50"),
                ".50 read as \(String(describing: AmountParser.parse(".50")))")
        #expect(AmountParser.parse(".5")?.amount == Decimal(string: "0.5"),
                ".5 read as \(String(describing: AmountParser.parse(".5")))")
        #expect(AmountParser.parse(",50")?.amount == Decimal(string: "0.50"),
                ",50 read as \(String(describing: AmountParser.parse(",50")))")
        #expect(TransactionDetailView.committedAmount(from: ".50") == Decimal(string: "0.50"),
                "detail saved \(String(describing: TransactionDetailView.committedAmount(from: ".50")))")
    }

    // MARK: 7. A receipt total with the currency after the number

    /// "TOTAL 350.00 THB" on a Bangkok receipt is booked as A$350 (the home
    /// currency), about 23 times too much. `GenericReceipts.total` only looks
    /// for a code or sign in front of the number, so it finds nothing;
    /// `ReceiptScanner.total` then takes its unsigned fallback and labels the
    /// amount with `Money.home`. Same for "TOTAL 12.50 EUR", "TOTAL 12.50€"
    /// and "Total: 45.00 SGD".
    ///
    /// Fixed 10 Oct 2026, was: `GenericReceipts.total` money regex (Spend/Services/GenericReceipts.swift:18-19)
    /// and the fallback in `ReceiptScanner.total` (Spend/Services/ReceiptScanner.swift:142-150).
    @Test(.bug("hunt-money-07: a currency written after the total is ignored and the home currency is used"))
    func aCurrencyAfterTheTotalIsKept() {
        let cases: [(String, String)] = [("TOTAL 350.00 THB", "THB"), ("TOTAL 12.50 EUR", "EUR"),
                                         ("TOTAL 12.50€", "EUR"), ("Total: 45.00 SGD", "SGD")]
        for (text, code) in cases {
            let found = ReceiptScanner.total(in: text)
            #expect(found?.currency == code, "\(text) read as \(String(describing: found))")
        }
    }

    // MARK: 8. A huge budget from a backup crashes Home

    /// `Pace.projectedOverDay` does `Int((budget / rate).rounded(.down))`
    /// (Spend/Services/Pace.swift:21), which traps once the result passes
    /// Int.max: a budget of 1e21 with $10 spent on the 7th crashes; 1e300
    /// crashes. `BudgetSheet` caps what is typed, but `Backup.restore` writes
    /// `monthlyBudget` from the file as is (Spend/Services/Backup.swift:315),
    /// and Home calls Pace with that raw value (HomeView `projectedOverDay`)
    /// before any sheet can sanitise it. A backup with a bad budget therefore
    /// crashes Home on every open from the 7th of the month. The test checks
    /// the restore, not Pace, so a failure does not abort the run.
    ///
    /// Fixed 10 Oct 2026 (the restore half; Pace itself is fixed on the money
    /// branch): `Backup.restore` holds the budget and every category limit to
    /// `BudgetSheet.maxBudget`, the most the budget field takes.
    @Test(.bug("hunt-money-08: a restored budget over the cap reaches Pace and traps"))
    func aRestoredBudgetIsCappedBeforeItReachesPace() throws {
        let from = try store()
        let fromDefaults = scratch()
        fromDefaults.set(1e300, forKey: FXService.budgetKey)
        fromDefaults.set(["eatingOut": 1e300, "transport": 200.0, "travel": -5.0], forKey: CategoryBudgets.key)
        let data = try Backup.data(in: from, defaults: fromDefaults)

        let to = try store()
        let toDefaults = scratch()
        try Backup.restore(data, mode: .merge, into: to, defaults: toDefaults, cardBook: CardBook(defaults: scratch()))

        let restored = toDefaults.double(forKey: FXService.budgetKey)
        #expect(restored <= BudgetSheet.maxBudget(), "restored budget \(restored) is over the cap; Home's pace line would trap")
        #expect(BudgetSheet.sanitized(restored) == restored, "restore wrote a budget BudgetSheet would throw away")
        #expect(restored == BudgetSheet.maxBudget())

        let limits = CategoryBudgets.stored(toDefaults)
        #expect(limits["eatingOut"] == BudgetSheet.maxBudget(), "a category limit over the cap was kept: \(limits)")
        #expect(limits["transport"] == 200)
        #expect(limits["travel"] == nil)
    }

    // MARK: 9. A China-region phone's yuan are read as yen

    /// A phone set to China (zh_CN, en_CN) writes yuan as "¥88.00" (checked
    /// with the system formatter, 8 Oct 2026). The bare "¥" marker is JPY,
    /// so every tap of such a phone is saved as ¥88 yen (about A$0.90)
    /// for a ¥88 yuan coffee (about A$18.60). The local-currency fallback
    /// would get CNY right, but the marker wins
    /// (`LogPurchaseIntent.handle`: `parsed?.currency ?? fallbackCurrency`).
    /// The receipt camera has the same rule (`GenericReceipts.currencyCode`).
    ///
    /// Known bug: `AmountParser.markers` (Spend/Services/Parsing.swift:36) maps a bare "¥" to JPY with no regard to the phone's region.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-09: ¥ written by a China-region phone is booked as Japanese yen"))
    func aChinaPhonesYuanAreNotYen() {
        let written = Decimal(string: "88.00")!.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
        #expect(written.contains("¥") && !written.contains("CN"), "zh_CN now writes \(written); then there is no bug")
        let parsed = AmountParser.parse(written)
        #expect(parsed?.currency != "JPY", "\(written) from a China-region phone read as \(String(describing: parsed))")
    }

    // MARK: 10. A refund from a Hebrew-language phone is logged as spending

    /// iOS writes a negative amount on a he_IL phone with direction marks
    /// first: U+200F U+200E "-45.50" NBSP U+200F "₪" (checked with the
    /// system formatter). `isNegative` only trims plain whitespace, so it
    /// never sees the minus: the refund tap goes down the purchase path and
    /// the total goes up by ₪45.50 instead of down. ur_PK writes
    /// U+200E "-" U+200F U+200E "$45.50", same result.
    ///
    /// Known bug: `AmountParser.isNegative` (Spend/Services/Parsing.swift:72-75) does not skip U+200E/U+200F, and
    /// `LogPurchaseIntent.handle` (Spend/Intents/LogPurchaseIntent.swift:198) passes the raw amount.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-10: a minus behind right-to-left marks is not seen, so a refund counts as spending"))
    func aRefundWithDirectionMarksIsStillARefund() {
        let hebrew = Decimal(string: "-45.50")!.formatted(.currency(code: "ILS").locale(Locale(identifier: "he_IL")))
        #expect(AmountParser.isNegative(hebrew), "he_IL refund \(hebrew.unicodeScalars.map { String($0.value, radix: 16) }) read as a purchase")
        #expect(AmountParser.isNegative("\u{200F}\u{200E}-45.50\u{00A0}\u{200F}₪"))
        #expect(AmountParser.isNegative("\u{200E}-\u{200F}\u{200E}$45.50"))
    }

    // MARK: 11. Rupiah and won purchases over 1,000,000 cannot be entered

    /// The Add sheet and quick entry stop at 1,000,000 in every currency
    /// (`QuickEntry.limit`, `AddTransactionView.parsedAmount` and its
    /// 6-digit `isTypeable`). Rp1,000,000 is about A$95 and ₩1,000,000 about
    /// A$1,100, so an IDR or KRW user cannot type a phone, a flight or rent:
    /// the 7th digit is refused and "hotel 1500000 idr" gives "Couldn't read
    /// that". `BudgetSheet.currencyScale` already scales its cap for these
    /// currencies (IDR ×10,000, KRW ×1,000); the purchase cap does not.
    ///
    /// Known bug: `QuickEntry.limit` (Spend/Services/QuickEntry.swift:143) and
    /// `AddTransactionView.parsedAmount`/`isTypeable` (Spend/Views/AddTransactionView.swift:527,533) ignore the currency.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-11: purchases of 1,000,000 or more cannot be entered in IDR, KRW, JPY"))
    func bigNumberCurrenciesCanBeEntered() {
        #expect(QuickEntry.read("hotel 1500000 idr")?.amount == 1_500_000, "Rp1.5M (about A$140) refused")
        #expect(QuickEntry.read("laptop 1,500,000 krw")?.amount == 1_500_000, "₩1.5M refused")
        #expect(BudgetSheet.maxBudget("IDR") > QuickEntry.limit.double,
                "the budget cap scales for IDR; the purchase cap must too")
    }

    // MARK: 12. Quick entry takes a model currency from letters inside a word

    /// `QuickEntryAI.merge` keeps the model's currency only when the line
    /// mentions it. The code itself is matched as a substring, so "pastry"
    /// mentions TRY, "nails" ILS, "Europcar" EUR, "whisky" ISK and "Zara"
    /// ZAR. If the model guesses that code, the Add form is filled in
    /// Turkish lira for a A$5 pastry (₺5 is about A$0.20). The hint words
    /// next to it were already made whole-word ("rm" in "farm", tested in
    /// `QuickEntryAITests.dropsACurrencyTheLineNeverMentions`); the code
    /// check was not.
    ///
    /// Known bug: `QuickEntryAI.mentionsCurrency` (Spend/Services/QuickEntryAI.swift:130) uses `lower.contains(code)`.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("hunt-money-12: a currency code inside a word (pastry, nails, Europcar) counts as named"))
    func aCurrencyCodeInsideAWordIsNotNamed() throws {
        func fields(_ merchant: String, _ amount: String, _ currency: String) -> QuickEntryFields {
            QuickEntryFields(merchant: merchant, amount: amount, currency: currency, daysAgo: 0, category: "Other")
        }
        let cases: [(String, String, String, String)] = [
            ("Pastry", "5", "TRY", "pastry 5"), ("Nails", "40", "ILS", "nails 40"),
            ("Europcar", "50", "EUR", "europcar 50"), ("Whisky", "30", "ISK", "whisky 30"),
            ("Zara", "80", "ZAR", "zara 80"),
        ]
        for (merchant, amount, code, typed) in cases {
            let r = try #require(QuickEntryAI.merge(fields(merchant, amount, code), typed: typed))
            #expect(r.currency == nil, "\(typed) filled in \(r.currency ?? "nil")")
        }
    }

    // MARK: 13. Number sizes that trapped (C1, C2, C3)

    /// A budget of 1e21 or 1e300 (a bad backup) made `Pace.projectedOverDay`
    /// call `Int(...)` on a number past Int.max and crash Home on every open.
    /// It now gives no projection. (`aRestoredBudgetIsCappedBeforeItReachesPace`
    /// stays a known bug: the restore itself still writes the raw budget.)
    @Test(.bug("C1: a huge budget makes Pace trap"))
    func aHugeBudgetGivesNoPaceInsteadOfACrash() {
        for budget in [1e21, 1e300, Double.infinity, Double.greatestFiniteMagnitude] {
            #expect(Pace.projectedOverDay(spent: 10, budget: budget, day: 7, daysInMonth: 31) == nil, "budget \(budget)")
        }
        #expect(Pace.projectedOverDay(spent: 10, budget: 1e-300, day: 7, daysInMonth: 31) == nil)
        // An ordinary month still projects: $70 by the 7th of a $200 budget.
        #expect(Pace.projectedOverDay(spent: 70, budget: 200, day: 7, daysInMonth: 31) == 21)
    }

    /// A 19-digit whole amount trapped in `Int(n.doubleValue)`.
    @Test(.bug("C2: GenericReceipts.appears traps on a 19-digit whole amount"))
    func aNineteenDigitAmountDoesNotTrap() {
        #expect(GenericReceipts.appears("9999999999999999999", in: "Total 9999999999999999999"))
        #expect(!GenericReceipts.appears("9999999999999999999", in: "Total 12.00"))
        #expect(GenericReceipts.appears("42.00", in: "Total $42"))
        #expect(!GenericReceipts.appears("5.00", in: "Total $15.00"))
    }

    /// This month about 1e17 times last month made the percent too big for
    /// an Int, and Insights trapped.
    @Test(.bug("C3: Outcome.line traps on a huge month"))
    func aHugeMonthGivesALineInsteadOfACrash() {
        #expect(Outcome.line(thisMonth: 1e17, lastMonthToSameDay: 1) != nil)
        #expect(Outcome.line(thisMonth: 1e300, lastMonthToSameDay: 1e-300) == nil)
        #expect(Outcome.line(thisMonth: 88, lastMonthToSameDay: 100) == "12% less than last month by now")
        #expect(Outcome.line(thisMonth: 100, lastMonthToSameDay: 100) == "About the same as last month by now")
    }
}
