import Testing
import Foundation
import SwiftData
@testable import Spend

/// Changing one purchase's category no longer moves the whole shop unless
/// Raj says "All".
@MainActor
struct RecategoriseChoiceTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func log(_ merchant: String, _ amount: Decimal, minutes: Double,
                     platform: String? = nil) throws -> Transaction {
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60), merchant: merchant,
                                 amount: amount, currency: "AUD", card: .other, source: .email, platform: platform)
        return try TransactionLogger.log(p, in: context).transaction
    }

    @Test func justThisOneChangesOnlyThatPurchaseAndLearnsNothing() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        let b = try log("Spotify", 12.99, minutes: 60 * 24 * 30)
        let before = b.category

        try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: false)

        #expect(a.category == .groceries)
        #expect(b.category == before)
        #expect(try TransactionLogger.learnedRules(in: context)["spotify"] == nil)
    }

    @Test func allMovesTheShopAndLearns() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        let b = try log("Spotify", 12.99, minutes: 60 * 24 * 30)

        try TransactionLogger.recategorise(a, to: .groceries, in: context, applyToOthers: true)

        #expect(b.category == .groceries)
        #expect(try TransactionLogger.learnedRules(in: context)["spotify"] == .groceries)
    }

    @Test func samePlaceCountsOtherPurchasesFromTheShop() throws {
        let a = try log("Spotify", 12.99, minutes: 0)
        _ = try log("Spotify", 12.99, minutes: 60 * 24 * 30)
        _ = try log("Spotify", 12.99, minutes: 60 * 24 * 60)
        _ = try log("Woolworths", 40, minutes: 5)
        #expect(try TransactionLogger.samePlace(as: a, in: context).count == 2)
    }

    @Test func aBareDoorDashOrderIsNotTheSamePlaceAsOtherDoorDashOrders() throws {
        let biryani = try log("DoorDash", 31.05, minutes: 0, platform: "doordash")
        _ = try log("Chennai Biryani House", 31.05, minutes: 4, platform: "doordash")
        _ = try log("DoorDash", 20, minutes: 600, platform: "doordash")
        #expect(try TransactionLogger.samePlace(as: biryani, in: context).isEmpty)
    }
}

/// Search forgives apostrophes, case and accents.
struct SearchTextTests {
    @Test func foldsPunctuationCaseAndAccents() {
        #expect(SearchText.fold("McDonald's") == "mcdonalds")
        #expect(SearchText.fold("mcdonalds") == "mcdonalds")
        #expect(SearchText.fold("Café Nero") == "cafenero")
        #expect(SearchText.fold("7-Eleven") == "7eleven")
        #expect(SearchText.fold("7 eleven") == "7eleven")
        #expect(SearchText.fold("  ") == "")
    }
}

/// The Add screen's amount field ignores keys past the limit.
@MainActor
struct AmountKeypadTests {
    @Test func acceptsNormalAmounts() {
        for ok in ["", "5", "5.", "5.5", "5.50", "4,50", "999999", "999999.99", "0.5"] {
            #expect(AddTransactionView.isTypeable(ok), "\(ok)")
        }
    }

    @Test func refusesTooLongOrTooPrecise() {
        for bad in ["1000000", "12345678901", "5.555", "5.5.5", "1,234.50", "abc", "-5"] {
            #expect(!AddTransactionView.isTypeable(bad), "\(bad)")
        }
    }
}
