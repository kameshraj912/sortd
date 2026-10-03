import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt 3 Oct 2026, fixed on `fix-hunt-a`: Backup and CSV export (D5, D6).
/// Each test failed before its fix. Helpers: `HuntA`.
@MainActor
struct BugHuntFixesAExportTests {

    private func store() throws -> ModelContext { try HuntA.store() }
    private func date(_ ymd: String, _ hm: String = "12:00") -> Date { HuntA.date(ymd, hm) }
    private func money(_ s: String) -> Decimal { HuntA.money(s) }
    private func calendar(_ id: Calendar.Identifier, _ zone: TimeZone = .current) -> Calendar { HuntA.calendar(id, zone) }
    private func ymd(_ d: Date?) -> String? { HuntA.ymd(d) }

    // MARK: D5. Export file names use the local date

    @Test func anExportIsNamedWithTheLocalDate() {
        let melbourne = TimeZone(identifier: "Australia/Melbourne")!
        let eightAM = Date(timeIntervalSince1970: 1_790_978_400)   // 3 Oct 2026 08:00 in Melbourne
        #expect(Exports.dated("Sortd backup", "sortdbackup", now: eightAM, timeZone: melbourne)
                == "Sortd backup 2026-10-03.sortdbackup")
        #expect(Exports.dated("Sortd purchases", "csv", now: eightAM, timeZone: TimeZone(identifier: "UTC")!)
                == "Sortd purchases 2026-10-02.csv")
    }

    // MARK: D6. The CSV holds real purchases only

    @Test func theCSVLeavesOutCheckRowsAndSamplePurchases() throws {
        let rows = [
            Transaction(date: date("2026-09-21"), merchant: "Seven Seeds", amount: money("5.50"), currencyCode: "AUD",
                        card: .nab, category: .eatingOut, source: .tap),
            Transaction(date: date("2026-09-21"), merchant: ApplePayHealthCheck.merchant, amount: money("0.01"),
                        currencyCode: "AUD", card: .other, category: .other, source: .tap),
            Transaction(date: date("2026-09-21"), merchant: LogPurchaseIntent.legacyTestMerchant, amount: money("0.01"),
                        currencyCode: "AUD", card: .other, category: .other, source: .tap),
            Transaction(date: date("2026-09-21"), merchant: "Woolworths", amount: money("58.30"), currencyCode: "AUD",
                        card: .nab, category: .groceries, source: .manual, note: DemoData.marker),
        ]
        let csv = String(decoding: CSVExport.data(rows), as: UTF8.self)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2, "\(csv)")
        #expect(csv.contains("Seven Seeds"))
        #expect(!csv.contains(ApplePayHealthCheck.merchant))
        #expect(!csv.contains(LogPurchaseIntent.legacyTestMerchant))
        #expect(!csv.contains("Woolworths"))
    }
}
