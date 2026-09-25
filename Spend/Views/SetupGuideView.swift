import SwiftUI
import SwiftData

/// Settings › Purchase Sources › Apple Pay Logging: the same panel as the
/// setup step, plus one line under it. Every state comes from a real event
/// (spec 2026-09-25). One path only, the ready-made shortcut — the by-hand
/// walkthrough and "Good to Know" both moved to the website (router feel
/// checks, 26 Sep 2026, "short"; see `docs/site-copy-moved.md`), and the raw
/// last-tap text is a long-press on the status card, not a section every
/// visitor sees.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    private var status: ApplePayStatus {
        ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions)
    }

    var body: some View {
        List {
            ListPageTitle(title: "Apple Pay Logging")
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Log every Apple Pay tap automatically.")
                        .font(.title2.weight(.bold))
                    Text("A one-time, two-minute setup in Shortcuts.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            Section {
                ApplePaySetupPanel(status: status)
            } footer: {
                Text(Features.gmail
                     ? "In-app and online Apple Pay comes from your email receipts."
                     : "Add in-app and online Apple Pay by hand.")
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Apple Pay Logging")
        .toolbar {
            if isPresentedAsSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .tint(Color.brand)
                }
            }
        }
    }

    var isPresentedAsSheet = false
}
