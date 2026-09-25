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

    private var status: ApplePayStatus {
        ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions)
    }

    private var lastTapText: String {
        switch status {
        case .tapLogged(let date, let merchant, _, _):
            return "Last tap \(date.formatted(.relative(presentation: .named))) · \(merchant)"
        // Set up but nothing bought yet. "No taps yet" on its own reads as
        // "this isn't working".
        case .shortcutReached:
            return "Connected · waiting for a shop tap"
        case .notConnected:
            return "Not set up yet"
        }
    }
}
