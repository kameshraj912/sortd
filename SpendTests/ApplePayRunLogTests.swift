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

    /// One run through the real intent path, and the event it would log.
    private func run(amount: String? = nil, merchant: String? = nil, card: String? = nil,
                     title: String? = nil, subtitle: String? = nil, body: String? = nil,
                     in ctx: ModelContext, book b: CardBook, at date: Date)
        async throws -> (outcome: LogPurchaseIntent.Outcome, event: Event) {
        let outcome = try await LogWalletTapIntent.handle(nil, amount: amount, merchant: merchant, card: card,
                                                          notificationTitle: title, notificationSubtitle: subtitle,
                                                          notificationBody: body, in: ctx, book: b, now: date)
        let event = LogWalletTapIntent.runEvent(outcome: outcome, transaction: nil, amount: amount, merchant: merchant,
                                                card: card,
                                                notification: WalletNotification(title: title, subtitle: subtitle, body: body))
        return (outcome, event)
    }

    private let allowedWords: Set<String> = ["tap", "notification", "saved", "merged", "needs_check", "blank",
                                             "no_amount", "not_completed", "money_in", "refund", "queued"]
    private let eightKeys: Set<String> = ["kind", "result", "has_amount", "has_shop", "has_card",
                                          "has_title", "has_subtitle", "has_body"]

    // MARK: - What kind of run, and what came of it

    @Test func aFullTapIsSaved() async throws {
        let r = try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                              in: store(), book: book(), at: now)
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "saved")
        #expect(flag(r.event, "has_amount") == true)
        #expect(flag(r.event, "has_shop") == true)
        #expect(flag(r.event, "has_card") == true)
        #expect(flag(r.event, "has_title") == false)
        #expect(flag(r.event, "has_subtitle") == false)
        #expect(flag(r.event, "has_body") == false)
    }

    @Test func theSameTapAgainIsMerged() async throws {
        let ctx = store(), b = book()
        _ = try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit", in: ctx, book: b, at: now)
        let second = try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                   in: ctx, book: b, at: now.addingTimeInterval(30))
        #expect(second.outcome.merged)
        #expect(string(second.event, "result") == "merged")
    }

    @Test func aCardOnlyTapNeedsACheck() async throws {
        let r = try await run(card: "NAB Visa Debit", in: store(), book: book(), at: now)
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "needs_check")
        #expect(flag(r.event, "has_amount") == false)
        #expect(flag(r.event, "has_shop") == false)
        #expect(flag(r.event, "has_card") == true)
    }

    @Test func aBlankRunIsBlank() async throws {
        let r = try await run(in: store(), book: book(), at: now)
        #expect(string(r.event, "kind") == "tap")
        #expect(string(r.event, "result") == "blank")
        for key in ["has_amount", "has_shop", "has_card", "has_title", "has_subtitle", "has_body"] {
            #expect(flag(r.event, key) == false, "\(key) should be false")
        }
    }

    // MARK: - Runs that were dropped

    @Test func aDeclinedNotificationIsNotCompleted() async throws {
        let r = try await run(title: "Payment declined", body: "A$23.40 at DoorDash", in: store(), book: book(), at: now)
        #expect(r.outcome.dropped == .notCompleted)
        #expect(string(r.event, "kind") == "notification")
        #expect(string(r.event, "result") == "not_completed")
        #expect(flag(r.event, "has_title") == true)
        #expect(flag(r.event, "has_body") == true)
        #expect(flag(r.event, "has_subtitle") == false)
    }

    @Test func aNotificationWithNoAmountIsNoAmount() async throws {
        let r = try await run(title: "Uber Eats", body: "Your order is on its way", in: store(), book: book(), at: now)
        #expect(r.outcome.dropped == .noAmount)
        #expect(string(r.event, "kind") == "notification")
        #expect(string(r.event, "result") == "no_amount")
    }

    @Test func moneyInIsMoneyIn() async throws {
        let r = try await run(title: "Wallet", body: "You received $25.00 from J Tan", in: store(), book: book(), at: now)
        #expect(r.outcome.dropped == .moneyIn)
        #expect(string(r.event, "kind") == "notification")
        #expect(string(r.event, "result") == "money_in")
    }

    // MARK: - Refunds and queued taps

    @Test func aRefundIsRefund() async throws {
        let ctx = store(), b = book()
        _ = try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit", in: ctx, book: b, at: now)
        let r = try await run(amount: "-A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                              in: ctx, book: b, at: now.addingTimeInterval(60))
        #expect(r.outcome.refund)
        #expect(string(r.event, "result") == "refund")
    }

    /// Built by hand, not through `handle`: a forced save failure queues to
    /// the real tap-queue file, which other suites share.
    @Test func aQueuedTapIsQueued() {
        let outcome = LogPurchaseIntent.Outcome(message: "x", transaction: nil, merged: false, saveFailed: true)
        let event = LogWalletTapIntent.runEvent(outcome: outcome, transaction: nil, amount: nil, merchant: nil, card: nil,
                                                notification: WalletNotification())
        #expect(string(event, "result") == "queued")
    }

    // MARK: - Never words or money

    @Test func noWordsOrMoneyLeaveThePhone() async throws {
        let saved = try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                  in: store(), book: book(), at: now)
        let declined = try await run(title: "Payment declined", body: "A$23.40 at DoorDash",
                                     in: store(), book: book(), at: now)
        let ctx = store(), b = book()
        _ = try await run(amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit", in: ctx, book: b, at: now)
        let refund = try await run(amount: "-A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                   in: ctx, book: b, at: now.addingTimeInterval(60))

        for event in [saved.event, declined.event, refund.event] {
            #expect(Set(event.keys) == eightKeys)
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
