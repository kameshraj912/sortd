import SwiftUI

/// Where the add, search and settings controls sit. Being tried out on the
/// ux-refresh branch; DEBUG builds pick one with SPEND_NAV=<rawValue>.
enum NavLayout: String {
    /// Gear and + in Home's header; search is a tab inside the bar.
    case header
    /// Floating glass + above the tab bar; gear alone in Home's header;
    /// search as the separate circle beside the bar.
    case fab
    /// iOS 27 prominent + tab in the bar; gear in Home's header.
    case prominent
    /// Standard glass toolbar buttons at the top of each tab (Mail/Notes style).
    case toolbar

    static let current: NavLayout = {
        // + in its own glass circle beside the tab bar, on every iOS: the
        // prominent tab on iOS 27, the same slot (the search circle) on 26.
        var chosen = NavLayout.prominent
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SPEND_NAV"], let layout = NavLayout(rawValue: raw) {
            chosen = layout
        }
        #endif
        return chosen
    }()

    /// The search field lives on the TabView (separate search circle) rather
    /// than inside the Search tab's own navigation bar.
    var rootSearch: Bool { false }
}

/// Which tabs there are and where Settings lives. Three candidates from the
/// navigation research, tried side by side; DEBUG picks one with
/// SPEND_NAVOPT=<rawValue>. Release uses `today` until one is chosen.
enum NavOption: String {
    /// Home, Activity, Insights, Search + the + circle; gear on Home only.
    case today
    /// Home, Activity, Insights + the + circle; search at the top of
    /// Activity; the gear in the same top-right spot on every tab.
    case threeTabs
    /// Today's tabs, with the gear top-right on every tab.
    case gearEverywhere
    /// Home, Activity, Insights, You (Settings as a tab) + the + circle.
    case youTab

    static let current: NavOption = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SPEND_NAVOPT"], let option = NavOption(rawValue: raw) {
            return option
        }
        #endif
        return .today
    }()

    var hasSearchTab: Bool { self == .today || self == .gearEverywhere }
    var hasYouTab: Bool { self == .youTab }
    /// The gear floats top-right over every tab (like the account button in
    /// Apple's own apps), instead of sitting in Home's header.
    var gearOnEveryTab: Bool { self == .threeTabs || self == .gearEverywhere }
    var gearOnHome: Bool { self == .today }
    var searchInActivity: Bool { self == .threeTabs }
}

/// The Settings button, the same glass circle wherever it appears.
struct SettingsButton: View {
    var body: some View {
        Button { Router.shared.showingSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(Color.ink)
        .accessibilityLabel("Settings")
    }
}

/// The floating add button: tap to add, hold for the other ways in.
struct AddFAB: View {
    let add: () -> Void
    let scan: () -> Void
    let importing: () -> Void

    var body: some View {
        Menu {
            Button("Import Statement", systemImage: "tray.and.arrow.down", action: importing)
            Button("Scan Receipt", systemImage: "doc.viewfinder", action: scan)
            Button("Add Manually", systemImage: "square.and.pencil", action: add)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 60, height: 60)
        } primaryAction: {
            add()
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(Color.brand)
        .accessibilityLabel("Add Purchase")
        .accessibilityHint("Hold for more ways to add")
    }
}
