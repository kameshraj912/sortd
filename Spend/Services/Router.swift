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

    /// What a `sortd://` link names, and the id after it if it has one
    /// ("sortd://purchase/<id>").
    struct Target: Equatable {
        var name: String
        var id: String?
    }

    var tab: AppTab = .home
    /// A purchase a widget row asked to open. Activity opens its detail and
    /// clears this; if the purchase is gone it just clears it.
    var pendingPurchase: UUID?
    var sheet: Sheet?
    var settingsPath: [Destination] = []
    /// Settings is a sheet over the tabs, opened from the gear on Home.
    var showingSettings = false
    /// "Run Setup Again" was tapped: setup opens once Settings has closed.
    var pendingRerun = false
    /// Help › "Show the Intro Again" was tapped: the intro starts once
    /// Settings has closed.
    var pendingIntroReplay = false

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
        guard let target = Self.target(for: url) else { return }
        let name = target.name

        // Settings is a sheet: close it first for links that go somewhere
        // else, then follow the link once it's out of the way.
        if showingSettings, name != "bills", name != "import" {
            showingSettings = false
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                follow(target)
            }
            return
        }
        follow(target)
    }

    /// Splits a `sortd://` URL into its name and optional id. Pure, so the
    /// parsing can be tested without a screen. Nil for any other scheme.
    nonisolated static func target(for url: URL) -> Target? {
        guard url.scheme == "sortd" else { return nil }
        // "sortd://add" puts "add" in the host, not the path; whatever
        // follows the host ("/<id>") is the id.
        if let host = url.host() {
            let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return Target(name: host, id: id.isEmpty ? nil : id)
        }
        let parts = url.path().split(separator: "/").map(String.init)
        return Target(name: parts.first ?? "", id: parts.dropFirst().first)
    }

    func follow(_ target: Target) {
        switch target.name {
        case "purchase":
            // Straight to that purchase. A missing or unreadable id, or a
            // purchase since deleted or merged, still lands on Activity:
            // Activity decides there is nothing to open and says nothing.
            tab = .activity
            pendingPurchase = target.id.flatMap(UUID.init(uuidString:))
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
