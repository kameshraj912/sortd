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
             detail: "Scroll down to find it."),
        Step(id: 3, symbol: "creditcard", title: "Choose your cards",
             detail: "Tap Choose next to Cards, tick every card you pay with, then Done. Leave Categories and Merchants as they are."),
        Step(id: 4, symbol: "bolt", title: "Tap “Run Immediately”, then Next",
             detail: "Turn off Notify When Run if you don't want a banner each time."),
        Step(id: 5, symbol: "plus.square.on.square", title: "Tap “Create New Shortcut”",
             detail: "Then type Sortd in the search box at the bottom and tap Log Wallet Tap."),
        Step(id: 6, symbol: "arrow.triangle.branch", title: "Fill in the three fields",
             detail: "Tap Amount, then Select Variable, then Shortcut Input — then tap that blue word again and choose Amount. Do the same for Shop (Merchant) and, behind ›, Card (Card or Pass)."),
        Step(id: 7, symbol: "checkmark.seal", title: "Tap Done, then pay for something",
             detail: "It shows up in Sortd within a few seconds."),
    ]

    var body: some View {
        List {
            ListPageTitle(title: "Apple Pay Logging")
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

            // The quick way: the shortcut arrives with the amount, shop and
            // card already matched to the parts of the tap.
            Section {
                Button {
                    openURL(URL(string: "https://sortd.page/apple-pay.shortcut")!)
                } label: {
                    Label("Get the Ready-Made Shortcut", systemImage: "square.and.arrow.down")
                }
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                }
            } header: {
                BoldHeader("The Quick Way")
            } footer: {
                Text("Add the shortcut, then build the automation. The pictures below show every screen.")
            }

            if #available(iOS 27.0, *) {
                Section {
                    WalletSetupGuide(route: .quick).padding(.vertical, 8)
                } header: {
                    BoldHeader("After the Shortcut Is Added")
                } footer: {
                    Text("Swipe through the steps. The ▶ button in Shortcuts only runs a test — a purchase is only logged when you tap your card in a shop.")
                }
            }

            if #available(iOS 27.0, *) {
                Section(bold: "Or Do It By Hand") {
                    WalletSetupGuide(route: .byHand).padding(.vertical, 8)
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

            Section {
                TapTestButton()
            } header: {
                BoldHeader("Check It Works")
            } footer: {
                Text("Puts a made-up purchase through the same code a real tap uses, then lets you delete it. It can't test the Shortcuts automation — only tapping your card in a shop does that.")
            }

            if let last = UserDefaults.standard.string(forKey: LogPurchaseIntent.lastTapKey) {
                Section {
                    Text(last).font(.footnote.monospaced()).textSelection(.enabled)
                    // Three empty fields is the single most confusing thing on
                    // this screen: it looks broken, but it is what the ▶ button
                    // in Shortcuts sends, every time.
                    if last.contains("amount “” · merchant “” · card “”") {
                        Label("Nothing was attached to that run. That's what the ▶ button in Shortcuts sends — it proves the connection but never logs a purchase. Only tapping your card in a shop sends real details.",
                              systemImage: "play.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    BoldHeader("Last Tap Received")
                } footer: {
                    Text("What Apple Pay sent. Helps if a tap shows the wrong shop, amount or card.")
                }
            }

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
