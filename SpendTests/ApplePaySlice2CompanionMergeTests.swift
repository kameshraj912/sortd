import Testing
import Foundation
import SwiftData
@testable import Spend

/// Part 3 (applepay-slice2, spec row 14): two triggers for one tap make one
/// row. Every test pins `now:` on both calls — never read the clock twice.
@MainActor
struct TapCompanionMergeTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "companion-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// (b) A zero-amount, no-merchant companion on the same card, 3 minutes
    /// after a real logged tap, is dropped — not logged as a second row.
    @Test func aBlankCompanionAt3MinutesMergesIntoTheRealTap() async throws {
        let ctx = store(), b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: now)
        let second = try await LogPurchaseIntent.handle(merchant: "", amount: "", card: "NAB Visa Debit",
                                                        in: ctx, book: b, now: now.addingTimeInterval(3 * 60))
        #expect(second.merged)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
        let saved = try #require(second.transaction)
        #expect(saved.merchant == "Seven Seeds")
        #expect(saved.amount == Decimal(string: "4.50"))
        #expect(!saved.needsCheck)
    }

    /// One arriving after 10 minutes is kept as its own row: the window
    /// only covers a genuinely close-together companion.
    @Test func aBlankCompanionAfter10MinutesStaysItsOwnRow() async throws {
        let ctx = store(), b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: now)
        let second = try await LogPurchaseIntent.handle(merchant: "", amount: "", card: "NAB Visa Debit",
                                                        in: ctx, book: b, now: now.addingTimeInterval(10 * 60))
        #expect(!second.merged)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    /// (c) A companion with a blank merchant but the right amount also
    /// merges — it only got the amount, not the shop.
    @Test func aBlankMerchantCompanionWithTheRightAmountMerges() async throws {
        let ctx = store(), b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: now)
        let second = try await LogPurchaseIntent.handle(merchant: "", amount: "A$4.50", card: "NAB Visa Debit",
                                                        in: ctx, book: b, now: now.addingTimeInterval(60))
        #expect(second.merged)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    /// A blank-first tap (the Notification trigger's companion lands
    /// first) followed by the full Transaction-trigger tap ends as one
    /// full row, the needs-a-check tag removed.
    @Test func aBlankFirstTapFollowedByAFullOneEndsAsOneFullRow() async throws {
        let ctx = store(), b = book()
        let first = try await LogPurchaseIntent.handle(merchant: "", amount: "", card: "NAB Visa Debit",
                                                       in: ctx, book: b, now: now)
        #expect(first.transaction?.needsCheck == true)
        let second = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit",
                                                        in: ctx, book: b, now: now.addingTimeInterval(45))
        #expect(second.merged)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
        let saved = try #require(second.transaction)
        #expect(saved.merchant == "Seven Seeds")
        #expect(saved.amount == Decimal(string: "4.50"))
        #expect(!saved.needsCheck)
        #expect(saved.note.isEmpty)
    }

    /// (a) Two full taps, same shop, amount and card, within 60 seconds:
    /// the same trigger firing twice — merge (confirm and keep).
    @Test func twoFullDuplicateTapsWithin60SecondsMerge() async throws {
        let ctx = store(), b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$5.50", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: now)
        let second = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$5.50", card: "NAB Visa Debit",
                                                        in: ctx, book: b, now: now.addingTimeInterval(45))
        #expect(second.merged)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    /// Two full taps with the same shop, amount and card more than 60
    /// seconds apart stay two rows — two coffees, not one duplicated.
    @Test func twoFullDuplicateTapsMoreThan60SecondsApartStayTwoRows() async throws {
        let ctx = store(), b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$5.50", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: now)
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$5.50", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: now.addingTimeInterval(90))
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    /// A different shop on the same card, close in time, is a real second
    /// purchase, not a companion — the blank-merchant rule only applies
    /// when the newcomer itself has nothing to disagree with.
    @Test func aDifferentRealShopNeverMergesAsACompanion() async throws {
        let ctx = store(), b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$5.50", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: now)
        let second = try await LogPurchaseIntent.handle(merchant: "Coles", amount: "A$30.00", card: "NAB Visa Debit",
                                                        in: ctx, book: b, now: now.addingTimeInterval(45))
        #expect(!second.merged)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    /// A companion on a *different* card never merges, however close in time.
    @Test func aDifferentCardNeverMerges() async throws {
        let ctx = store(), b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit",
                                               in: ctx, book: b, now: now)
        let second = try await LogPurchaseIntent.handle(merchant: "", amount: "", card: "CommBank Debit",
                                                        in: ctx, book: b, now: now.addingTimeInterval(30))
        #expect(!second.merged)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }
}
