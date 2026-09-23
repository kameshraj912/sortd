import Testing
import Foundation
import SwiftData
@testable import Sortd

@MainActor
struct EmailSyncTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    func record(_ id: String, kind: String = "purchase", merchant: String, raw: String? = nil, platform: String? = nil,
                amount: String, currency: String = "AUD", card: String = "other", date: String, note: String? = nil) -> EmailRecord {
        EmailRecord(id: id, kind: kind, merchant: merchant, rawMerchant: raw ?? merchant, platform: platform,
                    amount: amount, currency: currency, card: card, date: date, note: note, subscription: nil)
    }

    var all: [Transaction] { (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] }

    @Test func bankAlertAndDoorDashEmailBecomeOnePurchase() throws {
        let alert = record("sc-1", merchant: "DoorDash", raw: "DD *DOORDASH CHENNAIBI", platform: "doordash",
                           amount: "31.05", card: "scDebit", date: "2026-09-13T04:07:00.000Z")
        let order = record("dd-1", merchant: "Chennai Biryani House", raw: "DoorDash: Chennai Biryani House", platform: "doordash",
                           amount: "31.05", date: "2026-09-13T04:06:10.000Z", note: "DoorDash · paid with Apple Pay")
        let s = try EmailSync.importRecords([alert, order], in: context)

        #expect(s.added == 1 && s.merged == 1)
        let t = try #require(all.first)
        #expect(all.count == 1)
        #expect(t.merchant == "Chennai Biryani House")   // restaurant beats bare "DoorDash"
        #expect(t.card == .scDebit)                       // card from the bank alert
        #expect(t.category == .foodDelivery)
    }

    @Test func groceriesViaDoorDashStayGroceries() throws {
        try EmailSync.importRecords([record("dd-2", merchant: "Costco", raw: "DoorDash: Costco", platform: "doordash",
                                            amount: "127.22", date: "2026-09-11T02:00:00.000Z")], in: context)
        #expect(all.first?.category == .groceries)
    }

    @Test func sameRecordIsNeverImportedTwice() throws {
        let r = record("st-1", merchant: "Campus Rooms", amount: "68.30", card: "nab", date: "2026-09-14T04:30:26.000Z")
        try EmailSync.importRecords([r], in: context)
        let again = try EmailSync.importRecords([r], in: context)
        #expect(again.added == 0 && all.count == 1)
    }

    @Test func refundCancelsItsPurchase() throws {
        let buy = record("st-2", merchant: "Nourish'd", amount: "230.05", card: "stanchart", date: "2026-09-09T02:18:05.000Z")
        let back = record("st-3", kind: "refund", merchant: "Nourish'd", amount: "230.05", card: "stanchart", date: "2026-09-09T02:32:59.000Z")
        let s = try EmailSync.importRecords([back, buy], in: context)   // order doesn't matter
        #expect(s.refunds == 1)
        let t = try #require(all.first)
        #expect(t.refunded)
        #expect(t.audValue == 0)
    }

    @Test func unmatchedRefundIsRetriedLater() throws {
        let back = record("sc-9", kind: "refund", merchant: "DoorDash", raw: "DD *DOORDASH COSTCO", platform: "doordash",
                          amount: "17.53", card: "scDebit", date: "2026-09-11T03:49:00.000Z")
        #expect(try EmailSync.importRecords([back], in: context).refunds == 0)
        let buy = record("sc-8", merchant: "DoorDash", raw: "DD *DOORDASH COSTCO", platform: "doordash",
                         amount: "17.53", card: "scDebit", date: "2026-09-11T03:40:00.000Z")
        #expect(try EmailSync.importRecords([buy, back], in: context).refunds == 1)
    }

    @Test func differentDeliveryOrdersStaySeparate() throws {
        try EmailSync.importRecords([
            record("a", merchant: "Nando's", platform: "doordash", amount: "24.00", date: "2026-09-13T09:00:00.000Z"),
            record("b", merchant: "El Jannah", platform: "doordash", amount: "31.50", date: "2026-09-13T12:00:00.000Z"),
        ], in: context)
        #expect(all.count == 2)
    }
}
