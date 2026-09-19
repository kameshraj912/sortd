import Testing
import Foundation
@testable import Spend

struct AmountParserTests {
    @Test(arguments: [
        ("$4.50", Decimal(string: "4.50")!, nil as String?),
        ("A$4.50", Decimal(string: "4.50")!, "AUD"),
        ("S$1,234.00", Decimal(string: "1234.00")!, "SGD"),
        ("SGD 12.30", Decimal(string: "12.30")!, "SGD"),
        ("US$9.99", Decimal(string: "9.99")!, "USD"),
        ("4,50", Decimal(string: "4.50")!, nil),
        ("-$20.00", Decimal(string: "20.00")!, nil),
        ("12", Decimal(12), nil),
    ])
    func parses(text: String, amount: Decimal, currency: String?) {
        let r = AmountParser.parse(text)
        #expect(r?.amount == amount)
        #expect(r?.currency == currency)
    }

    @Test func rejectsEmpty() {
        #expect(AmountParser.parse("") == nil)
        #expect(AmountParser.parse(" ") == nil)
        #expect(AmountParser.parse("free") == nil)
    }
}

struct MerchantNameTests {
    @Test func cleansBankStyleNames() {
        #expect(MerchantName.clean("SQ *CAFE BLOSSOM MELBOURNE AU") == "Cafe Blossom")
        #expect(MerchantName.clean("McDonald's") == "McDonald's")
        #expect(MerchantName.clean("WOOLWORTHS 3342") == "Woolworths")
    }

    @Test func keyIgnoresCaseAndPunctuation() {
        #expect(MerchantName.key("Uber *Eats") == MerchantName.key("UBER EATS"))
    }
}

struct CategorizerTests {
    @Test(arguments: [
        ("Uber Eats", SpendCategory.foodDelivery),
        ("UBER *EATS PENDING", .foodDelivery),
        ("Uber Trip", .transport),
        ("DoorDash", .foodDelivery),
        ("Woolworths Carlton", .groceries),
        ("Seven Seeds Coffee", .eatingOut),
        ("Spotify", .subscriptions),
        ("IGA Carlton", .groceries),
        ("Cigar Bar Lounge", .eatingOut),   // "iga" inside "cigar" must not hit groceries
        ("Iglu Brisbane (Iglu Pty Ltd)", .housing),
        ("IGLU LAUNDRY - MELBOU", .housing),
        ("AMAYSIM MOBILE PTY LTD", .bills),
        ("NTUC FP - CITY SQUARE", .groceries),
        ("Saravanaa Bhavan", .eatingOut),
        ("CITY EMERGENCY DEPT", .health),
        ("NordVPN", .subscriptions),
        ("Trip.com", .travel),
        ("NETS FLASHPAY TOPUP", .transfers),
        ("Random Shop Pty", .other),
    ])
    func builtInRules(merchant: String, expected: SpendCategory) {
        #expect(Categorizer.category(for: merchant) == expected)
    }

    @Test func learnedRuleWins() {
        let learned = [MerchantName.key("Seven Seeds Coffee"): SpendCategory.groceries]
        #expect(Categorizer.category(for: "Seven Seeds Coffee", learned: learned) == .groceries)
    }
}

struct CardTests {
    @Test func matchesWalletNames() {
        #expect(Card.match("NAB Visa Debit") == .nab)
        #expect(Card.match("Standard Chartered Journey") == .stanchart)
        #expect(Card.match("SC Smart Card") == .stanchart)
        #expect(Card.match("Standard Chartered Jumpstart Debit") == .scDebit)
        #expect(Card.match("SC Debit Mastercard") == .scDebit)
        #expect(Card.match("YouTrip Mastercard") == .youtrip)
        #expect(Card.match("Maybank Platinum Debit") == .maybank)
        #expect(Card.match(nil) == .other)
        #expect(Card.match("Myki") == .other)
    }
}

struct LocalCurrencyTests {
    @Test func followsTimeZone() {
        #expect(LocalCurrency.current(timeZone: TimeZone(identifier: "Australia/Melbourne")!) == "AUD")
        #expect(LocalCurrency.current(timeZone: TimeZone(identifier: "Asia/Singapore")!) == "SGD")
    }
}

