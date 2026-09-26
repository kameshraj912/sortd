import SwiftUI
import SwiftData
import StoreKit

/// Settings › About: the app icon and version, a tagline, the tip jar,
/// and the App Store / website / legal links.
struct AboutSettingsView: View {
    @State private var tipping = false
    @State private var showingFounderNote = false
    private let tipJar = TipJar.shared
    @Environment(\.requestReview) private var requestReview

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }

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
                Button { showingFounderNote = true } label: {
                    Label("A Note from the Founder", systemImage: "envelope.open")
                }
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
        .sheet(isPresented: $showingFounderNote) { FounderNoteSheet(moment: .about) }
        .task { await tipJar.load() }
    }
}
