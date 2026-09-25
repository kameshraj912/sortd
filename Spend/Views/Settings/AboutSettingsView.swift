import SwiftUI
import SwiftData

/// Settings › About: purchase count, where things are stored, the app
/// version, the tip jar, and the legal links.
struct AboutSettingsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var tipping = false

    var body: some View {
        List {
            ListPageTitle(title: "About")
            Section {
                LabeledContent("Purchases", value: "\(transactions.count)")
                LabeledContent("Stored", value: "On this iPhone only")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            }

            Section {
                Button { tipping = true } label: {
                    HStack {
                        Label("Leave a Tip", systemImage: "heart")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .accessibilityHint("Opens the tip jar")
            } footer: {
                Text("Sortd is free. A tip unlocks nothing; it just says thanks.")
            }
            .tint(Color.ink)

            Section {
                Link(destination: URL(string: "https://sortd.page/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://sortd.page/terms")!) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://sortd.page/support")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
            } header: {
                BoldHeader("Legal")
            } footer: {
                Text("No Sortd account and no server. Your purchases, cards, settings and setup answers stay on this iPhone.")
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
    }
}