struct DeduperTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func c(_ merchant: String, _ amount: String, hoursLater: Double = 0,
           card: Card = .stanchart, source: TxnSource = .tap) -> Deduper.Candidate {
        .init(date: now.addingTimeInterval(hoursLater * 3600), merchant: merchant,
              amount: Decimal(string: amount)!, currency: "SGD", card: card, source: source)
    }

    @Test func tapAndEmailForSamePurchaseMerge() {
        let tap = c("Toast Box", "7.80")
        let email = c("TOAST BOX - PLAZA SING", "7.80", hoursLater: 20, source: .email)
        #expect(Deduper.match(email, in: [tap]) == 0)
    }

    @Test func twoCoffeesSameDayStaySeparate() {
        let first = c("Ya Kun Kaya Toast", "5.50")
        let second = c("Toast Box", "5.50", hoursLater: 3)
        #expect(Deduper.match(second, in: [first]) == nil)
    }

    @Test func differentAmountsNeverMerge() {
        #expect(Deduper.match(c("Grab", "18.60", source: .email), in: [c("Grab", "18.50")]) == nil)
    }

    @Test func differentKnownCardsNeverMerge() {
        let nab = c("Coles", "10.00", card: .nab)
        let sc = c("Coles", "10.00", card: .stanchart, source: .email)
        #expect(Deduper.match(sc, in: [nab]) == nil)
    }

    @Test func outsideWindowIsNewPurchase() {
        #expect(Deduper.match(c("Spotify", "13.99", hoursLater: 24 * 30, source: .email),
                              in: [c("Spotify", "13.99")]) == nil)
    }

    @Test func zeroAmountNeverMerges() {
        #expect(Deduper.match(c("Unknown merchant", "0"), in: [c("Unknown merchant", "0")]) == nil)
    }
}

struct RoundingTests {
    @Test func roundsHalfUp() {
        #expect(Decimal(string: "8.5695")!.rounded(2) == Decimal(string: "8.57")!)
    }
}

@MainActor
struct CardBookTests {
    private func fresh() -> CardBook {
        let name = "cards-\(UUID().uuidString)"
        return CardBook(defaults: UserDefaults(suiteName: name)!)
    }

    @Test func newInstallStartsWithNoCards() {
        let book = fresh()
        book.adoptLegacy(usedIds: [])
        #expect(book.cards.isEmpty)
    }

    @Test func updateKeepsOnlyCardsInUse() {
        let book = fresh()
        book.adoptLegacy(usedIds: ["nab", "stanchart", "other"])
        #expect(book.cards.map(\.id) == ["nab", "stanchart"])
    }

    @Test func cardsArriveLaterFromEmail() {
        let book = fresh()
        book.adoptLegacy(usedIds: [])            // first launch, nothing yet
        book.adoptLegacy(usedIds: ["scDebit"])   // first Gmail sync
        #expect(book.cards.map(\.id) == ["scDebit"])
    }

    @Test func removedCardIsNotAddedBack() {
        let book = fresh()
        book.adoptLegacy(usedIds: ["nab"])
        book.remove(book.cards[0], hasPurchases: true)
        book.adoptLegacy(usedIds: ["nab"])
        #expect(book.cards.count == 1)
        #expect(book.active.isEmpty)
    }

    @Test func matchesByLastFourDigits() {
        let book = fresh()
        book.upsert(CardInfo(id: "wise", name: "Wise", shortName: "Wise", last4: ["0123", "4567"]))
        #expect(book.card(last4: "0123") == Card(rawValue: "wise"))
        #expect(book.card(last4: "4567") == Card(rawValue: "wise"))
        #expect(book.card(last4: "9999") == nil)
    }

    @Test func applePayNumberAlsoMatches() {
        let book = fresh()
        var info = CardInfo(id: "c", name: "Card", shortName: "Card", last4: ["1234"])
        info.applePayLast4 = ["9876"]
        book.upsert(info)
        #expect(book.card(last4: "1234") == Card(rawValue: "c"))
        #expect(book.card(last4: "9876") == Card(rawValue: "c"))
    }

    @Test func cardsSavedBeforeApplePayDigitsStillLoad() throws {
        let old = #"[{"id":"x","name":"Old","shortName":"Old","bank":"","isCredit":false,"currency":"AUD","country":"AU","last4":["1111"],"walletWords":[],"archived":false}]"#
        let cards = try JSONDecoder().decode([CardInfo].self, from: Data(old.utf8))
        #expect(cards.first?.allLast4 == ["1111"])
    }

    @Test func customCardMatchesWalletName() {
        let book = fresh()
        book.upsert(CardInfo(id: "amex", name: "Amex Platinum", shortName: "Amex", isCredit: true,
                             walletWords: ["amex", "american express"]))
        #expect(book.match("American Express Platinum") == Card(rawValue: "amex"))
        #expect(book.match("Some Other Card") == .other)
    }

