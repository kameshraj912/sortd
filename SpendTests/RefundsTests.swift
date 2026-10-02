import Testing
import Foundation
import SwiftData
@testable import Spend

/// `Refunds`: a refund finds the purchase it cancels (Apple Pay refund taps).
@MainActor
struct RefundsTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func buy(_ merchant: String, _ amount: Decimal, card: Card = .other, at date: Date) throws {
        try TransactionLogger.log(IncomingPurchase(date: date, merchant: merchant, amount: amount, currency: "AUD",
                                                   card: card, source: .tap), in: context)
    }

    private var all: [Transaction] { (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] }

    @Test func refundCancelsItsPurchase() throws {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        try buy("Nourish'd", 230.05, at: when)
        let found = Refunds.markRefunded(amount: 230.05, currency: "AUD", card: .other, merchant: "Nourish'd",
                                         platform: nil, before: when.addingTimeInterval(900), in: context)
        #expect(found)
        let t = try #require(all.first)
        #expect(t.refunded)
        #expect(t.audValue == 0)
    }

    @Test func aRefundWithNoMatchingPurchaseChangesNothing() throws {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        try buy("Woolworths", 40, at: when)
        let found = Refunds.markRefunded(amount: 17.53, currency: "AUD", card: .other, merchant: "Woolworths",
                                         platform: nil, before: when.addingTimeInterval(900), in: context)
        #expect(!found)
        #expect(all.first?.refunded == false)
    }

    @Test func aPartRefundReducesTheBiggerPurchase() throws {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        try buy("Kmart", 59.90, at: when)
        let reduced = Refunds.markPartiallyRefunded(amount: 20, currency: "AUD", card: .other, merchant: "Kmart",
                                                    platform: nil, before: when.addingTimeInterval(900), in: context)
        #expect(reduced?.amount == Decimal(string: "39.90"))
        #expect(reduced?.note.contains("refunded") == true)
    }
}
