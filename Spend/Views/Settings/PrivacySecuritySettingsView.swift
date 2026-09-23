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
                Text("With the lock on, Sortd locks when you open it or come back after a minute. Widgets hide amounts on the Lock Screen and in StandBy unless Show Amounts When Locked is on.")
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
                row("checklist", "Your setup answers",
                    "Kept only on this iPhone. They choose your setup steps and check-in time. Change them in Help & Feedback › Run Setup Again. Delete All Data removes them.")
                row("bell", "Notifications",
                    "Made on this iPhone, with no push server. Your check-in never shows amounts. Bill reminders show the shop and amount.")
                row("sparkles", "Apple Intelligence",
                    "Where your iPhone has it, reads what you type, scan or get in a receipt email, on this iPhone. Nothing is sent anywhere. Check what it fills in.")
                row("square.grid.2x2", "Widgets",
                    "Show a summary kept on this iPhone. Only Sortd and its widgets can open it.")
            } header: {
                BoldHeader("Stays on This iPhone")
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
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
