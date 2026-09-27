import SwiftUI
import SwiftData
import StoreKit

/// Settings › About: the app icon and version, a tagline, the tip jar,
/// and the App Store / website / legal links.
struct AboutSettingsView: View {
    @State private var tipping = false
    private let tipJar = TipJar.shared
    @Environment(\.requestReview) private var requestReview
    /// Taps on the version line, for the hidden developer menu: 7 within 3
    /// seconds. Old taps age out, so a slow 7th tap never counts a stale run.
    @State private var versionTaps: [Date] = []
    @State private var devMenuOpens = 0
    @State private var showingDeveloper = false

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }

    /// 7 taps within 3 seconds opens the developer menu (Settings › About).
    private func registerVersionTap() {
        let now = Date.now
        versionTaps = versionTaps.filter { now.timeIntervalSince($0) < 3 } + [now]
        guard versionTaps.count >= 7 else { return }
        versionTaps = []
        devMenuOpens += 1
        showingDeveloper = true
    }

    var body: some View {
        List {
            ListPageTitle(title: "About")
            Section {
                VStack(spacing: 8) {
                    Image("BrandIcon")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 15, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Sortd").font(.title2.weight(.semibold))
                    Text("Version \(version) (\(build))")
                        .font(.footnote).foregroundStyle(.secondary)
                        .onTapGesture { registerVersionTap() }
                    Text("Tap to pay. Sortd writes it down.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)

            // The row waits for the App Store to know the three tips. Until
            // the products exist there is nothing to buy, so nothing to show.
            if !tipJar.products.isEmpty {
                Section {
                    Button { tipping = true } label: {
                        Label("Leave a Tip", systemImage: "heart")
                    }
                    .accessibilityHint("Opens the tip jar")
                }
                .tint(Color.ink)
            }

            Section {
                Button { requestReview() } label: {
                    Label("Rate on the App Store", systemImage: "star")
                }
                Link(destination: URL(string: "https://sortd.page/changelog")!) {
                    Label("What's New", systemImage: "sparkles")
                }
                Link(destination: URL(string: "https://sortd.page")!) {
                    Label("Website", systemImage: "globe")
                }
                Link(destination: URL(string: "https://sortd.page/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://sortd.page/terms")!) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
            }
            .tint(Color.ink)
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        // A 1pt clear row used to stand in for this. It can't clear a 49pt
        // (SE) or 83pt (Pro Max) bar; the list just needs the real inset.
        .contentMargins(.bottom, 24, for: .scrollContent)
        .brandedTitle("About")
        .sheet(isPresented: $tipping) { TipJarView() }
        .task { await tipJar.load() }
        .sheet(isPresented: $showingDeveloper) { DeveloperMenuView() }
        // `.undo`'s light weight, reused here for the 7th tap: the map has
        // no case of its own for a hidden Easter egg.
        .feedback(.undo, trigger: devMenuOpens)
    }
}
