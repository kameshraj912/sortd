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
