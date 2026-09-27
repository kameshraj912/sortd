import SwiftUI
import SwiftData

/// Settings › Privacy & Security: the app lock, widget/Lock Screen amount
/// hiding, and what Sortd stores.
struct PrivacySecuritySettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage(WidgetSummary.showWhenLockedKey) private var widgetShowWhenLocked = false

    var body: some View {
        List {
            ListPageTitle(title: "Privacy & Security")
            Section {
                Toggle(isOn: Binding(
                    get: { lockEnabled },
                    set: { on in
                        guard on else { lockEnabled = false; return }
                        // Check it works before turning it on.
                        Task {
                            if await AppLock.authenticate(reason: "Turn on the lock for Sortd.") {
                                lockEnabled = true
                                Analytics.shared.track(.appLockTurnedOn)
                            }
                        }
                    }
                )) {
                    Label("Require \(AppLock.methodName)", systemImage: AppLock.methodSymbol)
                }
                Toggle(isOn: $widgetShowWhenLocked) {
                    Label("Show Amounts When Locked", systemImage: "lock.rectangle")
                }
                .onChange(of: widgetShowWhenLocked) { _, _ in WidgetBridge.refresh(from: context) }
            } header: {
                BoldHeader("Security")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Locks when you open the app or come back after a minute.")
                    Link("Learn more", destination: URL(string: "https://sortd.page/help#app-lock")!)
                }
            }

            Section {
                NavigationLink {
                    PrivacyView()
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }
            } header: {
                BoldHeader("What Sortd Stores")
            }

            Section {
                row("checklist", "Your setup answers", "Kept only on this iPhone.")
                row("bell", "Notifications", "Made on this iPhone. Check-ins never show amounts.")
                row("sparkles", "Apple Intelligence", "Reads receipts on this iPhone. Nothing is sent anywhere.")
                row("square.grid.2x2", "Widgets", "A summary kept on this iPhone.")
            } header: {
                BoldHeader("Stays on This iPhone")
            } footer: {
                Link("Learn more", destination: URL(string: "https://sortd.page/help#stays-on-iphone")!)
            }

            Section {
                Link(destination: URL(string: "https://sortd.page/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://sortd.page/terms")!) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
            }
            .tint(Color.ink)
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Privacy & Security")
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(Color.ink).padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
