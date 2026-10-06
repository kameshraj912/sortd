import SwiftUI
import SwiftData

/// "Apple Pay isn't logging yet" on Home: the shortcut has reached Sortd
/// (steps 1 and 2) but step 3, the one that makes logging automatic, is not
/// done (`ApplePaySetupSteps.stepThreeLeft`). On iOS 26 this is someone who
/// set up with an older build, whose automation runs the downloaded shortcut
/// and can't log (`resetOldIOS26Setup`): the button opens the by-hand
/// walk-through. Home says plainly that taps are not being written down. It
/// can't be hidden: it goes when the person finishes or a real tap lands.
struct ApplePayStepLeftCard: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @AppStorage(ApplePaySetupSteps.automationBuiltKey) private var automationBuilt = false
    /// Read so the card re-checks when the app comes back from Shortcuts.
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0
    @State private var showingGuide = false

    private var stepLeft: Bool {
        let status = ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions)
        return ApplePaySetupSteps.stepThreeLeft(status: status, saysBuilt: automationBuilt)
    }

    var body: some View {
        let _ = (scenePhase, refresh)
        if stepLeft {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ApplePaySetupSteps.stepThreeLeftTitle)
                            .font(.headline)
                        Text(ApplePaySetupSteps.stepThreeLeftLine())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    ApplePaySetupSteps.trackAction("finish_step_3_home", status: .shortcutReached(.now), saysBuilt: automationBuilt)
                    showingGuide = true
                } label: {
                    Text(ApplePaySetupSteps.stepThreeLeftButton())
                        .font(.headline)
                        .foregroundStyle(Color.onBrand)
                        .frame(maxWidth: .infinity, minHeight: ButtonMetrics.labelHeight)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.brand)
                .controlSize(.large)
            }
            .setupCard()
            .sheet(isPresented: $showingGuide, onDismiss: { refresh += 1 }) {
                // iOS 26: straight to the walk-through. iOS 27's step 3 is two
                // switches on the setup page.
                if ApplePaySetupSteps.route == .automation {
                    ApplePayAutomationGuide(steps: ApplePaySetupSteps.automationSteps, drawing: .automation)
                } else {
                    NavigationStack { SetupGuideView(isPresentedAsSheet: true) }
                }
            }
            .transition(.opacity)
        }
    }
}
