import Testing
import SwiftData
import Foundation
@testable import Sortd

/// Bug hunt D5: the versioned schema and migration plan must open a store
/// made by the builds before them, with every purchase still there.
@MainActor
struct MigrationTests {

    @Test func aStoreFromBeforeTheMigrationPlanStillOpens() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Made the old way: a plain schema, no versions, no plan.
        do {
            let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(old)
            context.insert(Transaction(date: .now, merchant: "Woolworths", amount: 58.30, currencyCode: "AUD",
                                       card: .nab, category: .groceries, source: .manual))
            context.insert(MerchantRule(key: "woolworths", category: .groceries))
            try context.save()
        }

        // Opened the way the app now opens it.
        let schema = Schema(versionedSchema: SchemaV1.self)
        let new = try ModelContainer(for: schema, migrationPlan: SortdMigrationPlan.self,
                                     configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(new)
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        #expect(rows.count == 1)
        #expect(rows.first?.merchant == "Woolworths")
        #expect(try context.fetch(FetchDescriptor<MerchantRule>()).count == 1)
    }
}
