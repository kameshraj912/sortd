import SwiftUI
import SwiftData

/// Settings › Privacy & Security: the app lock, widget/Lock Screen amount
/// hiding, and what Sortd stores.
struct PrivacySecuritySettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage(AppLock.requireAfterKey) private var requireAfterRaw = AppLock.RequireAfter.immediately.rawValue
    @AppStorage(WidgetSummary.showWhenLockedKey) private var widgetShowWhenLocked = false

    @State private var lockFailed = false
    /// The row icons' column grows with the text: a fixed 24 pt let the
    /// symbols spill out of it at AX5 (U5).
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

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
                            } else {
                                // Say so: a toggle that springs back with no word
                                // reads as broken (feel check, 27 Sep).
                                lockFailed = true
                            }
                        }
                    }
                )) {
                    Label("Require \(AppLock.methodName)", systemImage: AppLock.methodSymbol)
                }
                if lockEnabled {
                    Picker("Require after", selection: Binding(
                        get: { AppLock.RequireAfter(rawValue: requireAfterRaw) ?? .immediately },
                        set: { requireAfterRaw = $0.rawValue }
                    )) {
                        ForEach(AppLock.RequireAfter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }
                Toggle(isOn: $widgetShowWhenLocked) {
                    Label("Show Amounts When Locked", systemImage: "lock.rectangle")
                }
                .onChange(of: widgetShowWhenLocked) { _, _ in WidgetBridge.refresh(from: context) }
            } header: {
                BoldHeader("Security")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uses the Face ID and passcode already on your iPhone. Nothing extra to remember.")
                    if #available(iOS 18, *) {
                        Text("You can also lock Sortd from the Home Screen: hold the app icon and choose Require Face ID.")
                    }
                    FooterLink("Learn more", destination: Self.appLockHelpURL)
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
                // The bank-app part since 8 Oct 2026: the shortcut can pass
                // a bank app's notifications to Sortd (`BankNotice`).
                row("bell", "Notifications", "Made on this iPhone. Check-ins never show amounts. If you add your bank's app to the shortcut, its notifications reach Sortd on this iPhone only; purchases are kept, the rest ignored.")
                row("sparkles", "Apple Intelligence", "Reads receipts on this iPhone. Nothing is sent anywhere.")
                row("square.grid.2x2", "Widgets", "A summary kept on this iPhone.")
            } header: {
                BoldHeader("Stays on This iPhone")
            } footer: {
                FooterLink("Learn more", destination: Self.staysOnIPhoneURL)
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
        .alert("Couldn't turn on \(AppLock.methodName)", isPresented: $lockFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check that \(AppLock.methodName) or a passcode is set up in iPhone Settings, then try again.")
        }
    }

    static let appLockHelpURL = URL(string: "https://sortd.page/help#app-lock") ?? URL(fileURLWithPath: "/")
    static let staysOnIPhoneURL = URL(string: "https://sortd.page/help#stays-on-iphone") ?? URL(fileURLWithPath: "/")

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).frame(width: iconWidth).foregroundStyle(Color.ink).padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A link in a grouped list's footer. The footer's grey made a plain Link
/// read as more footer text, worst in dark mode (U3): this one is in the
/// ink colour, semibold and underlined.
struct FooterLink: View {
    let title: String
    let destination: URL

    init(_ title: String, destination: URL) {
        self.title = title
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            Text(title)
                .fontWeight(.semibold)
                .underline()
                .foregroundStyle(Color.ink)
        }
        .accessibilityAddTraits(.isLink)
    }
}
