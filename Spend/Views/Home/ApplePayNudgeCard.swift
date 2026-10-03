import SwiftUI

/// "No Apple Pay taps for two weeks..." (spec 2026-09-26, failsafes #1/#3).
/// Fires once, then again only after another 14 days of silence — the same
/// rule as the quiet line on the Apple Pay Logging page
/// (`ApplePaySetupPanel`), which this card mirrors on Home. Reads
/// `LogPurchaseIntent`'s own UserDefaults keys directly (the same ones the
/// setup page and `ApplePayStatus` already use); no `@Query` needed, since
/// a real tap and a bare ▶ run both already update `lastTapReceivedAt`.
struct ApplePayNudgeCard: View {
    @State private var lastShownAt: Date? = ApplePayNudge.lastShown()
    @State private var dismissed = false

    private var due: Bool {
        !dismissed && ApplePayNudge.shouldShow(setupEverReached: LogPurchaseIntent.shortcutHasReachedApp,
                                               lastActivityAt: LogPurchaseIntent.lastTapReceivedAt,
                                               lastShownAt: lastShownAt)
    }

    var body: some View {
        if due {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wave.3.right.circle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(ApplePayNudge.line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss") {
                        withAnimation(.snappy) {
                            lastShownAt = ApplePayNudge.markShown()
                            dismissed = true
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brand)
                    .minTapTarget(growsBy: 24)
                }
            }
            .setupCard()
            .onAppear { if lastShownAt == nil { lastShownAt = ApplePayNudge.markShown() } }
            .transition(.opacity)
        }
    }
}