    @Test func removingAUsedCardArchivesIt() {
        let book = fresh()
        let used = CardInfo(id: "a", name: "A", shortName: "A")
        let unused = CardInfo(id: "b", name: "B", shortName: "B")
        book.upsert(used); book.upsert(unused)
        book.remove(used, hasPurchases: true)
        book.remove(unused, hasPurchases: false)
        #expect(book.cards.map(\.id) == ["a"])
        #expect(book.cards.first?.archived == true)
        #expect(book.active.isEmpty)
    }
}

struct RecurringTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: s)!
    }
    private func charge(_ d: String, _ merchant: String, _ amount: Decimal, _ cat: SpendCategory = .subscriptions,
                        renews: Date? = nil, period: String? = nil) -> RecurringDetector.Charge {
        .init(date: day(d), merchant: merchant, amount: amount, currency: "AUD", audAmount: amount,
              category: cat, card: .nab, renewsOn: renews, billingPeriod: period)
    }

    @Test func monthlyFromHistoryPredictsNextMonth() {
        let found = RecurringDetector.detect([
            charge("2026-06-10", "Spotify", 13.99), charge("2026-07-10", "Spotify", 13.99),
            charge("2026-08-10", "Spotify", 13.99), charge("2026-09-10", "Spotify", 13.99),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.count == 1)
        #expect(found.first?.cadence == .monthly)
        #expect(found.first?.nextDate == day("2026-10-10"))
    }

    @Test func priceRiseIsFlagged() {
        let found = RecurringDetector.detect([
            charge("2026-07-05", "Netflix", 16.99), charge("2026-08-05", "Netflix", 16.99),
            charge("2026-09-05", "Netflix", 18.99),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(abs((found.first?.priceChange ?? 0).double - 2) < 0.001)
    }

    @Test func coffeeHabitIsNotABill() {
        let found = RecurringDetector.detect([
            charge("2026-09-01", "Seven Seeds", 5.5, .eatingOut), charge("2026-09-08", "Seven Seeds", 5.5, .eatingOut),
            charge("2026-09-15", "Seven Seeds", 5.5, .eatingOut),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.isEmpty)
    }

    @Test func randomAmountsAreNotRecurring() {
        let found = RecurringDetector.detect([
            charge("2026-07-01", "Kmart", 12, .shopping), charge("2026-08-01", "Kmart", 85, .shopping),
            charge("2026-09-01", "Kmart", 40, .shopping),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.isEmpty)
    }

    @Test func appStoreRenewalDateIsUsed() {
        let found = RecurringDetector.detect([
            charge("2026-09-15", "TickTick", 79.99, renews: day("2027-09-15"), period: "yearly"),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.cadence == .yearly)
        #expect(found.first?.nextDate == day("2027-09-15"))
    }

    @Test func missedPaymentsMeanItStopped() {
        let found = RecurringDetector.detect([
            charge("2026-03-02", "Gym", 20, .health), charge("2026-04-02", "Gym", 20, .health),
            charge("2026-05-02", "Gym", 20, .health),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.status == .lapsed)
    }

    @Test func chargeAfterCancellingIsCaught() {
        let found = RecurringDetector.detect([
            charge("2026-07-10", "Stan", 12), charge("2026-08-10", "Stan", 12), charge("2026-09-10", "Stan", 12),
        ], cancelled: [MerchantName.key("Stan"): day("2026-08-20")], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.chargedAfterCancel == true)
    }

    @Test func fortnightlyRent() {
        let found = RecurringDetector.detect([
            charge("2026-08-04", "Campus Rooms", 560.40, .housing),
            charge("2026-08-18", "Campus Rooms", 560.40, .housing),
            charge("2026-09-01", "Campus Rooms", 560.40, .housing),
            charge("2026-09-15", "Campus Rooms", 560.40, .housing),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.cadence == .fortnightly)
        #expect(found.first?.nextDate == day("2026-09-29"))
    }

    @Test func rentWithAOneOffFeeIsStillFortnightly() {
        let found = RecurringDetector.detect([
            charge("2026-08-11", "Campus Rooms", 1046.80, .housing),
            charge("2026-08-25", "Campus Rooms", 1046.80, .housing),
            charge("2026-09-08", "Campus Rooms", 1046.80, .housing),
            charge("2026-09-14", "Campus Rooms", 68.30, .housing),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.cadence == .fortnightly)
        #expect(found.first?.amount == 1046.80)
        #expect(found.first?.nextDate == day("2026-09-22"))
    }

    @Test func skippedMonthIsStillMonthly() {
        let found = RecurringDetector.detect([
            charge("2026-06-06", "SA_justdone.ai", 22.22), charge("2026-08-13", "SA_justdone.ai", 22.22),
            charge("2026-09-12", "SA_justdone.ai", 22.22),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.cadence == .monthly)
    }

    @Test func weeklyMealPlanCounts() {
        let found = RecurringDetector.detect([
            charge("2026-08-12", "Nourish'd", 230.05, .eatingOut), charge("2026-08-19", "Nourish'd", 230.05, .eatingOut),
            charge("2026-09-02", "Nourish'd", 230.05, .eatingOut), charge("2026-09-09", "Nourish'd", 230.05, .eatingOut),
        ], now: day("2026-09-19"), calendar: cal)
        #expect(found.first?.cadence == .weekly)
    }
}

struct RecurringRealPatternTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: s)!
    }
    private func c(_ d: String, _ m: String, _ a: String, _ cat: SpendCategory) -> RecurringDetector.Charge {
        let amount = Decimal(string: a)!
        return .init(date: day(d), merchant: m, amount: amount, currency: "AUD", audAmount: amount,
                     category: cat, card: .nab, renewsOn: nil, billingPeriod: nil)
    }

    /// Fortnightly rent plus a one-off fee from the same landlord.
    @Test func rentWithExtraFee() {
        let dates = ["2026-07-14", "2026-07-28", "2026-08-11", "2026-08-25", "2026-09-08"]
        var list = dates.map { c($0, "Campus Rooms", "1046.80", .housing) }
        list.append(c("2026-09-14", "Campus Rooms", "68.30", .housing))
        let r = RecurringDetector.detect(list, now: day("2026-09-19"), calendar: cal).first
        #expect(r?.cadence == .fortnightly)
        #expect(r?.amount == Decimal(string: "1046.80"))
        #expect(r?.nextDate == day("2026-09-22"))
    }

    /// Monthly with a skipped month in between.
    @Test func monthlyWithSkippedMonth() {
        let r = RecurringDetector.detect([
            c("2026-06-06", "justdone.ai", "22.22", .subscriptions),
            c("2026-08-13", "justdone.ai", "22.22", .subscriptions),
            c("2026-09-12", "justdone.ai", "22.22", .subscriptions),
        ], now: day("2026-09-19"), calendar: cal).first
        #expect(r?.cadence == .monthly)
    }

    /// Same price every week from a food place: a meal plan, not a habit.
    @Test func weeklyMealPlan() {
        let r = RecurringDetector.detect([
            c("2026-08-12", "Nourish'd", "230.05", .eatingOut), c("2026-08-19", "Nourish'd", "230.05", .eatingOut),
            c("2026-09-02", "Nourish'd", "230.05", .eatingOut), c("2026-09-09", "Nourish'd", "230.05", .eatingOut),
        ], now: day("2026-09-19"), calendar: cal).first
        #expect(r?.cadence == .weekly)
    }
}

struct MerchantCleanTests {
    @Test(arguments: [
        ("MUJI RETAIL (AUSTRAL", "Muji Retail"),
        ("Apple Music Individual (Monthly)", "Apple Music Individual"),
        ("SA_justdone.ai", "justdone.ai"),
        ("LS House of Cards Espr", "House of Cards Espr"),
        ("KMD PTY LTD", "Kmd"),
        ("SMP_REAL TASTY PTE LTD", "Real Tasty"),
        ("Sri Ananda Bhavan CBD", "Sri Ananda Bhavan CBD"),
        ("7-ELEVEN 1144", "7-Eleven"),
    ])
    func cleans(raw: String, expected: String) {
        #expect(MerchantName.clean(raw) == expected)
    }

    @Test func cleaningTwiceChangesNothing() {
        for raw in ["MUJI RETAIL (AUSTRAL", "SQ *PONDOK REMPAH", "Rocket Burgers & Fries"] {
            let once = MerchantName.clean(raw)
            #expect(MerchantName.clean(once) == once)
        }
    }
}

struct CSVExportTests {
    @Test func plainFieldsAreLeftAlone() {
        #expect(CSVExport.escape("Uber Eats") == "Uber Eats")
    }

    @Test func commasAndQuotesAreQuoted() {
        #expect(CSVExport.escape("Grill'd, Carlton") == "\"Grill'd, Carlton\"")
        #expect(CSVExport.escape("The \"Best\" Cafe") == "\"The \"\"Best\"\" Cafe\"")
    }
}

/// The same cases as apps-script/test/parsers.test.js, so the on-phone
/// parsers and the Apps Script parsers can't drift apart.
struct EmailParserTests {
    private func msg(_ id: String, _ from: String, _ subject: String, _ body: String, _ date: Date = .now) -> EmailParsers.Message {
        .init(id: id, from: from, subject: subject, body: body, date: date)
    }
    private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private func one(_ m: EmailParsers.Message) -> EmailRecord? {
        let rows = EmailParsers.parse(m)
        #expect(rows.count == 1)
        return rows.first
    }
    private func date(_ r: EmailRecord?) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return r.flatMap { f.date(from: $0.date) }
    }

    @Test func stanChartPurchaseInSingaporeTime() {
        let r = one(msg("a", "alerts.sg@sc.com", "Transaction Alert Debit Card Email Alert",
                        "Thank you for charging +AUD 24.49 to yr debit card ****2222 on 16-Sep-2611:54 AM at SOME CAFE PTY LTD.\n\nTo modify these alerts",
                        iso("2026-09-16T04:00:00Z")))
        #expect(r?.kind == "purchase"); #expect(r?.merchant == "SOME CAFE PTY LTD")
        #expect(r?.amount == "24.49"); #expect(r?.currency == "AUD"); #expect(r?.last4 == "2222")
        #expect(date(r) == iso("2026-09-16T03:54:00Z"))
    }

    @Test func stanChartDeliveryDescriptors() {
        let dd = one(msg("b", "alerts.sg@sc.com", "s", "Thank you for charging +AUD 31.05 to yr debit card ****2222 on 13-Sep-26 12:07 PM at DD *DOORDASH SOMEWHERE. To modify"))
        let ue = one(msg("c", "alerts.sg@sc.com", "s", "Thank you for charging +AUD 33.43 to yr credit card ****3333 on 12-Sep-26 08:53 PM at UBER * EATS PENDING. To modify"))
        #expect(dd?.merchant == "DoorDash"); #expect(dd?.platform == "doordash")
        #expect(ue?.merchant == "Uber Eats"); #expect(ue?.platform == "uber"); #expect(ue?.last4 == "3333")
    }

    @Test func stanChartReversalIsRefund() {
        let r = one(msg("d", "alerts.sg@sc.com", "s", "Transaction of +AUD 17.53 made on your card ****2222 on 11-Sep-26 11:49 AM at DD *DOORDASH SHOP has been reversed. To modify"))
        #expect(r?.kind == "refund"); #expect(r?.amount == "17.53")
    }

    @Test func doorDashTotalAndRestaurant() {
        let r = one(msg("e", "no-reply@doordash.com", "Order Confirmation for Raj from Test Kitchen",
                        "Paid with Apple Pay\nTest Kitchen\nTotal: $38.15\nSubtotal $35.00\nTotal Charged $38.15"))
        #expect(r?.merchant == "Test Kitchen"); #expect(r?.amount == "38.15"); #expect(r?.platform == "doordash")
    }

    @Test func doorDashMarketingIgnored() {
        #expect(EmailParsers.parse(msg("f", "no-reply@doordash.com", "Craving something different?", "30% off")).isEmpty)
    }

    @Test func appleInvoice() {
        let r = one(msg("g", "no_reply@email.apple.com", "Your tax invoice from Apple.",
                        "Apple Account:\n\nme@example.com\n\nSomeApp:Tasks\n\nAnnual SomeApp Premium (Annual)\n\nRenews 15 September 2027\n\n$79.99\n\nBilling and Payment\n\nVisa •••• 1111\n\n$79.99"))
        #expect(r?.merchant == "SomeApp"); #expect(r?.amount == "79.99"); #expect(r?.last4 == "1111")
        #expect(r?.subscription?.period == "yearly"); #expect(r?.subscription?.renews == "15 September 2027")
    }

    @Test func appleInAppOlderLayout() {
        let r = one(msg("g2", "no_reply@email.apple.com", "Your tax invoice from Apple.",
                        "Tax Invoice\nAPPLE ACCOUNT\nme@example.com BILLED TO\nVisa .... 1111\nSomeone\nDATE\n23 May 2026\nApp Store\n\nSome App: Match & More\n3 Boosts\nIn-App Purchase\nReport a Problem\n$39.99\n\nTOTAL $39.99\n\nGet help"))
        #expect(r?.merchant == "Some App"); #expect(r?.amount == "39.99"); #expect(r?.last4 == "1111")
    }

    @Test func youTripRowsAndDayBefore() {
        let rows = EmailParsers.parse(msg("h", "noreply@you.co", "Summary of your recent online purchases & ATM withdrawals",
            "| based on Singapore Time (UTC+8). |\n| | UBER * EATS PENDING~1 Street~Sydney | AUD 32.76 |\n| Ref. No: SFT-1 | 8:24 AM |\n| | SHOP ONE~X | SGD 5.00 |\n| Ref. No: SFT-2 | 2:10 AM |\n| You may view",
            iso("2026-06-02T20:42:49Z")))
        #expect(rows.count == 2)
        #expect(rows.first?.merchant == "Uber Eats"); #expect(rows.first?.card == "youtrip")
        #expect(date(rows.first) == iso("2026-06-02T00:24:00Z"))
        #expect(date(rows.last) == iso("2026-06-02T18:10:00Z"))
    }

    @Test func youTripBoldHeader() {
        let rows = EmailParsers.parse(msg("h2", "noreply@you.co", "Summary of your recent online purchases & ATM withdrawals",
            "The times shown are based on *Singapore Time (UTC+8)*.\n\nUBER * EATS PENDING~1 Street~Sydney~2000 036\nAUD 32.76\nRef. No: SFT-1\n8:24 AM\n\nYou may view",
            iso("2026-06-02T20:42:49Z")))
        #expect(rows.count == 1); #expect(rows.first?.amount == "32.76")
    }

    @Test func youTripHTMLVersionFromGmailAPI() {
        let rows = EmailParsers.parse(msg("h3", "noreply@you.co", "Summary of your recent online purchases & ATM withdrawals",
            "Here’s a summary of your online purchases and ATM withdrawals in the last 24 hours. The times shown are based on Singapore Time (UTC+8) . UBER * EATS PENDING~1 Some Street~Sydney~2000 036 AUD 32.76 Ref. No: SFT-1 8:24 AM You may view the full transaction history",
            iso("2026-06-02T20:42:49Z")))
        #expect(rows.count == 1); #expect(rows.first?.merchant == "Uber Eats"); #expect(rows.first?.amount == "32.76")
    }

    @Test func stripeLayouts() {
        let buy = one(msg("i", "receipts+acct_x@stripe.com", "s", "Receipt from Test Rentals (Test Co Pty Ltd) Receipt #1-2\nAmount paid\nA$68.30\nPayment method\n- 1111"))
        let back = one(msg("j", "receipts+acct_x@stripe.com", "s", "Refund from Meal Co Receipt #3-4\nRefunded\nA$230.05\nRefunded to\n- 3333"))
        let inv = one(msg("k", "invoice+statements@mail.anthropic.com", "s", "Receipt from Some AI, PBC S$137.61 Paid September 3, 2026 Payment method - 9999 Receipt #1 Sep 3–Oct 3, 2026 Pro plan Qty 1 S$137.61"))
        #expect(buy?.kind == "purchase"); #expect(buy?.merchant == "Test Rentals"); #expect(buy?.amount == "68.30"); #expect(buy?.last4 == "1111")
        #expect(back?.kind == "refund"); #expect(back?.amount == "230.05"); #expect(back?.last4 == "3333")
        #expect(inv?.merchant == "Some AI"); #expect(inv?.currency == "SGD"); #expect(inv?.last4 == "9999")
    }

    @Test func stripeInvoiceRefund() {
        let r = one(msg("l", "invoice+statements@mail.anthropic.com", "Your refund from Some AI",
                        "Refund from Some AI, PBC S$2.48 Refunded on July 3, 2026 (invoice illustration) Receipt number 1 Refunded to - 3333"))
        #expect(r?.kind == "refund"); #expect(r?.merchant == "Some AI"); #expect(r?.amount == "2.48"); #expect(r?.currency == "SGD")
    }

    @Test func unknownSenderIgnored() {
        #expect(EmailParsers.parse(msg("z", "ads@bank.example", "promo", "S$10 off")).isEmpty)
    }
}

/// Receipts from senders Sortd has no special rules for.
struct GenericReceiptTests {
    private func msg(_ from: String, _ subject: String, _ body: String) -> EmailParsers.Message {
        .init(id: "g", from: from, subject: subject, body: body, date: .now)
    }

    @Test func supermarketOrder() {
        let r = GenericReceipts.parse(msg("Fresh Mart <orders@freshmart.example>", "Your order confirmation #4411",
            "Thanks for shopping. Subtotal $80.10 Delivery $5.00 Order total $85.10 Paid with Visa ending in 4242"))
        #expect(r?.amount == "85.10"); #expect(r?.last4 == "4242"); #expect(r?.kind == "purchase"); #expect(r?.merchant == "Fresh Mart")
    }

    @Test func airlineGrandTotalBeatsFares() {
        let r = GenericReceipts.parse(msg("SkyJet <noreply@skyjet.example>", "Your booking receipt from SkyJet",
            "Base fare AUD 150.00 Taxes AUD 39.00 Grand total AUD 189.00"))
        #expect(r?.amount == "189.00"); #expect(r?.currency == "AUD"); #expect(r?.merchant == "SkyJet")
    }

    @Test func bankAlertWithCardDigits() {
        let r = GenericReceipts.parse(msg("Example Bank <alerts@examplebank.example>", "Transaction alert",
            "A purchase of $12.50 was made on your card ending 1234 at CORNER CAFE."))
        #expect(r?.amount == "12.50"); #expect(r?.last4 == "1234")
    }

    @Test func rideReceiptWithThousands() {
        let r = GenericReceipts.parse(msg("RideCo Receipts <receipts@rideco.example>", "Your trip receipt",
            "Trip fare S$1,204.30 Total S$1,204.30 Paid with •••• 9876"))
        #expect(r?.amount == "1204.30"); #expect(r?.currency == "SGD"); #expect(r?.last4 == "9876"); #expect(r?.merchant == "RideCo")
    }

    @Test func refundIsRefund() {
        let r = GenericReceipts.parse(msg("Shop <help@shop.example>", "Your refund is on its way",
            "We have refunded your order. Amount paid back: Total $25.99"))
        #expect(r?.kind == "refund"); #expect(r?.amount == "25.99")
    }

    @Test func promotionIgnored() {
        #expect(GenericReceipts.parse(msg("Shop <deals@shop.example>", "50% off everything this weekend",
            "Total savings $20.00 when you spend $40.00")) == nil)
    }

    @Test func shippingUpdateWithoutPriceIgnored() {
        #expect(GenericReceipts.parse(msg("Shop <orders@shop.example>", "Your order has shipped",
            "Your parcel is on the way. Track it here.")) == nil)
    }

    @Test func notPurchases() {
        for subject in ["Shipped: 2 ‘Old Spice…’", "Out for delivery: ‘Case’", "Payment declined: Update your information",
                        "Your order has been picked up (#76290)", "Subscription renewal: Payment in 30 days",
                        "Re: Your Nourish'd receipt", "Monthly Statement of Margin Account"] {
            #expect(GenericReceipts.isNotAPurchase(subject), "\(subject)")
        }
        for subject in ["Your receipt from YOI", "Ordered: \"ESR case\"", "Your invoice is available", "Order Confirmation"] {
            #expect(!GenericReceipts.isNotAPurchase(subject), "\(subject)")
        }
    }

    @Test func declinedPaymentIsNotAPurchase() {
        #expect(GenericReceipts.parse(msg("Shop <orders@shop.example>", "Payment declined: update your card",
            "We couldn't charge Order total $24.99 to your card ending 1234")) == nil)
    }

    @Test func aiAmountMustBeInTheEmail() {
        #expect(GenericReceipts.appears("1204.30", in: "Total S$1,204.30"))
        #expect(GenericReceipts.appears("42.50", in: "Paid $42.50 today"))
        #expect(!GenericReceipts.appears("99.99", in: "Paid $42.50 today"))
    }

    @Test func knownSendersKeepTheirExactRules() {
        #expect(EmailParsers.knowsSender("DoorDash <no-reply@doordash.com>"))
        #expect(!EmailParsers.knowsSender("Fresh Mart <orders@freshmart.example>"))
    }
}

