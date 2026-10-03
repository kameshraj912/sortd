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

    // MARK: X5

    @Test func aRunLineSaysHowFieldsArrivedNotWhatTheySaid() {
        let line = LogWalletTapIntent.record(transaction: nil, amount: "A$12.34", merchant: "", card: "Merchant",
                                             notification: WalletNotification(), at: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(line.contains("amount 7 characters"))
        #expect(line.contains("merchant empty"))
        #expect(line.contains("card placeholder"))
        #expect(!line.contains("12.34"))
    }

    @Test func runLinesFromOlderBuildsAreClearedOnce() {
        let d = UserDefaults(suiteName: "hunt-fix-c-\(UUID().uuidString)")!
        d.set("amount “A$12.34” · merchant “ZEBRA”", forKey: LogPurchaseIntent.lastTapKey)
        d.set(["merchant “ZEBRA”"], forKey: LogPurchaseIntent.recentRunsKey)

        LogPurchaseIntent.scrubOldRunText(defaults: d)
        #expect(d.string(forKey: LogPurchaseIntent.lastTapKey) == nil)
        #expect(LogPurchaseIntent.recentRuns(d).isEmpty)

        // New lines written after the clean-up are kept.
        LogPurchaseIntent.recordReach("tap run · amount 7 characters", at: .now, defaults: d)
        LogPurchaseIntent.scrubOldRunText(defaults: d)
        #expect(LogPurchaseIntent.recentRuns(d).count == 1)
    }

    // MARK: D4

    /// The recovery screen's way out: the unopenable store's files are moved
    /// aside (kept) and an empty store opens in their place. The real store
    /// path is shared with the app, so this only checks the pure message.
    @Test func theRestoredMessageCountsPurchasesInPlainWords() {
        #expect(StoreRecovery.restoredMessage(1).hasPrefix("1 purchase is back."))
        #expect(StoreRecovery.restoredMessage(214).hasPrefix("214 purchases are back."))
        #expect(StoreRecovery.restoredMessage(0).contains("Close Sortd"))
    }
}
