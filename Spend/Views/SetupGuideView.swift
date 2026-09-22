import SwiftUI

/// Step-by-step guide to the Shortcuts automation that logs every tap.
struct SetupGuideView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    // @AppStorage (not a direct UserDefaults read) so this updates live: a
    // tap logged while this screen is open shows up without reopening it.
    @AppStorage(LogPurchaseIntent.lastTapKey) private var lastTapRaw = ""
    @AppStorage(LogPurchaseIntent.lastOutcomeKey) private var lastTapOutcome = ""

    private struct Step: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let detail: String
    }

    /// iOS 27: automations are shortcuts that start with a trigger.
    /// Checked step by step on iOS 27.0 (Sep 2026).
    private static let steps27: [Step] = WalletSetupGuide.pages.map {
        Step(id: $0.id + 1, symbol: "", title: $0.title, detail: $0.detail)
    }

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
             detail: "Then type Sortd in the search box at the bottom and tap Log Wallet Tap."),
        Step(id: 6, symbol: "arrow.triangle.branch", title: "Fill in Transaction",
             detail: "Tap the word Transaction. Above the keyboard, tap Shortcut Input. That's the only one."),
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

            if #available(iOS 27.0, *) {
                Section(bold: "Steps") {
                    WalletSetupGuide().padding(.vertical, 8)
                }
            } else {
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

            if !lastTapRaw.isEmpty {
                Section {
                    if !lastTapOutcome.isEmpty {
                        Text(lastTapOutcome).font(.subheadline.weight(.semibold))
                    }
                    Text(lastTapRaw).font(.footnote.monospaced()).textSelection(.enabled)
                        .foregroundStyle(lastTapOutcome.isEmpty ? .primary : .secondary)
                } header: {
                    BoldHeader("Last Tap Received")
                } footer: {
                    Text("What Sortd did with the last tap. Useful if something looks wrong.")
                }
            }

            Section(bold: "Good to Know") {
                Label(Features.gmail
                      ? "Only tapping your phone or watch in a shop triggers this. Apple Pay in apps and online (Uber, DoorDash) comes from your email receipts instead."
                      : "Only tapping your phone or watch in a shop triggers this. Add Apple Pay in apps and online (Uber, DoorDash) by hand.",
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
