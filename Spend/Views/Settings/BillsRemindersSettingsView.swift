import SwiftUI
import SwiftData

/// Settings › Bills & Reminders: recurring subscriptions/bills and the
/// day-before notification.
struct BillsRemindersSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @AppStorage(Reminders.paceAlertKey) private var paceAlert = true
    @AppStorage(SetupProfile.checkInKey) private var checkIn = SetupProfile.CheckIn.needed.rawValue
    @State private var notificationsBlocked = false
    /// What iOS allows now. Assumed yes until checked, so the switch does not
    /// flick off and on while the answer comes back.
    @State private var notificationsAllowed = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            ListPageTitle(title: "Bills & Reminders")
            Section {
                Picker(selection: $checkIn) {
                    ForEach(SetupProfile.CheckIn.allCases) { c in
                        Text(c == .needed ? "Off" : c.title).tag(c.rawValue)
                    }
                } label: {
                    Label("Check-In", systemImage: "calendar.badge.clock")
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
            } footer: {
                let choice = SetupProfile.CheckIn(rawValue: checkIn) ?? .needed
                Text(choice == .needed ? "Get a short reminder to check your spending." : choice.detail + ".")
            }
            Section {
                NavigationLink {
                    RecurringView()
                } label: {
                    Label("Subscriptions & Bills", systemImage: "arrow.triangle.2.circlepath")
                }
                Toggle(isOn: $reminders) {
                    Label("Remind Me the Day Before", systemImage: "bell")
                }
                .onChange(of: reminders) { _, on in
                    Task {
                        if on, !(await Reminders.requestPermission()) { reminders = false }
                        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
                        await Reminders.reschedule(all.recurring())
                    }
                }
            } header: {
                BoldHeader("Bills")
            } footer: {
                Text("A notification at 9 am the day before each subscription or bill.")
            }
            Section {
                Toggle(isOn: Binding(
                    get: { Reminders.paceAlertShownOn(stored: paceAlert, notificationsAllowed: notificationsAllowed) },
                    set: { on in
                        paceAlert = on
                        guard on else { return }
                        // The same ask as Remind Me the Day Before.
                        Task {
                            let allowed = await Reminders.requestPermission()
                            notificationsAllowed = allowed
                            if !allowed { notificationsBlocked = true }
                        }
                    })) {
                    Label("Budget Pace Alert", systemImage: "gauge.with.needle")
                }
            } header: {
                BoldHeader("Budget")
            } footer: {
                if notificationsAllowed {
                    Text("One alert a month if you're on track to pass your budget.")
                } else {
                    Text("Turn on notifications for Sortd in Settings to get this alert.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Bills & Reminders")
        // Back from the Settings app: the answer may have changed.
        .task(id: scenePhase) {
            if scenePhase == .active { notificationsAllowed = await Reminders.notificationsAllowed() }
        }
        .alert("Notifications are off for Sortd", isPresented: $notificationsBlocked) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Turn them on in the Settings app to get your reminders and alerts.")
        }
    }
}
