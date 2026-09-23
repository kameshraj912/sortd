import SwiftUI
import SwiftData

/// Settings › About: purchase count, where things are stored, the app
/// version — and, five taps on Version in DEBUG builds, the hidden
/// comped-Pro code sheet.
struct AboutSettingsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    #if DEBUG
    @State private var knock = SecretKnock.shared
    #endif

    var body: some View {
        List {
            ListPageTitle(title: "About")
            Section {
                LabeledContent("Purchases", value: "\(transactions.count)")
                LabeledContent("Stored", value: "On this iPhone only")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    #if DEBUG
                    .contentShape(.rect)
                    .onTapGesture { knock.knock() }
                    .accessibilityHint("Tapped five times, opens a code screen")
                    #endif
            } footer: {
                #if DEBUG
                if let hint = knock.hint {
                    Text(hint).foregroundStyle(.secondary)
                } else if let source = CompedPro.source() {
                    // Named so a tester can say which code they used —
                    // the app has no server and reports nothing.
                    Text("Pro is on the house. Code: \(source)")
                        .foregroundStyle(.secondary)
                }
                #endif
            }

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
        #if DEBUG
        .sheet(isPresented: $knock.isOpen) { SecretCodeSheet() }
        #endif
    }
}
