import SwiftUI
import SwiftData

/// Settings › Bills & Reminders: recurring subscriptions/bills and the
/// day-before notification.
struct BillsRemindersSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @State private var showingPaywall = false
    @AppStorage(SetupProfile.checkInKey) private var checkIn = SetupProfile.CheckIn.needed.rawValue
    @State private var notificationsBlocked = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            ListPageTitle(title: "Bills & Reminders", subtitle: "Subscriptions, bills, and your check-in.")
            Section {
                Picker(selection: $checkIn) {
                    ForEach(SetupProfile.CheckIn.allCases) { c in
                        Text(c == .needed ? "Off" : c.title).tag(c.rawValue)
                    }
                } label: {
                    Label("Check-in", systemImage: "calendar.badge.clock")
                }
                .onChange(of: checkIn) { _, raw in
                    let choice = SetupProfile.CheckIn(rawValue: raw) ?? .needed
                    Task {
                        if choice != .needed, !(await Reminders.requestPermission()) {
                            checkIn = SetupProfile.CheckIn.needed.rawValue
                            notificationsBlocked = true
                            return
                        }
                        // Picked again while this one waited: the newer one wins.
                        guard checkIn == raw else { return }
                        await CheckInReminder.schedule(choice)
                    }
                }
            } header: {
                BoldHeader("Check-in")
            } footer: {
                Text((SetupProfile.CheckIn(rawValue: checkIn) ?? .needed).detail + ". A short nudge to take a look. Free.")
            }
            Section {
                NavigationLink {
                    ProGate(feature: .recurring) { RecurringView() }
                } label: {
                    Label("Subscriptions & Bills", systemImage: "arrow.triangle.2.circlepath")
                }
                Toggle(isOn: $reminders) {
                    Label("Remind Me the Day Before", systemImage: "bell")
                }
                .onChange(of: reminders) { _, on in
                    if on, !ProStore.shared.isPro { reminders = false; showingPaywall = true; return }
                    Task {
                        if on, !(await Reminders.requestPermission()) { reminders = false }
                        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
                        await Reminders.reschedule(all.recurring())
                    }
                }
            } header: {
                BoldHeader("Recurring")
            } footer: {
                Text("A notification at 9 am the day before a subscription or bill is due.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Bills & Reminders")
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .alert("Notifications are off for Sortd", isPresented: $notificationsBlocked) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Turn them on in the Settings app to get your check-in.")
        }
    }
}
