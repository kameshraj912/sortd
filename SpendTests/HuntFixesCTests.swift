import Testing
import Foundation
import SwiftData
@testable import Spend

// Tests added with the 3 Oct 2026 hunt fixes in the data, backup and privacy
// areas (docs/BugHunt-2026-10-03-fixes-c.md).

@MainActor
struct HuntFixesCTests {
    private struct DiskFull: Error {}

    private func context() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    // MARK: D2

    /// A save that throws must not leave the new row pending, or the person's
    /// "Please try again" saves the purchase twice (hand-typed rows never merge).
    @Test func aFailedSaveLeavesNoRowSoARetryDoesNotSaveTwice() throws {
        let ctx = try context()
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000), merchant: "Coffee", amount: 5,
                                 currency: "AUD", card: .other, source: .manual)

        #expect(throws: DiskFull.self) {
            try TransactionLogger.log(p, in: ctx, commit: { _ in throw DiskFull() })
        }
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 0, "the failed save left its row in the context")

        try TransactionLogger.log(p, in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }
}
