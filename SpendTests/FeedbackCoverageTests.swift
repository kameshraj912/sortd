import Testing
import Foundation

/// Source-scan guard rails for spec 5 (one haptic map). These read the
/// checked-out sources under `Spend/`, not the compiled app, so they catch
/// drift the moment someone adds a raw `.sensoryFeedback(` call or puts
/// haptics on a scroll gesture.
@Suite("FeedbackCoverage")
struct FeedbackCoverageTests {

    /// `#filePath` for this file, walked up to the repo root, then into
    /// `Spend/`. Keeps the scan working from any worktree.
    private static var spendDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SpendTests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Spend")
    }

    private static func swiftFiles() throws -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: spendDir, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in e where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    /// Every `sensoryFeedback` call must live inside
    /// `Spend/Views/Components/Feedback.swift`, behind the `.feedback(_:trigger:)`
    /// modifier the spec asks for. Fails now: 20 call sites in 14 other files
    /// still call `.sensoryFeedback(` directly (spec 5, "Files").
    @Test func noRawSensoryFeedbackOutsideFeedbackFile() throws {
        let feedbackFile = "Views/Components/Feedback.swift"
        var offenders: [String] = []
        for file in try Self.swiftFiles() {
            let path = file.path
            guard !path.hasSuffix(feedbackFile) else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (i, line) in text.components(separatedBy: .newlines).enumerated() where line.contains(".sensoryFeedback(") {
                offenders.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        #expect(offenders.isEmpty, "raw .sensoryFeedback( outside Feedback.swift: \(offenders.joined(separator: ", "))")
    }

    /// Haptics never fire on scroll: no line mentioning `Feedback` or
    /// `sensoryFeedback` may also mention `onScrollGeometryChange`,
    /// `ScrollView` or `scrollPosition` on the same line.
    @Test func noFeedbackOnScrollLines() throws {
        let scrollMarkers = ["onScrollGeometryChange", "ScrollView", "scrollPosition"]
        var offenders: [String] = []
        for file in try Self.swiftFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (i, line) in text.components(separatedBy: .newlines).enumerated() {
                let mentionsFeedback = line.contains("Feedback") || line.contains("sensoryFeedback")
                let mentionsScroll = scrollMarkers.contains { line.contains($0) }
                if mentionsFeedback && mentionsScroll {
                    offenders.append("\(file.lastPathComponent):\(i + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty, "feedback mentioned on a scroll line: \(offenders.joined(separator: ", "))")
    }
}
