import Testing
import Foundation
import SwiftData
@testable import Spend

/// Before/after timing of a 300-line statement import. Off by default, so CI
/// skips it: it prints timings rather than checking anything.
/// `TEST_RUNNER_SPEND_BENCH=1 scripts/test.sh --only StatementSpeedBenchmark`
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SPEND_BENCH"] == "1"))
struct StatementSpeedBenchmark {

    static let emails = 300

    private func freshContext() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        // On disk, like the phone: each save is a real SQLite write.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).store")
        return ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]))
    }

    private func report(_ label: String, _ values: [(String, Double)]) {
        let text = values.map { "\($0.0)=\(String(format: "%.0f", $0.1))ms" }.joined(separator: " ")
        print("BENCH \(label) n=\(Self.emails) \(text)")
    }

    /// A 300-line bank statement.
    @Test func statementImport() throws {
        let rows = (0..<Self.emails).map { i in
            StatementImport.Row(date: Date.now.addingTimeInterval(-Double(i) * 7200), detail: "SHOP \(i)",
                                amount: Decimal(10 + i), currency: "AUD", kind: .spend, raw: "")
        }
        // Before: one save per row.
        let a = try freshContext()
        var t = ContinuousClock.now
        var touched: Set<UUID> = []
        for row in rows {
            let p = IncomingPurchase(date: row.date, merchant: row.detail, amount: row.amount,
                                     currency: "AUD", card: .other, source: .csv)
            if let o = try? TransactionLogger.log(p, in: a, excluding: touched) { touched.insert(o.transaction.id) }
        }
        let before = Perf.ms(since: t)
        let c = try freshContext()
        t = ContinuousClock.now
        _ = StatementImport.save(rows, card: .other, in: c)
        report("statement", [("before", before), ("after", Perf.ms(since: t))])
    }
}
