import Testing
import Foundation

/// The budget preset chips (setup, the budget sheet, a category limit) must
/// draw their amounts with `Money.format`, the formatter every row uses, so a
/// Singapore-dollar budget reads the same on a chip as it does on Home: plain
/// "$" while SGD is the home currency, "S$" when it is not. A hand-built
/// "$\(amount)" on a chip is what this guards against.
/// Source scan, like `FeedbackCoverageTests`, so it never touches the global
/// home currency.

struct BudgetChipFormatTests {
    private static var views: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Spend/Views")
    }

    private static func lines(_ file: String) throws -> [String] {
        try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8)
            .components(separatedBy: .newlines)
    }

    @Test(arguments: ["BudgetSheet.swift", "CategoryLimitSheet.swift", "OnboardingView.swift"])
    func presetChipsUseMoneyFormat(file: String) throws {
        let all = try Self.lines(file)
        let chipLines = all.enumerated().filter { $0.element.contains(".chip(selected:") }
        #expect(!chipLines.isEmpty, "\(file) has no chip to check")
        for (i, _) in chipLines {
            // The text a chip wraps sits in the three lines above `.chip`.
            let window = all[max(0, i - 3)...i].joined(separator: "\n")
            if window.contains("preset") || window.contains("value") {
                #expect(window.contains("Money.format("), "\(file):\(i + 1) chip does not use Money.format")
                #expect(!window.contains("\"$"), "\(file):\(i + 1) chip builds its own dollar sign")
            }
        }
    }
}
