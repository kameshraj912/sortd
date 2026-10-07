import Testing
import Foundation
import SwiftData
@testable import Spend

/// Apple Pay in apps and on websites (2 Oct 2026): the iOS 27 Notification
/// trigger hands `LogWalletTapIntent` Wallet's notification as Title,
/// Subtitle and Body. Every test goes through the real intent path
/// (`LogWalletTapIntent.handle`) with a pinned `now:`.
///
/// What Wallet's notification really says for an online payment is not
/// known yet (needs Raj's phone), so the parts are tried in every order and
/// in several shapes.
@MainActor
struct ApplePayOnlineNotificationTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "online-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func rows(_ ctx: ModelContext) throws -> [Transaction] {
        try ctx.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)]))
    }

    /// One notification run. The tap fields are left blank, as Shortcuts
    /// sends an unset variable, unless a test says otherwise.
    @discardableResult
    private func notify(_ title: String?, _ subtitle: String?, _ body: String?,
                        amount: String? = "", merchant: String? = "", card: String? = "",
                        ctx: ModelContext, book: CardBook, at date: Date? = nil) async throws -> LogPurchaseIntent.Outcome {
        try await LogWalletTapIntent.handle(nil, amount: amount, merchant: merchant, card: card,
                                            notificationTitle: title, notificationSubtitle: subtitle,
                                            notificationBody: body, in: ctx, book: book, now: date ?? now)
    }

    // MARK: - Title, Subtitle and Body in any order

    static let sixOrders: [[Int]] = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

    @Test(arguments: sixOrders)
    func cardShopAndAmountInEveryOrder(order: [Int]) async throws {
        let ctx = store(), b = book()
        let parts = ["NAB Visa Debit", "DoorDash", "A$23.40"]
        let r = try await notify(parts[order[0]], parts[order[1]], parts[order[2]], ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "DoorDash")
        #expect(t.amount == Decimal(string: "23.40"))
        #expect(t.currencyCode == "AUD")
        #expect(b.info(t.card)?.name == "NAB Visa Debit")
        #expect(t.tapOrigins == "n")
        #expect(!t.needsCheck)
        #expect(try rows(ctx).count == 1)
    }

    /// A card the person already has, named only by its bank word (no
    /// "Visa", no "Debit", no digits), is still the card and not the shop —
    /// whichever line it is on.
    @Test(arguments: sixOrders)
    func aKnownCardWithNoCardWordsIsStillTheCard(order: [Int]) async throws {
        let ctx = store(), b = book()
        b.upsert(CardInfo(id: "yt", name: "YouTrip", shortName: "YouTrip", bank: "YouTrip",
                          currency: "SGD", country: "SG", walletWords: ["youtrip"]))
        let parts = ["YouTrip", "Grab", "S$12.80"]
        let r = try await notify(parts[order[0]], parts[order[1]], parts[order[2]], ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "Grab")
        #expect(t.card == Card(rawValue: "yt"))
        #expect(t.currencyCode == "SGD")
    }

    // MARK: - Amounts

    struct AmountCase: Sendable, CustomTestStringConvertible {
        let text: String
        let amount: String
        let currency: String?
        var testDescription: String { text }
    }

    static let amounts: [AmountCase] = [
        .init(text: "A$23.40", amount: "23.40", currency: "AUD"),
        .init(text: "S$23.40", amount: "23.40", currency: "SGD"),
        .init(text: "AUD 23.40", amount: "23.40", currency: "AUD"),
        .init(text: "SGD 23.40", amount: "23.40", currency: "SGD"),
        .init(text: "€23.40", amount: "23.40", currency: "EUR"),
        .init(text: "£23.40", amount: "23.40", currency: "GBP"),
        .init(text: "¥2340", amount: "2340", currency: "JPY"),
        .init(text: "RM23.40", amount: "23.40", currency: "MYR"),
        .init(text: "A$1,234.50", amount: "1234.50", currency: "AUD"),
        // No currency in the text: the card's currency.
        .init(text: "$23.40", amount: "23.40", currency: nil),
        .init(text: "23.40", amount: "23.40", currency: nil),
        .init(text: "1,234.50", amount: "1234.50", currency: nil),
    ]

    @Test(arguments: amounts)
    func everyAmountShapeIsRead(_ c: AmountCase) async throws {
        let ctx = store(), b = book()
        // A card in Singapore dollars, so "card's currency" is visible.
        b.upsert(CardInfo(id: "dbs", name: "DBS Visa Debit", shortName: "DBS", bank: "DBS",
                          currency: "SGD", country: "SG", walletWords: ["dbs"]))
        let r = try await notify("DBS Visa Debit", "Amazon.com.au", c.text, ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.amount == Decimal(string: c.amount))
        #expect(t.currencyCode == (c.currency ?? "SGD"))
        #expect(t.rawMerchant == "Amazon.com.au")
    }

    /// No currency in the text and no card at all: the home currency.
    @Test func noCurrencyAndNoCardFallsBackToHome() async throws {
        let ctx = store(), b = book()
        let r = try await notify("", "DoorDash", "$23.40", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.card == .other)
        #expect(t.currencyCode == Money.home)
    }

    // MARK: - Cards

    @Test func aMaskedMastercardIsTheCard() async throws {
        let ctx = store(), b = book()
        let r = try await notify("DoorDash", "A$23.40", "Mastercard ••4821", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "DoorDash")
        #expect(t.card != .other)
        #expect(b.info(t.card)?.allLast4.contains("4821") == true)
    }

    @Test func visaEndingDigitsIsTheCard() async throws {
        let ctx = store(), b = book()
        let r = try await notify("Visa ending 1234", "UBER *EATS", "A$31.10", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "UBER *EATS")
        #expect(t.amount == Decimal(string: "31.10"))
    }

    /// A bank Sortd has no preset for still reads as a card when Wallet
    /// says Debit, and the shop is not swallowed into it.
    @Test func anUnknownBankCardIsTheCardNotTheShop() async throws {
        let ctx = store(), b = book()
        let r = try await notify("PAYPAL *SPOTIFY", "Zeta Bank Debit ••7700", "A$13.99", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "PAYPAL *SPOTIFY")
        #expect(t.card != .other)
    }

    // MARK: - Shops

    @Test func anEmojiShopIsKept() async throws {
        let ctx = store(), b = book()
        let r = try await notify("NAB Visa Debit", "☕️ Little Cafe", "A$5.50", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "☕️ Little Cafe")
        #expect(!t.needsCheck)
    }

    @Test func aTwoHundredCharacterShopIsKeptAndCapped() async throws {
        let ctx = store(), b = book()
        let longName = String(String(repeating: "Bakery Deluxe ", count: 20).prefix(200))
        #expect(longName.count == 200)
        let r = try await notify("NAB Visa Debit", longName, "A$9.00", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.amount == 9)
        #expect(!t.merchant.isEmpty)
        #expect(t.merchant.count <= MerchantName.maxLength)
        #expect(try rows(ctx).count == 1)
    }

    // MARK: - One sentence in the body

    @Test func aWholeSentenceInTheBody() async throws {
        let ctx = store(), b = book()
        let r = try await notify("Apple Pay", "", "$23.40 paid to DoorDash with Mastercard ••4821", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "DoorDash")
        #expect(t.amount == Decimal(string: "23.40"))
        #expect(b.info(t.card)?.allLast4.contains("4821") == true)
    }

    @Test func youPaidShopAmount() async throws {
        let ctx = store(), b = book()
        let r = try await notify("Wallet", "You paid DoorDash A$23.40", "", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "DoorDash")
        #expect(t.amount == Decimal(string: "23.40"))
        #expect(t.currencyCode == "AUD")
    }

    // MARK: - Payments that did not happen

    @Test(arguments: [
        "Payment declined",
        "Transaction not completed",
        "Payment failed",
        "Unsuccessful payment",
        "Your payment couldn't be completed",
        "Your payment couldn’t be completed",
        "Insufficient funds",
    ])
    func aPaymentThatDidNotHappenSavesNothing(_ wording: String) async throws {
        let ctx = store(), b = book()
        let r = try await notify("NAB Visa Debit", "DoorDash", "\(wording) · A$23.40", ctx: ctx, book: b)
        #expect(r.transaction == nil)
        #expect(!r.saveFailed)
        #expect(try rows(ctx).isEmpty)
        #expect(b.cards.isEmpty)
    }

    // MARK: - Refunds

    @Test func aRefundNotificationMarksTheEarlierPurchaseRefunded() async throws {
        let ctx = store(), b = book()
        try await notify("NAB Visa Debit", "DoorDash", "A$23.40", ctx: ctx, book: b, at: now.addingTimeInterval(-86_400))
        let r = try await notify("NAB Visa Debit", "Refund from DoorDash", "A$23.40", ctx: ctx, book: b)
        #expect(r.merged)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.refunded == true)
    }

    @Test func aRefundedWordWithNoEarlierPurchaseIsAStandaloneRefund() async throws {
        let ctx = store(), b = book()
        let r = try await notify("Refunded", "DoorDash", "A$23.40", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.refunded)
        #expect(t.rawMerchant == "DoorDash")
        #expect(Activation.detect(t) == nil)
    }

    @Test func aLeadingMinusIsARefund() async throws {
        let ctx = store(), b = book()
        let r = try await notify("NAB Visa Debit", "DoorDash", "-A$23.40", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.refunded)
        #expect(t.amount == Decimal(string: "23.40"))
    }

    // MARK: - Wallet notifications that are not payments

    @Test(arguments: [
        ["Qantas", "Boarding pass", "QF401 to Sydney, Gate 12, boards 10:40"],
        ["Uber Eats", "Your order is on its way", ""],
        ["Wallet", "Card added to Wallet", "NAB Visa Debit is ready to use with Apple Pay"],
        ["Myki", "Touched on at Flinders Street", ""],
        ["SimplyGo", "Journey started", "Bus 961"],
        ["", "", "A$0.00"],
    ])
    func aNotificationWithNoAmountSavesNothing(_ parts: [String]) async throws {
        let ctx = store(), b = book()
        let r = try await notify(parts[0], parts[1], parts[2], ctx: ctx, book: b)
        #expect(r.transaction == nil)
        #expect(r.message == "Sortd saw a Wallet notification with no amount.")
        #expect(try rows(ctx).isEmpty)
        #expect(b.cards.isEmpty)
    }

    @Test func transitWithAnAmountIsLogged() async throws {
        let ctx = store(), b = book()
        let myki = try await notify("Myki", "Top up", "A$20.00", ctx: ctx, book: b)
        #expect(myki.transaction?.amount == 20)
        let simplyGo = try await notify("SimplyGo", "Bus 961", "S$1.79", ctx: ctx, book: b, at: now.addingTimeInterval(3600))
        #expect(simplyGo.transaction?.amount == Decimal(string: "1.79"))
        #expect(simplyGo.transaction?.currencyCode == "SGD")
        #expect(try rows(ctx).count == 2)
    }

    // MARK: - Blank and stray fields

    @Test func aBlankTitleStillLogsFromSubtitleAndBody() async throws {
        let ctx = store(), b = book()
        let r = try await notify("", "DoorDash", "A$23.40", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "DoorDash")
        #expect(t.card == .other)
        #expect(!t.needsCheck)
    }

    /// The tap fields are ignored on a notification run, whatever they hold.
    @Test func strayTextInTheTapFieldsIsIgnored() async throws {
        let ctx = store(), b = book()
        let r = try await notify("NAB Visa Debit", "DoorDash", "A$23.40",
                                 amount: "A$99.00", merchant: "Shortcut Input", card: "Wallet",
                                 ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.amount == Decimal(string: "23.40"))
        #expect(t.rawMerchant == "DoorDash")
        #expect(b.info(t.card)?.name == "NAB Visa Debit")
        #expect(b.cards.count == 1)
    }

    /// All three notification fields blank (or Shortcuts' own placeholder
    /// names): exactly today's tap behaviour.
    @Test func allThreeBlankIsATapRunAsToday() async throws {
        let ctx = store(), b = book()
        let r = try await notify("Title", " ", "\u{200B}",
                                 amount: "A$4.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                 ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.rawMerchant == "Seven Seeds")
        #expect(t.tapOrigins == "t")
    }

    @Test func allSixBlankIsStillAPreviewRun() async throws {
        let ctx = store(), b = book()
        let r = try await notify("", "", "", ctx: ctx, book: b)
        #expect(r.transaction == nil)
        #expect(r.message.contains("connected"))
        #expect(try rows(ctx).isEmpty)
    }

    // MARK: - A missing shop

    @Test func anAmountWithNoShopIsKeptAndFlagged() async throws {
        let ctx = store(), b = book()
        let r = try await notify("NAB Visa Debit", "", "A$23.40", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.merchant == "Unknown merchant")
        #expect(t.needsCheck)
        #expect(Activation.detect(t) == nil)
        #expect(ApplePayStatus.resolve(lastReachedAt: now, taps: [t], now: now) == .tapNeedsCheck(date: now))
        #expect(ApplePayStatus.needsCheckCount(in: [t]) == 1)
    }

    // MARK: - Status and Activation after an online purchase

    @Test func anOnlinePurchaseCountsForStatusAndActivation() async throws {
        let ctx = store(), b = book()
        let r = try await notify("NAB Visa Debit", "DoorDash", "A$23.40", ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(Activation.detect(t) == .tap)
        #expect(ApplePayStatus.resolve(lastReachedAt: now, taps: [t], now: now)
                == .tapLogged(date: now, merchant: t.merchant, amount: t.amount, currency: "AUD"))
        #expect(ApplePayStatus.needsCheckCount(in: [t]) == 0)
    }

    @Test func aNotificationWithNoAmountLeavesTheStatusAtReached() async throws {
        let ctx = store(), b = book()
        try await notify("Qantas", "Boarding pass", "Gate 12", ctx: ctx, book: b)
        #expect(ApplePayStatus.resolve(lastReachedAt: now, taps: try rows(ctx), now: now) == .shortcutReached(now))
    }

    // MARK: - Bank app sentences

    private let bankSentence = "You spent $23.40 at DOORDASH with your card ending 4821."

    @Test func aBankSentenceSavesARow() async throws {
        let ctx = store(), b = book()
        let r = try await notify("CommBank", nil, bankSentence, ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.amount == Decimal(string: "23.40"))
        #expect(t.rawMerchant.lowercased() == "doordash")
        #expect(t.tapOrigins == "b")
        #expect(t.seenByBank)
        #expect(!t.needsCheck)
        #expect(t.category == .foodDelivery)
        #expect(try rows(ctx).count == 1)
    }

    @Test func aBankSentenceMatchesTheCardByLastFour() async throws {
        let ctx = store(), b = book()
        b.upsert(CardInfo(id: "cba", name: "CommBank Debit", shortName: "CommBank", bank: "CommBank", last4: ["4821"]))
        let r = try await notify("CommBank", nil, bankSentence, ctx: ctx, book: b)
        let t = try #require(r.transaction)
        #expect(t.card == Card(rawValue: "cba"))
    }

    @Test func aBankNoticeThatIsNotAPurchaseSavesNothing() async throws {
        let ctx = store(), b = book()
        let r = try await notify("CommBank", nil, "Your available balance is $1,204.11", ctx: ctx, book: b)
        #expect(r.transaction == nil)
        #expect(r.dropped == .notAPurchase)
        #expect(try rows(ctx).count == 0)
        #expect(LogPurchaseIntent.lastTapReceivedAt != nil)
    }

    /// A tap, Wallet's notification and the bank's notice for one payment:
    /// one row, the tap's shop name, all three letters in t, n, b order.
    @Test func tapThenWalletThenBankIsOneRow() async throws {
        let ctx = store(), b = book()
        try await notify("", "", "", amount: "A$23.40", merchant: "DoorDash", card: "NAB Visa Debit",
                         ctx: ctx, book: b, at: now)
        try await notify("NAB Visa Debit", "DoorDash", "A$23.40", ctx: ctx, book: b, at: now.addingTimeInterval(30))
        let third = try await notify("CommBank", nil, "You spent $23.40 at DOORDASH*ORDER with your card ending 4821.",
                                     ctx: ctx, book: b, at: now.addingTimeInterval(60))
        #expect(third.merged)
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "tnb")
        #expect(all.first?.rawMerchant == "DoorDash")
    }

    /// A tap that joins a bank-only row replaces the bank's shop name.
    @Test func bankThenTapKeepsTheTapsName() async throws {
        let ctx = store(), b = book()
        try await notify("CommBank", nil, "You spent $23.40 at DOORDASH*ORDER with your card ending 4821.",
                         ctx: ctx, book: b, at: now)
        try await notify("", "", "", amount: "A$23.40", merchant: "DoorDash", card: "NAB Visa Debit",
                         ctx: ctx, book: b, at: now.addingTimeInterval(120))
        let all = try rows(ctx)
        #expect(all.count == 1)
        #expect(all.first?.rawMerchant == "DoorDash")
        #expect(all.first?.tapOrigins == "tb")
    }

    @Test func aBankSentenceElevenMinutesLaterIsItsOwnRow() async throws {
        let ctx = store(), b = book()
        try await notify("", "", "", amount: "A$23.40", merchant: "DoorDash", card: "NAB Visa Debit",
                         ctx: ctx, book: b, at: now)
        try await notify("CommBank", nil, bankSentence, ctx: ctx, book: b, at: now.addingTimeInterval(11 * 60))
        #expect(try rows(ctx).count == 2)
    }
}
