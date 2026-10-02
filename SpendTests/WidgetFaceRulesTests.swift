import Testing
import Foundation
@testable import Spend

/// Rules the widget extension has to keep, checked against its source text.
/// The extension is a separate target the app's tests cannot import, and
/// these are the things that drift quietly: a symbol that differs from the
/// app's, or a shop name that ends up on screen without the privacy rule.
struct WidgetFaceRulesTests {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The widget draws each category with the symbol the app uses, not its
    /// own near-miss ("cart" for the app's "cart.fill").
    @Test func widgetCategorySymbolsMatchTheApp() throws {
        let theme = try source("SortdWidget/SortdTheme.swift")
        let start = try #require(theme.range(of: "static func symbol(forCategory"))
        let end = try #require(theme.range(of: "// MARK:", range: start.upperBound..<theme.endIndex))
        let body = String(theme[start.upperBound..<end.lowerBound])

        let pattern = try NSRegularExpression(pattern: #"case "(\w+)":\s+"([^"]+)""#)
        let ns = body as NSString
        var found: [String: String] = [:]
        for m in pattern.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            found[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
        }
        for category in SpendCategory.allCases where category != .other {
            #expect(found[category.rawValue] == category.symbol, "\(category.rawValue)")
        }
        #expect(body.contains(#"default:              "\#(SpendCategory.other.symbol)""#))
    }

    /// Shop names are hidden while the iPhone is locked, whatever "Show
    /// Amounts When Locked" says. One view draws a shop name and it always
    /// applies `.privacySensitive()`; no other `Text` may show a merchant.
    @Test func everyShopNameIsDrawnByTheAlwaysPrivateView() throws {
        let widget = try source("SortdWidget/SortdWidget.swift")

        let helper = try #require(widget.range(of: "func shopNameIsPrivate()"))
        let helperLine = widget[helper.lowerBound...].prefix { $0 != "\n" }
        #expect(helperLine.contains("privacySensitive()"), "no argument: always on")

        let view = try #require(widget.range(of: "private struct ShopName"))
        let viewEnd = try #require(widget.range(of: "\n}\n", range: view.upperBound..<widget.endIndex))
        #expect(widget[view.upperBound..<viewEnd.lowerBound].contains(".shopNameIsPrivate()"))

        // Outside ShopName, no Text(...) is given a merchant.
        let outside = widget.replacingCharacters(in: view.lowerBound..<viewEnd.upperBound, with: "")
        let leak = try NSRegularExpression(pattern: #"Text\([^\n]*merchant"#)
        let hits = leak.numberOfMatches(in: outside, range: NSRange(location: 0, length: (outside as NSString).length))
        #expect(hits == 0, "a shop name is drawn without ShopName")
    }

    /// A Recent row's link is the one `Router` reads: `sortd://purchase/<id>`.
    @Test func theRecentRowLinkMatchesWhatTheRouterParses() throws {
        let theme = try source("SortdWidget/SortdTheme.swift")
        #expect(theme.contains(#"URL(string: "sortd://purchase/\(id.uuidString)")"#))
        let id = UUID()
        let target = Router.target(for: URL(string: "sortd://purchase/\(id.uuidString)")!)
        #expect(target?.name == "purchase")
        #expect(target?.id == id.uuidString)
    }
}
