import SwiftUI
import SwiftData

/// Settings › Purchase Sources: Apple Pay auto-logging and Gmail receipts —
/// the two ways Sortd finds a purchase without you typing it in.
struct PurchaseSourcesSettingsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    var body: some View {
        List {
            ListPageTitle(title: "Purchase Sources")
            Section {
                NavigationLink {
                    SetupGuideView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Pay Logging")
                            Text(lastTapText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wave.3.right")
                    }
                }
            } header: {
                BoldHeader("Apple Pay")
            } footer: {
                Text("Logs in-store Apple Pay taps the moment you pay.")
            }

            if Features.gmail { GmailSection() }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Purchase Sources")
    }

    private var lastTapText: String {
        guard let last = transactions.first(where: { $0.seenIn.contains(.tap) }) else {
            return "No taps yet"
        }
        return "Last tap \(last.date.formatted(.relative(presentation: .named)))"
    }
}
