import SwiftUI
import SwiftData

/// Settings › Purchase Sources › Apple Pay Logging: the same panel as the
/// setup step, plus "Good to Know". Every state comes from a real event
/// (spec 2026-09-25). One path only, the ready-made shortcut — the by-hand
/// walkthrough moved to the website (router feel check, 26 Sep 2026, "short
/// and clean"; see `docs/site-copy-moved.md`), and the raw last-tap text is
/// a long-press on the status card, not a section every visitor sees.
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
            }
            .listRowBackground(Color.clear)

            Section(bold: "Good to Know") {
                Label(Features.gmail
                      ? "This only works when you tap your phone or watch in a shop. Apple Pay in apps and online (like Uber) comes from your email receipts."
                      : "This only works when you tap your phone or watch in a shop. Add Apple Pay in apps and online (like Uber) by hand.",
                      systemImage: "info.circle")
                Label("If Apple Pay ever sends a purchase without an amount, Sortd still saves it and marks it “Add amount”.",
                      systemImage: "exclamationmark.circle")
                Label("The purchase currency follows your time zone, so travel spending is converted automatically.",
                      systemImage: "globe.asia.australia")
            }
            .font(.subheadline)
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
