import Testing
import Foundation
@testable import Spend

/// `screen_viewed` and the `screen` super property (10 Oct 2026): PostHog's
/// `$rageclick` only named the UIKit hosting controller, so Sortd names the
/// screen itself and registers it for every later event.
@MainActor
struct AnalyticsScreenTests {
    final class RegisterSpy: Analytics.Sink {
        private(set) var captured: [(name: String, properties: [String: Any])] = []
        private(set) var registered: [String] = []
        private(set) var unregistered: [String] = []
        func capture(_ name: String, properties: [String: Any]) { captured.append((name, properties)) }
        func identify(_ id: String) {}
        func reset() {}
        func screen(_ name: String) {}
        func register(_ properties: [String: Any]) {
            if let s = properties["screen"] as? String { registered.append(s) }
        }
        func unregister(_ key: String) { unregistered.append(key) }
    }

    private func make(_ suite: String) -> (Analytics, RegisterSpy) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let spy = RegisterSpy()
        return (Analytics(sink: spy, defaults: defaults, isDemo: { false }, regionCode: "AU"), spy)
    }

    @Test func aScreenIsViewedAndRegistered() {
        let (a, spy) = make(#function)
        a.showScreen(.home)
        #expect(spy.captured.last?.name == "screen_viewed")
        #expect(spy.captured.last?.properties["name"] as? String == "home")
        #expect(spy.registered == ["home"])
        #expect(a.currentScreen == "home")
    }

    /// A sheet on top of a tab: when it goes, the tab is current again,
    /// with no second `screen_viewed`.
    @Test func closingASheetPutsTheScreenUnderItBack() {
        let (a, spy) = make(#function)
        a.showScreen(.home)
        let sheet = a.showScreen(.addPurchase)
        a.screenDisappeared(sheet)
        #expect(spy.registered == ["home", "addPurchase", "home"])
        #expect(spy.captured.filter { $0.name == "screen_viewed" }.count == 2)
        #expect(a.currentScreen == "home")
    }

    /// Switching tabs: the new tab can appear before the old one goes.
    /// Removing a screen that is not on top changes nothing.
    @Test func aTabSwitchInEitherOrderEndsOnTheNewTab() {
        let (a, spy) = make(#function)
        let home = a.showScreen(.home)
        a.showScreen(.activity)
        a.screenDisappeared(home)
        #expect(a.currentScreen == "activity")
        #expect(spy.registered.last == "activity")
    }

    /// The last screen went (the app is in the background, or an intent
    /// runs with no screen): `screen` is dropped, not left on later events.
    @Test func noScreenLeftDropsTheSuperProperty() {
        let (a, spy) = make(#function)
        let home = a.showScreen(.home)
        #expect(spy.unregistered.isEmpty)
        a.screenDisappeared(home)
        #expect(a.currentScreen == nil)
        #expect(spy.unregistered == ["screen"])
    }

    @Test func screenNamesAreFixedWords() {
        #expect(Analytics.ScreenName.applePayGuide(page: 3).rawValue == "applePayGuide.3")
        #expect(Analytics.ScreenName.setupStep("applePay").rawValue == "setup.applePay")
        #expect(Analytics.ScreenName.transactionDetail.rawValue == "transactionDetail")
    }

    @Test func offSendsNothingButKeepsTheScreen() {
        let (a, spy) = make(#function)
        a.isEnabled = false
        let before = spy.captured.count
        a.showScreen(.insights)
        #expect(spy.captured.count == before)
        #expect(spy.registered.isEmpty)
        a.isEnabled = true
        #expect(spy.registered == ["insights"])
    }

    @Test func helpOpenedCarriesTopicAndSource() {
        let p = HelpTopic.properties(.supportEmail, source: .settings)
        guard case .string(let topic)? = p["topic"], case .string(let source)? = p["source"] else {
            Issue.record("missing topic or source"); return
        }
        #expect(topic == "support_email")
        #expect(source == "settings")
        let panel = HelpTopic.properties(.learnMore, source: .setupPanel)
        if case .string(let s)? = panel["source"] { #expect(s == "setup_panel") } else { Issue.record("no source") }
    }
}
