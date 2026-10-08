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
                     title: String? = nil, subtitle: String? = nil, body: String? = nil,
                     in ctx: ModelContext, book b: CardBook, at date: Date,
                     forceSaveFailure: Bool = false, queueURL: URL? = nil) async throws -> Run {
        let outcome = try await LogWalletTapIntent.handle(text, amount: amount, merchant: merchant, card: card,
                                                          notificationTitle: title, notificationSubtitle: subtitle,
                                                          notificationBody: body, in: ctx, book: b, now: date,
                                                          debugForceSaveFailure: forceSaveFailure, queueURL: queueURL)
        let event = LogWalletTapIntent.runEvent(outcome: outcome, transaction: text, amount: amount, merchant: merchant,
                                                card: card,
                                                notification: WalletNotification(title: title, subtitle: subtitle, body: body))
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

    private let allowedWords: Set<String> = ["tap", "notification", "saved", "merged", "needs_check", "blank",
                                             "no_amount", "not_completed", "money_in", "refund", "health_check",
                                             "queued", "not_saved", "not_purchase", "bank"]
    private let nineKeys: Set<String> = ["kind", "result", "has_amount", "has_shop", "has_card",
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

    @Test func aBlankRunIsBlank() async throws {
        let r = try await blankRun()
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "blank")
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
            #expect(Set(event.keys) == nineKeys)
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
