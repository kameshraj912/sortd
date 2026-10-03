#if DEBUG
import SwiftUI
import UIKit

/// Drives Activity's search the way a finger would, for simulator checks
/// with no way to tap (DEBUG only). Launch with SPEND_SEARCH_DRIVE=<query>
/// and SPEND_SEARCH_LOG=<file>: it opens search from the bar button, types
/// the query, presses the field's close button, then leaves the tab and
/// comes back, writing what it saw at each step to the log ("OPEN",
/// "CLOSED", "BACK" mark the moments to take a screenshot).
@MainActor
enum DebugSearchDriver {
    private static var started = false
    private static var lines: [String] = []
    private static var logPath: String?

    /// One line in the drive's log (also from the views it is driving).
    static func note(_ s: String) {
        guard let logPath else { return }
        lines.append(s)
        try? lines.joined(separator: "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
    }

    /// Once per launch: Activity's search calls this each time it appears.
    static func runIfAsked() {
        let env = ProcessInfo.processInfo.environment
        guard !started, let query = env["SPEND_SEARCH_DRIVE"] else { return }
        started = true
        let logPath = env["SPEND_SEARCH_LOG"]
        Task { await run(query: query, logPath: logPath) }
    }

    private static func run(query: String, logPath: String?) async {
        Self.logPath = logPath
        func log(_ s: String) { note(s) }
        log("start")
        try? await Task.sleep(for: .seconds(5))
        guard let window = keyWindow() else { log("no window"); return }

        // 1. The bar's search button: the trailing bar button, beside the
        // gear. (Accessibility labels are empty while no assistive tech
        // runs, so it is found by place, not by name.)
        let barButtons = controls(in: window) {
            String(describing: type(of: $0)) == "_UIButtonBarButton" && $0.convert($0.bounds, to: nil).minY < 130
        }
        log("bar buttons: " + barButtons.map(describe).joined(separator: " | "))
        guard let button = barButtons.max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }) else {
            log("no bar button"); return
        }
        press(button)
        try? await Task.sleep(for: .seconds(1.5))

        // 2. Type into the field that opened.
        guard let field = first(UISearchTextField.self, in: window) else { log("no search field after the tap"); return }
        log("field: \(describe(field)) firstResponder=\(field.isFirstResponder)")
        if !field.isFirstResponder { field.becomeFirstResponder() }
        field.insertText(query)
        try? await Task.sleep(for: .seconds(1.5))
        log("typed text=\(field.text ?? "nil")")
        log("OPEN")
        try? await Task.sleep(for: .seconds(4))

        // 3. The field's own X (iOS 26 draws Cancel as an X): a button inside
        // the search bar but not inside the text field (that one is the
        // clear button); else, by place, the bar button beside the field.
        func inSearchBar(_ v: UIView) -> Bool {
            var p = v.superview
            while let q = p { if q is UISearchTextField { return false }; if q is UISearchBar { return true }; p = q.superview }
            return false
        }
        var close = controls(in: window) { $0 is UIControl && !($0 is UISearchTextField) && inSearchBar($0) }
        if close.isEmpty {
            close = controls(in: window) {
                String(describing: type(of: $0)) == "_UIButtonBarButton" && $0.convert($0.bounds, to: nil).minY < 130
            }
        }
        log("close candidates: " + close.map(describe).joined(separator: " | "))
        if let close = close.max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }) {
            press(close)
        } else { log("no close button") }
        try? await Task.sleep(for: .seconds(1.5))
        let after = first(UISearchTextField.self, in: window)
        log("after close: field=\(after.map(describe) ?? "gone") text=\(after?.text ?? "nil") firstResponder=\(after?.isFirstResponder ?? false)")
        log("bar buttons now: " + controls(in: window) {
            String(describing: type(of: $0)) == "_UIButtonBarButton" && $0.convert($0.bounds, to: nil).minY < 130
        }.map(describe).joined(separator: " | "))
        log("CLOSED")
        try? await Task.sleep(for: .seconds(4))

        // 4. Open and type again, then away to Home and back.
        if let again = controls(in: window, where: {
            String(describing: type(of: $0)) == "_UIButtonBarButton" && $0.convert($0.bounds, to: nil).minY < 130
        }).max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }) {
            press(again)
            try? await Task.sleep(for: .seconds(1.5))
            first(UISearchTextField.self, in: window)?.insertText(query)
            try? await Task.sleep(for: .seconds(1))
            log("reopened: field=\(first(UISearchTextField.self, in: window).map(describe) ?? "gone") text=\(first(UISearchTextField.self, in: window)?.text ?? "nil")")
        }
        Router.shared.tab = .home
        try? await Task.sleep(for: .seconds(1.5))
        Router.shared.tab = .activity
        try? await Task.sleep(for: .seconds(1.5))
        let back = first(UISearchTextField.self, in: window)
        log("after tab round trip: field=\(back.map(describe) ?? "gone") text=\(back?.text ?? "nil")")
        log("BACK")
    }

    // MARK: Helpers

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }

    private static func label(_ view: UIView) -> String {
        view.accessibilityLabel ?? ""
    }

    private static func describe(_ view: UIView) -> String {
        let f = view.convert(view.bounds, to: nil)
        return "\(type(of: view))'\(label(view))'@\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))\(view.isHidden || view.alpha < 0.05 ? " hidden" : "")"
    }

    private static func controls(in root: UIView, where match: (UIView) -> Bool) -> [UIView] {
        var found: [UIView] = []
        func walk(_ v: UIView) {
            guard !v.isHidden, v.alpha > 0.05 else { return }
            if (v is UIControl || v.accessibilityTraits.contains(.button)), match(v) { found.append(v) }
            v.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    private static func first<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
        if let hit = root as? T, !hit.isHidden { return hit }
        for sub in root.subviews where !sub.isHidden {
            if let hit = first(type, in: sub) { return hit }
        }
        return nil
    }

    /// The control's own actions, as a tap ends them; else its
    /// accessibility activation (what VoiceOver's double-tap does).
    private static func press(_ view: UIView) {
        if let control = view as? UIControl, !control.allControlEvents.isEmpty {
            // One event only: both would run the action twice.
            control.sendActions(for: control.allControlEvents.contains(.primaryActionTriggered)
                                ? .primaryActionTriggered : .touchUpInside)
        } else {
            _ = view.accessibilityActivate()
        }
    }
}
#endif
