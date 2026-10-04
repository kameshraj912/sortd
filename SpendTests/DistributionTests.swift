import Testing
import Foundation
@testable import Spend

/// "Rate on the App Store" must only show for a copy that came from the App
/// Store. In a TestFlight build the row did nothing (TestFlight 1.0 (2)).
struct DistributionTests {
    @Test func aStoreReceiptMeansTheAppStore() {
        #expect(Distribution.isAppStore(receiptName: "receipt"))
    }

    @Test(arguments: ["sandboxReceipt", nil, "", "Receipt"] as [String?])
    func anythingElseIsNotTheAppStore(name: String?) {
        #expect(!Distribution.isAppStore(receiptName: name))
    }

    @Test func theRateRowIsBehindTheCheck() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Spend/Views/Settings/AboutSettingsView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let lines = source.components(separatedBy: .newlines)
        let row = try #require(lines.firstIndex { $0.contains("Rate on the App Store") })
        #expect(lines[max(0, row - 3)..<row].contains { $0.contains("if Distribution.isAppStore") })
    }
}
