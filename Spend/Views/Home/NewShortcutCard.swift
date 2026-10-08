import SwiftUI
import SwiftData

/// "Get the new shortcut" (iOS 27) or "What's new for iOS 26" on Home, in the
/// place and style of "Apple Pay isn't logging yet" (`ApplePayStepLeftCard`).
/// For anyone who set up on an older build (`ApplePaySetupSteps
/// .needsNewShortcut`). Show Me How opens the Apple Pay setup page, where the
/// same card lists the steps; I've Done It hides it for good. While the
/// step-left card is up, this one waits: one card at a time, and that one
/// leads to the same page.
struct NewShortcutCard: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @AppStorage(ApplePaySetupSteps.automationBuiltKey) private var automationBuilt = false
    @AppStorage(ApplePaySetupSteps.shortcutVersionKey) private var storedVersion = 0
    /// Read so the card re-checks when the app comes back from Shortcuts.
    @Environment(\.scenePhase) private var scenePhase

    private let route = ApplePaySetupSteps.route

    private var status: ApplePayStatus {
        ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions)
    }

    private var due: Bool {
        let status = status
        guard !ApplePaySetupSteps.stepThreeLeft(status: status, saysBuilt: automationBuilt) else { return false }
        return ApplePaySetupSteps.needsNewShortcut(route: route, status: status, saysBuilt: automationBuilt, rawVersion: storedVersion)
    }

    var body: some View {
        let _ = scenePhase
        if due {
            let copy = ApplePaySetupSteps.newShortcutCopy(route: route)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: route == .shortcut ? "square.and.arrow.down.fill" : "sparkles")
                        .font(.title2)
                        .foregroundStyle(Color.brand)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.title)
                            .font(.headline)
                        Text(copy.line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    Router.shared.sheet = .applePaySetup
                } label: {
                    Text(copy.homeButton)
                        .font(.headline)
                        .foregroundStyle(Color.onBrand)
                        .frame(maxWidth: .infinity, minHeight: ButtonMetrics.labelHeight)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.brand)
                .controlSize(.large)
                Button {
                    ApplePaySetupSteps.trackNewShortcut(.done, route: route, status: status, saysBuilt: automationBuilt)
                    withAnimation(.snappy) { storedVersion = ApplePaySetupSteps.shortcutVersion }
                } label: {
                    Text(copy.doneButton)
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: ButtonMetrics.labelHeight)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .setupCard()
            .onAppear {
                ApplePaySetupSteps.trackNewShortcut(.shown, route: route, status: status, saysBuilt: automationBuilt)
            }
            .transition(.opacity)
        }
    }
}
