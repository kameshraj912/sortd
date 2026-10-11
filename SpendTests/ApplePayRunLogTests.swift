import Testing
import Foundation
import SwiftData
@testable import Spend

/// The hidden run log (8 Oct 2026): one `apple_pay_run` event per Shortcuts
/// run that reaches Sortd, saying what kind of run it was and what came of
/// it, never words or money. The event is built by a pure function
/// (`LogWalletTapIntent.runEvent`); runs go through the real intent path
/// with a pinned `now:`.
@MainActor
struct ApplePayRunLogTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "runlog-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private typealias Event = [String: Analytics.AnalyticsValue]

    /// `AnalyticsValue` is not Equatable, so read it by pattern.
    private func string(_ event: Event, _ key: String) -> String? {
        if case .string(let s)? = event[key] { return s }
        return nil
    }
    private func flag(_ event: Event, _ key: String) -> Bool? {
        if case .bool(let b)? = event[key] { return b }
        return nil
    }

    private typealias Run = (outcome: LogPurchaseIntent.Outcome, event: Event)

    /// One run through the real intent path, and the event it would log.
    /// `queueURL` is the test's own queue file, for a forced save failure.
    private func run(text: String? = nil, amount: String? = nil, merchant: String? = nil, card: String? = nil,
                     title: String? = nil, subtitle: String? = nil, body: String? = nil, app: String? = nil,
                     in ctx: ModelContext, book b: CardBook, at date: Date,
                     forceSaveFailure: Bool = false, queueURL: URL? = nil) async throws -> Run {
        let outcome = try await LogWalletTapIntent.handle(text, amount: amount, merchant: merchant, card: card,
                                                          notificationTitle: title, notificationSubtitle: subtitle,
                                                          notificationBody: body, notificationApp: app,
                                                          in: ctx, book: b, now: date,
                                                          debugForceSaveFailure: forceSaveFailure, queueURL: queueURL)
        let event = LogWalletTapIntent.runEvent(outcome: outcome, transaction: text, amount: amount, merchant: merchant,
                                                card: card,
                                                notification: WalletNotification(title: title, subtitle: subtitle, body: body,
                                                                                 app: app))
        return (outcome, event)
    }

    // MARK: - Every run this suite makes

    private func fullTap() async throws -> Run {
        try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit", in: store(), book: book(), at: now)
    }
    private func sameTapTwice() async throws -> Run {
        let ctx = store(), b = book()
        _ = try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit", in: ctx, book: b, at: now)
        return try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                             in: ctx, book: b, at: now.addingTimeInterval(30))
    }
    private func cardOnlyTap() async throws -> Run {
        try await run(card: "NAB Visa Debit", in: store(), book: book(), at: now)
    }
    private func blankRun() async throws -> Run {
        try await run(in: store(), book: book(), at: now)
    }
    private func freeTextTap() async throws -> Run {
        try await run(text: "Seven Seeds A$5.50 NAB Visa Debit", in: store(), book: book(), at: now)
    }
    private func healthCheck() async throws -> Run {
        try await run(amount: "A$0.01", merchant: ApplePayHealthCheck.merchant, card: "Test Card",
                      in: store(), book: book(), at: now)
    }
    private func declined() async throws -> Run {
        try await run(title: "Payment declined", body: "A$23.40 at DoorDash", in: store(), book: book(), at: now)
    }
    private func notificationWithNoAmount() async throws -> Run {
        try await run(title: "Uber Eats", body: "Your order is on its way", in: store(), book: book(), at: now)
    }
    private func moneyIn() async throws -> Run {
        try await run(title: "Wallet", body: "You received $25.00 from J Tan", in: store(), book: book(), at: now)
    }
    private func refundAfterPurchase() async throws -> Run {
        let ctx = store(), b = book()
        _ = try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit", in: ctx, book: b, at: now)
        return try await run(amount: "-A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                             in: ctx, book: b, at: now.addingTimeInterval(60))
    }
    /// A forced save failure queues to this test's own file, never the real
    /// queue the test host app replays at launch.
    private func queuedNotification() async throws -> Run {
        let url = FileManager.default.temporaryDirectory.appending(path: "runlog-queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        return try await run(title: "DoorDash", body: "A$23.40", in: store(), book: book(), at: now,
                             forceSaveFailure: true, queueURL: url)
    }

    private func everyRun() async throws -> [Run] {
        [try await fullTap(), try await sameTapTwice(), try await cardOnlyTap(), try await blankRun(),
         try await freeTextTap(), try await healthCheck(), try await declined(), try await notificationWithNoAmount(),
         try await moneyIn(), try await refundAfterPurchase(), try await queuedNotification()]
    }

    private let allowedWords: Set<String> = ["tap", "notification", "saved", "merged", "needs_check", "blank", "empty_run",
                                             "no_amount", "not_completed", "money_in", "refund", "health_check",
                                             "queued", "not_saved", "not_purchase", "bank"]
    /// Ten since 9 Oct 2026 (`has_app`).
    private let eventKeys: Set<String> = ["kind", "result", "has_amount", "has_shop", "has_card", "has_app",
                                         "has_title", "has_subtitle", "has_body", "has_text"]

    // MARK: - What kind of run, and what came of it

    @Test func aFullTapIsSaved() async throws {
        let r = try await fullTap()
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "saved")
        #expect(flag(r.event, "has_amount") == true)
        #expect(flag(r.event, "has_shop") == true)
        #expect(flag(r.event, "has_card") == true)
        #expect(flag(r.event, "has_title") == false)
        #expect(flag(r.event, "has_subtitle") == false)
        #expect(flag(r.event, "has_body") == false)
        #expect(flag(r.event, "has_text") == false)
    }

    @Test func theSameTapAgainIsMerged() async throws {
        let second = try await sameTapTwice()
        #expect(second.outcome.merged)
        #expect(string(second.event, "result") == "merged")
    }

    @Test func aCardOnlyTapNeedsACheck() async throws {
        let r = try await cardOnlyTap()
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "needs_check")
        #expect(flag(r.event, "has_amount") == false)
        #expect(flag(r.event, "has_shop") == false)
        #expect(flag(r.event, "has_card") == true)
    }

    /// A run with no field at all and no check running is `empty_run`
    /// (10 Oct 2026: it used to read as "blank").
    @Test func anEmptyRunWithNoCheckIsEmptyRun() async throws {
        let r = try await blankRun()
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "empty_run")
        for key in ["has_amount", "has_shop", "has_card", "has_title", "has_subtitle", "has_body", "has_text"] {
            #expect(flag(r.event, key) == false, "\(key) should be false")
        }
    }

    /// The old free-text Transaction field: parsed and saved, and only
    /// `has_text` says it came in.
    @Test func aFreeTextTapHasText() async throws {
        let r = try await freeTextTap()
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "saved")
        #expect(flag(r.event, "has_text") == true)
        #expect(flag(r.event, "has_amount") == false)
    }

    /// "Check the Shortcut" in Apple Pay setup is not a purchase.
    @Test func aHealthCheckRunIsHealthCheck() async throws {
        let r = try await healthCheck()
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "health_check")
    }

    /// What "Check the Shortcut" really sends: the ready-made shortcut has
    /// no Text step, so the run arrives with every field empty. Inside the
    /// check's window it is `health_check`; before the tap or after the
    /// window it is `empty_run` (beta data, 10 Oct 2026).
    @Test func anEmptyRunDuringACheckIsHealthCheck() async throws {
        let ctx = store()
        let outcome = try await LogWalletTapIntent.handle(nil, amount: nil, merchant: nil, card: nil,
                                                          in: ctx, book: book(), now: now)
        func result(startedAt: Date?, at date: Date) -> String? {
            string(LogWalletTapIntent.runEvent(outcome: outcome, transaction: nil, amount: nil, merchant: nil, card: nil,
                                               notification: WalletNotification(),
                                               checkStartedAt: startedAt, now: date), "result")
        }
        #expect(result(startedAt: now, at: now.addingTimeInterval(3)) == "health_check")
        #expect(result(startedAt: now, at: now.addingTimeInterval(ApplePayHealthCheck.timeout)) == "health_check")
        #expect(result(startedAt: now, at: now.addingTimeInterval(ApplePayHealthCheck.timeout + 1)) == "empty_run")
        #expect(result(startedAt: now, at: now.addingTimeInterval(-5)) == "empty_run")
        #expect(result(startedAt: nil, at: now) == "empty_run")
    }

    /// A run that brought a field is never taken for the check, even
    /// during one.
    @Test func aRunWithAFieldDuringACheckIsNotHealthCheck() async throws {
        let ctx = store()
        let outcome = try await LogWalletTapIntent.handle(nil, amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                                          in: ctx, book: book(), now: now)
        let event = LogWalletTapIntent.runEvent(outcome: outcome, transaction: nil, amount: "A$5.50", merchant: "Seven Seeds",
                                                card: "NAB Visa Debit", notification: WalletNotification(),
                                                checkStartedAt: now, now: now.addingTimeInterval(2))
        #expect(string(event, "result") == "saved")
    }

    /// The check's start time goes to the intent's own defaults and back.
    @Test func theCheckStartIsKeptWhereTheIntentReadsIt() {
        let d = UserDefaults(suiteName: "runlog-check-\(UUID().uuidString)")!
        #expect(ApplePayHealthCheck.lastStartedAt(d) == nil)
        ApplePayHealthCheck.markStarted(at: now, defaults: d)
        #expect(ApplePayHealthCheck.lastStartedAt(d) == now)
    }

    // MARK: - Runs that were dropped

    @Test func aDeclinedNotificationIsNotCompleted() async throws {
        let r = try await declined()
        #expect(r.outcome.dropped == .notCompleted)
        #expect(string(r.event, "kind") == "notification")
        #expect(string(r.event, "result") == "not_completed")
        #expect(flag(r.event, "has_title") == true)
        #expect(flag(r.event, "has_body") == true)
        #expect(flag(r.event, "has_subtitle") == false)
    }

    @Test func aNotificationWithNoAmountIsNoAmount() async throws {
        let r = try await notificationWithNoAmount()
        #expect(r.outcome.dropped == .noAmount)
        #expect(string(r.event, "kind") == "notification")
        #expect(string(r.event, "result") == "no_amount")
    }

    /// A bank app's balance alert: a bank run (8 Oct 2026 review: kind
    /// "bank", was "notification"), not a purchase.
    @Test func aBankNoticeThatIsNotAPurchaseIsNotPurchase() async throws {
        let r = try await run(body: "Your available balance is $1,204.11", in: store(), book: book(), at: now)
        #expect(r.outcome.dropped == .notAPurchase)
        #expect(string(r.event, "kind") == "bank")
        #expect(string(r.event, "result") == "not_purchase")
    }

    /// The shortcut says which app sent it: a bank's app makes a bank run,
    /// even for a short line.
    @Test func aRunFromABanksAppSaysSo() async throws {
        let r = try await run(title: "Payment received", body: "$120.00", app: "CommBank", in: store(), book: book(), at: now)
        #expect(string(r.event, "kind") == "bank")
        #expect(flag(r.event, "has_app") == true)
        #expect(string(r.event, "result") == "not_purchase")
        let wallet = try await run(title: "NAB Visa Debit", subtitle: "DoorDash", body: "A$23.40", app: "Wallet",
                                   in: store(), book: book(), at: now)
        #expect(string(wallet.event, "kind") == "notification")
        #expect(flag(wallet.event, "has_app") == true)
        #expect(flag(try await fullTap().event, "has_app") == false)
    }

    /// Shortcuts' own "App" is no app, the same as for `source`.
    @Test func thePlaceholderAppIsNoApp() async throws {
        let placeholder = try await run(title: "NAB Visa Debit", subtitle: "DoorDash", body: "A$23.40", app: "App",
                                        in: store(), book: book(), at: now)
        #expect(flag(placeholder.event, "has_app") == false)
        let bank = try await run(title: "NAB Visa Debit", subtitle: "DoorDash", body: "A$23.40", app: "CommBank",
                                 in: store(), book: book(), at: now)
        #expect(flag(bank.event, "has_app") == true)
        let record = LogWalletTapIntent.record(transaction: nil, amount: nil, merchant: nil, card: nil,
                                               notification: WalletNotification(body: "x", app: "App"), at: now)
        #expect(record.contains("app placeholder"))
    }

    @Test func aBankPurchaseIsABankRun() async throws {
        let r = try await run(title: "CommBank", body: "You spent $23.40 at DOORDASH with your card ending 4821.",
                              in: store(), book: book(), at: now)
        #expect(r.outcome.transaction != nil)
        #expect(string(r.event, "kind") == "bank")
        #expect(string(r.event, "result") == "saved")
    }

    @Test func moneyInIsMoneyIn() async throws {
        let r = try await moneyIn()
        #expect(r.outcome.dropped == .moneyIn)
        #expect(string(r.event, "kind") == "notification")
        #expect(string(r.event, "result") == "money_in")
    }

    // MARK: - Refunds and queued taps

    @Test func aRefundIsRefund() async throws {
        let r = try await refundAfterPurchase()
        #expect(r.outcome.refund)
        #expect(string(r.event, "result") == "refund")
    }

    /// Through the real path: a forced save failure on a notification
    /// payment, queued to this test's own file (`queueURL`), never the real
    /// queue file.
    @Test func aQueuedTapIsQueued() async throws {
        let r = try await queuedNotification()
        #expect(r.outcome.saveFailed)
        #expect(r.outcome.kept)
        #expect(string(r.event, "kind") == "notification")
        #expect(string(r.event, "result") == "queued")
    }

    // MARK: - Never words or money

    @Test func noWordsOrMoneyLeaveThePhone() async throws {
        for event in try await everyRun().map(\.event) {
            #expect(Set(event.keys) == eventKeys)
            #expect(Analytics.deniedKeys.isDisjoint(with: event.keys))
            for (key, value) in event {
                switch value {
                case .string(let s): #expect(allowedWords.contains(s), "\(key) = \(s) is not one of the allowed words")
                case .bool: break
                default: Issue.record("\(key) is neither a fixed word nor a bool")
                }
            }
        }
    }

    @Test func theEventIsNamedApplePayRun() {
        #expect(Analytics.Event.applePayRun.rawValue == "apple_pay_run")
    }
}

