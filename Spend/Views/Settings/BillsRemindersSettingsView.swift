import SwiftUI
import SwiftData

/// Settings › Bills & Reminders: recurring subscriptions/bills and the
/// day-before notification.
struct BillsRemindersSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @State private var showingPaywall = false

    var body: some View {
        List {
            ListPageTitle(title: "Bills & Reminders", subtitle: "Subscriptions, bills, and the day-before nudge.")
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
        .sheet(isPresented: $showingPaywall) { ProPaywall(entry: .feature(.recurring)) }
    }
}
