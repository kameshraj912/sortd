import SwiftUI

/// Where a tap from a widget should land.
///
/// Apple's widget guidance is specific about this: a widget tap should open
/// the app at the thing the widget was showing, not drop people on the first
/// screen to find it themselves. So each widget carries its own URL and this
/// turns it into a tab, and sometimes a sheet or a pushed screen.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    /// A screen to push inside Settings.
    enum Destination: Hashable {
        case importing, recurring
    }

    /// A sheet for Home to present.
    enum Sheet: Hashable {
        case add, budget
    }

    var tab: AppTab = .home
    var sheet: Sheet?
    var settingsPath: [Destination] = []
    /// Settings is a sheet over the tabs, opened from the gear on Home.
    var showingSettings = false
    /// "Run Setup Again" was tapped: setup opens once Settings has closed.
    var pendingRerun = false
    /// Help › "Show the Intro Again" was tapped: the intro starts once
    /// Settings has closed.
    var pendingIntroReplay = false
    /// Set by `RootView` when the intro's `.move` step starts: `ActivityView`
    /// clears it, and calls its own `stepDay(1)` first if a second day of
    /// data exists (only it knows that).
    var pendingIntroDayTap = false

    private init() {
        #if DEBUG
        showingSettings = ProcessInfo.processInfo.environment["SPEND_TAB"] == "settings"
        #endif
    }

    /// Handles a `sortd://` URL from a widget. Unknown links just open the
    /// app on Home rather than doing nothing, which is the friendlier miss.
    func open(_ url: URL) {
        guard url.scheme == "sortd" else { return }
        // Setup comes first: while it's on screen, links would open behind it.
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: OnboardingView.doneKey), !defaults.bool(forKey: SetupProfile.rerunKey) else { return }
        // "sortd://add" puts "add" in the host, not the path.
        let name = url.host() ?? url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Settings is a sheet: close it first for links that go somewhere
        // else, then follow the link once it's out of the way.
        if showingSettings, name != "bills", name != "import" {
            showingSettings = false
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                follow(name)
            }
            return
        }
        follow(name)
    }

    private func follow(_ name: String) {
        switch name {
        case "add", "scan":
            tab = .home
            sheet = .add
        case "budget":
            tab = .home
            sheet = .budget
        case "activity":
            tab = .activity
        case "insights":
            tab = .insights
        case "bills":
            settingsPath = [.recurring]
            showingSettings = true
        case "import":
            settingsPath = [.importing]
            showingSettings = true
        default:
            tab = .home
        }
    }

    /// Called once the sheet has been shown, so it doesn't reopen.
    func clearSheet() { sheet = nil }
}