/// The Card row on a purchase (beta, build 9): the purchase's own card is
/// always one of the choices, so the picker never shows nothing.
@MainActor
struct TransactionDetailCardOptionsTests {
    private let mine = [Card(rawValue: "a"), Card(rawValue: "b")]

    @Test func aKnownCardIsNotAddedTwice() {
        #expect(TransactionDetailView.cardOptions(current: mine[1], mine: mine) == mine + [.other])
    }

    @Test func anArchivedOrUnknownCardIsStillOffered() {
        let gone = Card(rawValue: "archived-card")
        let options = TransactionDetailView.cardOptions(current: gone, mine: mine)
        #expect(options.first == gone)
        #expect(options.contains(.other))
        #expect(options.count == 4)
    }

    @Test func cardNotKnownIsOfferedOnce() {
        let options = TransactionDetailView.cardOptions(current: .other, mine: mine)
        #expect(options.filter { $0 == .other }.count == 1)
    }

    /// An empty `cardRaw` drew a blank row, and an id with no `CardInfo`
    /// drew the raw UUID. Both read as words now and stay offered.
    @Test func anEmptyOrUnknownCardReadsAsWords() {
        let empty = Card(rawValue: "")
        let unknown = Card(rawValue: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B")
        #expect(TransactionDetailView.cardLabel(empty, info: nil) == "Other")
        #expect(TransactionDetailView.cardLabel(unknown, info: nil) == "Unknown card")
        #expect(TransactionDetailView.cardOptions(current: empty, mine: mine).first == empty)
        #expect(TransactionDetailView.cardOptions(current: unknown, mine: mine).first == unknown)
        let info = CardInfo.legacy[0]
        #expect(TransactionDetailView.cardLabel(info.card, info: info) == info.card.name)
    }
}
