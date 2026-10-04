import Testing
import SwiftData
import Foundation
@testable import Spend

/// 4 Oct 2026, phone run: restore a backup from the first screen, finish
/// setup, and Home asked for a monthly budget again. Setup had noted the
/// budget (nothing) when it opened and put that back when it ended.
@MainActor
struct RestoreBudgetThroughSetupTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "restore-budget-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func backupWithBudget() throws -> Data {
        var snap = Backup.Snapshot()
        snap.settings["monthlyBudget"] = .double(2000)
        snap.settings[Money.homeKey] = .string("AUD")
        return try Backup.encode(snap)
    }

    @Test func restoreFromTheFirstScreenKeepsTheBudgetThroughSetup() throws {
        let defaults = scratch()
        var memory = SetupBudgetMemory()
        // The first screen opens: no budget yet.
        memory.begin(current: defaults.double(forKey: "monthlyBudget"))

        // Bring in past spending > Replace Everything.
        try Backup.restore(try backupWithBudget(), mode: .replace, into: try store(),
                           defaults: defaults, cardBook: CardBook(defaults: scratch()))
        let restored = defaults.double(forKey: "monthlyBudget")
        #expect(restored == 2000)
        memory.adopt(current: restored)

        // Setup ends with "Spend less" never ticked.
        #expect(memory.final(current: restored, spendLess: false) == 2000)
    }

    @Test func withoutAdoptingTheOldStartPointWouldWipeIt() throws {
        // What the phone run showed: the start point is nothing, so un-ticked
        // "Spend less" put nothing back. This is why the sheet adopts the budget.
        var memory = SetupBudgetMemory()
        memory.begin(current: 0)
        #expect(memory.final(current: 2000, spendLess: false) == 0)
    }

    @Test func unTickingSpendLessStillUndoesALimitSetInSetup() {
        var memory = SetupBudgetMemory()
        memory.begin(current: 0)
        #expect(memory.final(current: 500, spendLess: false) == 0)
        #expect(memory.final(current: 500, spendLess: true) == 500)
    }

    @Test func aLimitSetWeeksAgoSurvivesUnTickingSpendLess() {
        var memory = SetupBudgetMemory()
        memory.begin(current: 1200)
        memory.begin(current: 99)   // setup appearing again does not move the start
        #expect(memory.final(current: 300, spendLess: false) == 1200)
    }
}
