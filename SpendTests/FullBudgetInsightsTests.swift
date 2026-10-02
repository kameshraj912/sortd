import Testing
import Foundation
@testable import Spend

/// "Top Shops" on the Insights tab: the purchase count must match the total,
/// so refunds and transfers are left out of both.
@MainActor
@Suite struct FullBudgetInsightsTests {
    private func spend(_ merchant: String, _ amount: Decimal, _ category: SpendCategory = .shopping,
                       refunded: Bool = false) -> Transaction {
        let t = Transaction(date: .now, merchant: merchant, amount: amount, currencyCode: Money.home,
                            card: .nab, category: category, source: .manual)
        t.refunded = refunded
        return t
    }

    @Test func refundedAndTransferRowsAreNotCountedAsPurchases() {
        let shops = InsightCarousel.topShops([
            spend("Kmart", 20), spend("Kmart", 30), spend("Kmart", 99, refunded: true),
            spend("Kmart", 500, .transfers),
        ])
        #expect(shops.count == 1)
        #expect(shops.first?.count == 2)
        #expect(shops.first?.total == 50)
    }

    @Test func aShopWithOnlyARefundOrTransferIsNotListed() {
        let shops = InsightCarousel.topShops([
            spend("Kmart", 20), spend("Returned Co", 40, refunded: true), spend("My Savings", 100, .transfers),
        ])
        #expect(shops.map(\.name) == ["Kmart"])
    }
}
