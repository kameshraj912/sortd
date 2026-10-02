import Testing
import SwiftData
import Foundation
@testable import Spend

/// Fields that are meant to travel with every purchase in a backup, logged
/// through `TransactionLogger.log` (never inserted directly) so a field only
/// visible when the real logger sets it isn't mistaken for a bug.
@MainActor
struct FullDataRoundTripTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "fulldata-roundtrip-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func book() -> CardBook { CardBook(defaults: scratch()) }

    /// A receipt or bank alert whose last-4 matched none of Raj's active
    /// cards leaves `unmatchedLast4` set so "Which card?" (Home) can find it
    /// once he answers. `Backup.Snapshot.Row` had no field for it at all, so
    /// every backup silently dropped it: after a restore the
    /// purchase looks like any other unassigned-card row and "Which card?"
    /// can never find it to fix in bulk.
    @Test func unmatchedCardDigitsSurviveABackupRoundTrip() throws {
        let from = try store()
        // Nothing sets these digits any more (Gmail and "Which card?" were
        // removed on 2 Oct 2026), but rows saved before that still carry them
        // and a backup must not drop them. So the field is set on the row.
        let p = IncomingPurchase(date: Date(timeIntervalSince1970: 1_790_000_000),
                                 merchant: "Woolworths", amount: 58.30, currency: "AUD",
                                 card: .other, source: .email)
        _ = try TransactionLogger.log(p, in: from)
        let before = try from.fetch(FetchDescriptor<Transaction>())
        before.first?.unmatchedLast4 = "4821"
        try from.save()

        let data = try Backup.data(in: from, defaults: scratch())
        let to = try store()
        let result = try Backup.restore(data, mode: .merge, into: to, defaults: scratch(), cardBook: book())
        #expect(result.added == 1)

        let restored = try to.fetch(FetchDescriptor<Transaction>())
        #expect(restored.first?.unmatchedLast4 == "4821")
    }

    /// A backup written before `unmatchedLast4` was in the file: the row has
    /// no such key and still restores, with no digits.
    @Test func aBackupFromBeforeUnmatchedDigitsStillRestores() throws {
        let old = """
        {"format":"sortd.backup","version":1,"createdAt":"2026-09-01T00:00:00Z",
         "cards":[],"settings":{},"rules":[],
         "transactions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
           "date":"2026-09-01T02:00:00Z","merchant":"Woolworths","rawMerchant":"WOOLWORTHS",
           "amount":58.3,"currencyCode":"AUD","homeAmount":58.3,"card":"other",
           "category":"groceries","source":"manual","seenIn":"","note":"",
           "createdAt":"2026-09-01T02:00:00Z","refunded":false}]}
        """
        let to = try store()
        let result = try Backup.restore(Data(old.utf8), mode: .merge, into: to,
                                        defaults: scratch(), cardBook: book())
        #expect(result.added == 1)
        let restored = try to.fetch(FetchDescriptor<Transaction>())
        #expect(restored.first?.merchant == "Woolworths")
        #expect(restored.first?.unmatchedLast4 == nil)
    }
}
