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
            ListPageTitle(title: "Privacy & Security", subtitle: "Lock the app, and see what Sortd stores.")
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
                Text("Sortd locks when you open it, and when you come back after more than a minute. Widgets hide amounts on the Lock Screen and in StandBy unless you turn that on.")
            }

            Section {
                NavigationLink {
                    PrivacyView()
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }
            } header: {
                BoldHeader("Privacy")
            } footer: {
                Text("What Sortd stores, and where.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Privacy & Security")
    }
}
