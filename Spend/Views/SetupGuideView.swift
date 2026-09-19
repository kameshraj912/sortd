import SwiftUI

/// Step-by-step guide to the Shortcuts automation that logs every tap.
struct SetupGuideView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let detail: String
    }

    private static let steps: [Step] = [
        Step(id: 1, symbol: "square.stack.3d.up", title: "Open Shortcuts → Automation",
             detail: "Tap New Automation (or + at the top)."),
        Step(id: 2, symbol: "wallet.pass", title: "Choose “Wallet”",
             detail: "On older iOS it’s called “Transaction”."),
        Step(id: 3, symbol: "creditcard", title: "Pick your cards",
             detail: "Select every card you pay with. Leave categories and merchants on Any."),
        Step(id: 4, symbol: "bolt", title: "Choose “Run Immediately”",
             detail: "Turn off Notify When Run if you don’t want a banner. Tap Next."),
        Step(id: 5, symbol: "plus.square.on.square", title: "Add the “Log Purchase” action",
             detail: "Start with New Blank Automation, search for Sortd, and add Log Purchase."),
        Step(id: 6, symbol: "arrow.triangle.branch", title: "Fill in the three fields",
             detail: "Tap Merchant → Shortcut Input → Merchant. Do the same for Amount → Amount, and Card → Card or Pass."),
        Step(id: 7, symbol: "checkmark.seal", title: "Tap Done, then pay for something",
             detail: "It shows up in Sortd within a second or two."),
    ]

    var body: some View {
        List {
            ListPageTitle(title: "Auto-Logging")
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Log every Apple Pay tap automatically")
                        .font(.title2.weight(.bold))
                    Text("A one-time, two-minute setup in the Shortcuts app. After that, every Apple Pay tap is logged, even with Sortd closed.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            Section(bold: "Steps") {
                ForEach(Self.steps) { step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(step.id)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.onBrand)
                            .frame(width: 28, height: 28)
                            .background(Color.brand, in: .circle)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Label(step.title, systemImage: step.symbol)
                                .font(.body.weight(.semibold))
                                .labelStyle(.titleOnly)
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(step.id). \(step.title). \(step.detail)")
                }
            }

            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent).tint(Color.brand).foregroundStyle(Color.onBrand)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section(bold: "Good to Know") {
                Label("Only in-store taps trigger this. Uber, DoorDash and online Apple Pay will come from your email receipts in the next update.",
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
        .brandedTitle("Auto-Logging")
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
