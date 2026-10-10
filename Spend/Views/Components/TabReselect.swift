import SwiftUI
import Observation

/// A tap on the tab that is already showing (beta, 10 Oct 2026: six
/// testers tapped Home again and again from a pushed purchase and nothing
/// happened). Each tab's `NavigationStack` takes `.id(TabReselect.shared
/// .generation(for:))`, so a re-tap rebuilds the stack: back to its root,
/// scrolled to the top, as iOS's own apps do.
@MainActor @Observable
final class TabReselect {
    static let shared = TabReselect()

    private(set) var generations: [AppTab: Int] = [:]

    func generation(for tab: AppTab) -> Int { generations[tab, default: 0] }

    /// Called by the tab bar's selection when `tab` is picked while it is
    /// already the current one.
    func reselect(_ tab: AppTab) {
        generations[tab, default: 0] += 1
    }
}

extension View {
    /// Rebuilds this tab's navigation stack when its tab is tapped again.
    func popsToRootOnReselect(_ tab: AppTab) -> some View {
        id(TabReselect.shared.generation(for: tab))
    }
}
