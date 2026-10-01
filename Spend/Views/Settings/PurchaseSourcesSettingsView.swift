import SwiftUI
import SwiftData

/// Settings › Purchase Sources: Apple Pay auto-logging, the way Sortd finds a
/// purchase without you typing it in.
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
                            HStack(spacing: 6) {
                                Text("Apple Pay Logging")
                                if needsCheckCount > 0 {
                                    Text("\(needsCheckCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Color.onBrand)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(.orange, in: .capsule)
                                        .accessibilityHidden(true)
                                }
                            }
                            Text(lastTapText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wave.3.right")
                    }
                    .accessibilityLabel(needsCheckCount > 0
                        ? "Apple Pay Logging, \(ApplePayStatus.needsCheckLine(count: needsCheckCount) ?? ""). \(lastTapText)"
                        : "Apple Pay Logging. \(lastTapText)")
                }
            } header: {
                BoldHeader("Apple Pay")
            } footer: {
                Text("Logs in-store Apple Pay taps the moment you pay.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Purchase Sources")
    }

    private var status: ApplePayStatus {
        ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions)
    }

    private var needsCheckCount: Int { ApplePayStatus.needsCheckCount(in: transactions) }

    private var lastTapText: String {
        switch status {
        case .tapLogged(let date, let merchant, _, _):
            return "Last tap \(date.formatted(.relative(presentation: .named))) · \(merchant)"
        case .tapNeedsCheck(let date):
            return "Last tap \(date.formatted(.relative(presentation: .named))) · needs a check"
        // Set up but nothing bought yet. "No taps yet" on its own reads as
        // "this isn't working".
        case .shortcutReached:
            return "Connected · waiting for a shop tap"
        case .notConnected:
            return "Not set up yet"
        }
    }
}
