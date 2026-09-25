import Testing
import Foundation
@testable import Spend

/// Every `Analytics.Event` case must be called somewhere under `Spend/` — not just
/// declared in `Analytics.swift`. A named event nobody sends is dead weight and a
/// silent gap in the funnels the analytics spec exists to fill.
///
/// This is a source-tree scan from `#filePath`, not a mock: it reads every `.swift`
/// file under `Spend/` (excluding `Analytics.swift` itself, where the cases are
/// declared) and checks each event's Swift case identifier (e.g. `setupStarted`)
/// appears as `.setupStarted` somewhere in that text.
///
/// Every event is wired (sub-spec 2). This stays so a new `Event` case cannot
/// be added without a real call site.
struct AnalyticsEventCoverageTests {
    private static var spendRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SpendTests/
            .deletingLastPathComponent() // worktree root
            .appendingPathComponent("Spend")
    }

    private static func swiftFiles(under url: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Analytics.swift" }
    }

    @Test func everyAnalyticsEventIsReferencedOutsideTheFacade() throws {
        let root = Self.spendRoot
        #expect(FileManager.default.fileExists(atPath: root.path), "expected Spend/ at \(root.path)")

        var combined = ""
        for file in Self.swiftFiles(under: root) {
            combined += (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }

        var missing: [String] = []
        for event in Analytics.Event.allCases {
            let caseIdentifier = String(describing: event)
            if !combined.contains(".\(caseIdentifier)") {
                missing.append(event.rawValue)
            }
        }
        #expect(missing.isEmpty, "Events never called under Spend/ (outside Analytics.swift): \(missing.joined(separator: ", "))")
    }
}