@MainActor
struct SpendSummaryTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return c
    }()
    private let home = Money.home
    private var now: Date { day("2026-09-19", hour: 12) }

    private func day(_ s: String, hour: Int = 10) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH"; f.timeZone = cal.timeZone
        return f.date(from: "\(s) \(hour)")!
    }
    private func buy(_ d: String, _ merchant: String, _ amount: Decimal,
                     _ cat: SpendCategory = .shopping, refunded: Bool = false) -> SpendSummary.Purchase {
        .init(date: day(d), merchant: merchant, amount: amount, currency: home, category: cat, refunded: refunded)
    }
    private func m(_ v: Decimal) -> String { Money.format(v, home, cents: false) }

    private var sample: [SpendSummary.Purchase] {
        [buy("2026-09-02", "Rent", 1000, .housing),
         buy("2026-09-10", "Woolworths", 200, .groceries),
         buy("2026-09-19", "Coles", 40, .groceries),
         buy("2026-09-05", "YouTrip top-up", 500, .transfers),
         buy("2026-09-12", "Myer", 80, refunded: true),
         buy("2026-08-30", "Last month", 999)]
    }

    @Test func monthTotalWithBudget() {
        let r = SpendSummary.spent(sample, period: .month, budget: 2000, currency: home, now: now, calendar: cal)
        #expect(r.total == 1240)
        #expect(r.text == "You've spent \(m(1240)) this month, \(m(760)) left of your \(m(2000)) budget.")
    }

    @Test func todayLeavesOutBudget() {
        let r = SpendSummary.spent(sample, period: .today, budget: 2000, currency: home, now: now, calendar: cal)
        #expect(r.total == 40)
        #expect(r.text == "You've spent \(m(40)) today.")
    }

    @Test func overBudgetWording() {
        let r = SpendSummary.spent(sample, period: .month, budget: 1000, currency: home, now: now, calendar: cal)
        #expect(r.text.hasSuffix("\(m(240)) over your \(m(1000)) budget."))
        let left = SpendSummary.budgetLeft(sample, budget: 1000, currency: home, now: now, calendar: cal)
        #expect(left.left == -240)
        #expect(left.text == "You're \(m(240)) over your \(m(1000)) budget this month.")
    }

    @Test func budgetLeftUnderAndUnset() {
        let r = SpendSummary.budgetLeft(sample, budget: 2000, currency: home, now: now, calendar: cal)
        #expect(r.left == 760)
        #expect(r.text == "You have \(m(760)) left of your \(m(2000)) budget this month.")
        #expect(SpendSummary.budgetLeft(sample, budget: 0, currency: home, now: now, calendar: cal).text.contains("haven't set"))
    }

    @Test func categoryFilter() {
        let r = SpendSummary.spent(sample, period: .month, category: .groceries, budget: 2000,
                                   currency: home, now: now, calendar: cal)
        #expect(r.total == 240)
        #expect(r.text == "You've spent \(m(240)) on Groceries this month.")
        let none = SpendSummary.spent(sample, period: .month, category: .travel, currency: home, now: now, calendar: cal)
        #expect(none.total == 0)
        #expect(none.text == "You haven't spent anything on Travel this month.")
    }

    @Test func emptyData() {
        #expect(SpendSummary.spent([], period: .month, budget: 2000, currency: home, now: now, calendar: cal).text == "No purchases yet.")
        #expect(SpendSummary.lastPurchase([], now: now, calendar: cal) == "No purchases yet.")
        #expect(SpendSummary.upcomingBills([], hasPurchases: false, now: now, calendar: cal) == "No purchases yet.")
        #expect(SpendSummary.budgetLeft([], budget: 500, currency: home, now: now, calendar: cal).left == 500)
    }

    @Test func lastPurchaseSkipsRefundsAndTransfers() {
        let items = sample + [buy("2026-09-19", "Refunded", 30, refunded: true)]
        #expect(SpendSummary.lastPurchase(items, now: now, calendar: cal)
                == "Your last purchase was \(Money.format(40, home)) at Coles today.")
    }

    @Test func upcomingBillsWithinTwoWeeks() {
        func bill(_ name: String, _ next: String, status: Recurring.Status = .active) -> Recurring {
            Recurring(key: name, merchant: name, category: .subscriptions, card: .nab, cadence: .monthly,
                      amount: 10, currency: home, audAmount: 10, lastDate: day("2026-08-20"),
                      nextDate: day(next), charges: 3, previousAmount: nil, status: status, chargedAfterCancel: false)
        }
        let bills = [bill("Later", "2026-10-20"), bill("Spotify", "2026-09-20"), bill("Gym", "2026-09-25"),
                     bill("Phone", "2026-09-30"), bill("Rent", "2026-10-02"), bill("Old", "2026-09-21", status: .cancelled)]
        let text = SpendSummary.upcomingBills(bills, hasPurchases: true, now: now, calendar: cal)
        #expect(text.hasPrefix("Your next 3 bills are: Spotify \(Money.format(10, home)) tomorrow, Gym"))
        #expect(!text.contains("Rent") && !text.contains("Later") && !text.contains("Old"))
        #expect(SpendSummary.upcomingBills([bill("Later", "2026-10-20")], hasPurchases: true, now: now, calendar: cal)
                == "No bills due in the next 14 days.")
    }
}
