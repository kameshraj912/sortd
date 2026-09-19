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

    /// iOS 27: automations are shortcuts that start with a trigger.
    /// Checked step by step on iOS 27.0 (Sep 2026).
    private static let steps27: [Step] = [
        Step(id: 1, symbol: "square.stack.3d.up", title: "Open Shortcuts and tap +",
             detail: "The + is at the bottom. Then tap Edit at the top right (skip the “Describe a shortcut” box)."),
        Step(id: 2, symbol: "wallet.pass", title: "Add the Wallet trigger",
             detail: "Tap Automation, type wallet, and tap Wallet (“When I tap a Wallet Card or Pass”). It starts as Any Card, which is what you want."),
        Step(id: 3, symbol: "plus.square.on.square", title: "Add Sortd's Log Purchase",
             detail: "In the search box at the bottom, type Sortd and tap Log Purchase. It reads “Log Amount at Merchant on Card or Pass”."),
        Step(id: 4, symbol: "arrow.triangle.branch", title: "Fill in the three blue words",
             detail: "Tap Amount → Select Variable → Transaction. Then tap the blue Transaction and pick Amount. Do the same for Merchant (pick Merchant) and Card (pick Card or Pass)."),
        Step(id: 5, symbol: "bolt", title: "Check it runs by itself",
             detail: "Tap the arrow next to “tapped”. Automation should be on. Turn Notify off if you don't want a banner."),
        Step(id: 6, symbol: "checkmark.seal", title: "Tap back, then pay for something",
             detail: "It saves by itself. Your next Apple Pay tap shows up in Sortd within a few seconds."),
    ]

    private static var currentSteps: [Step] {
        if #available(iOS 27.0, *) { return steps27 }
        return steps
    }

    /// iOS 26 and earlier: the separate Automation tab.
    private static let steps: [Step] = [
        Step(id: 1, symbol: "square.stack.3d.up", title: "Open Shortcuts, then Automation",
             detail: "It's the middle tab at the bottom. Tap + at the top right (or New Automation if you have none)."),
        Step(id: 2, symbol: "wallet.pass", title: "Tap “Wallet”",
             detail: "Scroll down to find it. On iOS 17 and 18 it's called “Transaction”."),
        Step(id: 3, symbol: "creditcard", title: "Choose your cards",
             detail: "Tap Choose next to Cards, tick every card you pay with, then Done. Leave Categories and Merchants as they are."),
        Step(id: 4, symbol: "bolt", title: "Tap “Run Immediately”, then Next",
             detail: "Turn off Notify When Run if you don't want a banner each time."),
        Step(id: 5, symbol: "plus.square.on.square", title: "Tap “Create New Shortcut”",
             detail: "Then type Sortd in the search box at the bottom and tap Log Purchase."),
        Step(id: 6, symbol: "arrow.triangle.branch", title: "Fill in Amount, Merchant and Card",
             detail: "Tap the blue word Amount. Above the keyboard, tap Shortcut Input. Then tap the new Shortcut Input and pick Amount. Do the same for Merchant (pick Merchant) and Card (pick Card or Pass)."),
        Step(id: 7, symbol: "checkmark.seal", title: "Tap Done, then pay for something",
             detail: "It shows up in Sortd within a few seconds."),
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
                ForEach(Self.currentSteps) { step in
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
                Label("Only tapping your phone or watch in a shop triggers this. Apple Pay in apps and online (Uber, DoorDash) comes from your email receipts instead.",
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
