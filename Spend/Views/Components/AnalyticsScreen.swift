import SwiftUI

extension Analytics {
    /// A named screen appeared: it goes on top (`screenAppeared`, which
    /// registers the `screen` super property) and `screen_viewed` is sent.
    @discardableResult
    func showScreen(_ name: ScreenName) -> UUID {
        let token = screenAppeared(name)
        track(.screenViewed, ["name": .string(name.rawValue)])
        return token
    }
}

extension View {
    /// Names this screen for analytics while it is on show: `screen_viewed`
    /// when it appears, and the `screen` super property for as long as it
    /// is on top (`Analytics.screenAppeared`). A changed name (a new page
    /// of the walk-through) counts as a new screen.
    func analyticsScreen(_ name: Analytics.ScreenName) -> some View {
        modifier(AnalyticsScreenModifier(name: name))
    }
}

private struct AnalyticsScreenModifier: ViewModifier {
    let name: Analytics.ScreenName
    @State private var token: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear { show() }
            .onDisappear { hide() }
            .onChange(of: name) {
                // The new page goes on top first, then the old one is taken
                // out from under it.
                let old = token
                token = Analytics.shared.showScreen(name)
                if let old { Analytics.shared.screenDisappeared(old) }
            }
    }

    private func show() {
        guard token == nil else { return }
        token = Analytics.shared.showScreen(name)
    }

    private func hide() {
        guard let token else { return }
        Analytics.shared.screenDisappeared(token)
        self.token = nil
    }
}
