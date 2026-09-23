import SwiftUI
import SwiftData

/// "Send a test tap": pushes a made-up purchase through the same code a real
/// Apple Pay tap uses, so someone can check the app's half of the setup
/// without buying anything.
///
/// It cannot test Apple's half. The Wallet automation only fires when a card
/// is really tapped, and nothing on the phone can fake that. What this proves
/// is that the action, the parsing, the card matching and the saving all work
/// — so if a real tap still logs nothing, the fault is in the automation.
struct TapTestButton: View {
    @Environment(\.modelContext) private var context
    @State private var outcome: LogPurchaseIntent.Outcome?
    @State private var failure: String?
    @State private var running = false
    @State private var removed = false

    /// A tiny amount, in whatever currency totals are shown in, so the test
    /// purchase is obvious and cheap to undo.
    private static let testAmount = Decimal(string: "4.50")!
    private static let testMerchant = "Sortd Test"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await run() }
            } label: {
                Label(running ? "Testing…" : "Send a Test Tap", systemImage: "wave.3.right")
            }
            .disabled(running)
            // In a List, two plain buttons in one row become one tap target
            // and the second never fires. Borderless keeps them separate.
            .buttonStyle(.borderless)

            if let outcome {
                result(outcome)
            } else if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.down)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func result(_ outcome: LogPurchaseIntent.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(removed ? "Test purchase removed." : outcome.message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: outcome.transaction == nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(outcome.transaction == nil ? Color.down : Color.up)

            if outcome.transaction != nil, !removed {
                // A test must not leave a purchase behind in real totals.
                Button("Remove Test Purchase") { remove(outcome) }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            if outcome.transaction != nil, !removed {
                Text("Sortd's half works. If a real tap still logs nothing, the automation in Shortcuts is not passing the transaction on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func run() async {
        running = true
        failure = nil
        removed = false
        defer { running = false }
        let amount = Money.format(Self.testAmount, Money.home)
        do {
            // The same entry point the Wallet automation calls, with the same
            // shape of arguments, so a pass here means a real tap would pass.
            outcome = try await LogWalletTapIntent.handle(nil, amount: amount,
                                                          merchant: Self.testMerchant,
                                                          card: CardBook.shared.active.first?.name,
                                                          in: context, book: .shared)
        } catch {
            outcome = nil
            failure = "The test could not run: \(error.localizedDescription)"
        }
    }

    private func remove(_ outcome: LogPurchaseIntent.Outcome) {
        guard let t = outcome.transaction else { return }
        context.delete(t)
        try? context.save()
        WidgetBridge.refresh(from: context)
        removed = true
    }
}
