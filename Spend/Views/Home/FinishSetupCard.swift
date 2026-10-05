import SwiftUI
import SwiftData
import WidgetKit

/// "Finish setup · 2 of 4 done" on Home: the same checklist as the plan at
/// the end of setup, ticking itself off from real data. Each row opens its
/// step. Hides itself once everything is done (or when hidden).
struct FinishSetupCard: View {
    /// Home with purchases lets people hide it; the empty Home always shows it.
    var canHide = true

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @AppStorage(SetupProfile.goalsKey) private var goalsRaw = ""
    @AppStorage(SetupProfile.paymentKey) private var paymentRaw = ""
    @AppStorage(SetupChecklist.hiddenKey) private var hidden = false
    @AppStorage(ApplePaySetupSteps.automationBuiltKey) private var automationBuilt = false
    /// Read so the card re-checks when the app comes back (the widget may
    /// have been added from the Home Screen meanwhile).
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0
    @State private var widgetAdded = false
    @State private var opening: SetupTask.Kind?

    private var tasks: [SetupTask] {
        let flow = SetupFlow(goals: SetupProfile.goals(goalsRaw), payment: SetupProfile.Payment(rawValue: paymentRaw),
                             hasCards: !CardBook.shared.active.isEmpty)
        let status = ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions)
        return SetupChecklist.tasks(flow: flow, hasCards: flow.hasCards,
                                    // A finished setup counts even before the first shop tap, but
                                    // only with all three steps done: the shortcut reaching the app
                                    // is steps 1 and 2, and step 3 is the one that logs.
                                    tapped: status.isConnected
                                        && !ApplePaySetupSteps.stepThreeLeft(status: status, saysBuilt: automationBuilt),
                                    widgetAdded: widgetAdded)
    }

    var body: some View {
        let _ = (scenePhase, refresh)
        let tasks = tasks
        if !SetupChecklist.isComplete(tasks), !(canHide && hidden) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Finish Setup").font(.headline)
                    Text("\(SetupChecklist.doneCount(tasks)) of \(tasks.count) done")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    if canHide {
                        Button("Hide") { withAnimation(.snappy) { hidden = true } }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                }
                SetupChecklistList(tasks: tasks) { opening = $0 }
                // The Apple Pay tip sits under the list as a card. As a popover on
                // the row it came loose and covered the row below (4 Oct 2026).
                if tasks.contains(where: { $0.kind == .applePay && !$0.done }) {
                    SortdTipView(tip: ApplePayTip())
                }
            }
            .task { await checkWidget() }
            .sheet(item: $opening, onDismiss: { refresh += 1; Task { await checkWidget() } }) { kind in
                switch kind {
                case .cards: NavigationStack { CardsSettingsView() }
                case .applePay: NavigationStack { SetupGuideView(isPresentedAsSheet: true) }
                case .widget: NavigationStack { WidgetsGuideView() }
                case .answers: EmptyView()
                }
            }
        }
    }

    private func checkWidget() async {
        let configs = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        widgetAdded = !configs.isEmpty
    }
}

extension SetupTask.Kind: Identifiable {
    var id: String { rawValue }
}
