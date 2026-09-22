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
            ListPageTitle(title: "About", subtitle: "Sortd, and what's stored where.")
            Section {
                LabeledContent("Purchases", value: "\(transactions.count)")
                LabeledContent("Stored", value: "On this iPhone only")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    #if DEBUG
                    .contentShape(.rect)
                    .onTapGesture { knock.knock() }
                    .accessibilityHint("Tapped five times, opens a code screen")
                    #endif
                // The flat tab bar sits over the last row otherwise, and
                // the last row is the one with the hidden door in it.
                Color.clear
                    .frame(height: 1)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
            } header: {
                BoldHeader("About")
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
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("About")
        #if DEBUG
        .sheet(isPresented: $knock.isOpen) { SecretCodeSheet() }
        #endif
    }
}
