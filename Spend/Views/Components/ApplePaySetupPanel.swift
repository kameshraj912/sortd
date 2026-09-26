import SwiftUI

/// The Apple Pay Logging panel: the status card, "Get the Shortcut", the
/// picture guide, and the one line about Apple's own timeout. Used by the
/// setup step (`OnboardingView.applePay`) and by Settings › Purchase
/// Sources › Apple Pay Logging (`SetupGuideView`), so the two always agree
/// (spec 2026-09-25, option A: every state comes from a real event).
///
/// One path only: the ready-made shortcut and its one picture guide. There
/// is no by-hand walkthrough on this page any more (router feel check, 26
/// Sep 2026, "short and clean") — it moved to the website, see
/// `docs/site-copy-moved.md`.
struct ApplePaySetupPanel: View {
    let status: ApplePayStatus
    /// How many logged taps still need a look (spec 2026-09-26, failsafes
    /// #2/#10) — `ApplePayStatus.needsCheckCount`, computed by the caller
    /// (it already has the `@Query`).
    var needsCheckCount: Int = 0

    @Environment(\.openURL) private var openURL
    @State private var shortcutOpened = false
    /// A long-press on the status card reveals what Apple Pay last sent, in
    /// plain text — support staff point people to it. Kept out of the way
    /// so the page itself stays short (router feel check, 26 Sep 2026).
    @State private var showingRawTap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusCard
            if let line = ApplePayStatus.needsCheckLine(count: needsCheckCount) {
                Label(line, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            steps
            timeoutNote
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: status.symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 46, height: 46)
                .background(status.isConnected ? Color.up : Color.brand, in: .circle)
                .symbolEffect(.variableColor.iterative, isActive: !status.isConnected)
                .symbolEffect(.bounce, value: status.isConnected)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(.headline)
                Text(status.detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.isConnected ? Color.up.opacity(0.12) : Color.card, in: .rect(cornerRadius: 20, style: .continuous))
        .animation(.snappy, value: status)
        .feedback(.confirm, trigger: status)
        .contentShape(.rect)
        .onLongPressGesture {
            guard UserDefaults.standard.string(forKey: LogPurchaseIntent.lastTapKey) != nil else { return }
            showingRawTap = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
        .alert("Last Tap Received", isPresented: $showingRawTap) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(UserDefaults.standard.string(forKey: LogPurchaseIntent.lastTapKey) ?? "")
        }
    }

    // MARK: - The two steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            miniStep(1, "Add the Sortd shortcut", "Opens Safari, then tap the download and Add Shortcut.")
            Button {
                openURL(URL(string: "https://sortd.page/apple-pay.shortcut")!)
                shortcutOpened = true
            } label: {
                Label(shortcutOpened ? "Get It Again" : "Get the Shortcut", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .foregroundStyle(Color.onBrand)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.brand)
            .controlSize(.large)

            Divider()

            miniStep(2, "Turn it on for your cards", "Swipe through the pictures. They show every screen in Shortcuts.")
            if #available(iOS 27.0, *) {
                WalletSetupGuide(route: .quick)
            } else {
                legacySteps
            }
            Button {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            } label: {
                Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .setupCard()
    }

    /// Plain text before iOS 27: the picture guide is checked against the
    /// iOS 27 screens only (`WalletSetupGuide`'s own note).
    private var legacySteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.legacyStepLines, id: \.self) { line in
                Text(line).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static let legacyStepLines = [
        "Automation, then + · Wallet · tick your cards · Run Immediately.",
        "Create New Shortcut, search Sortd, add Log Wallet Tap.",
        "Fill in Amount, Shop and Card from the Shortcut Input.",
    ]

    private func miniStep(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 26, height: 26)
                .background(Color.ink, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Timeout note

    private var timeoutNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sortd sees when a tap arrives, not your automation.")
            Text("Apple's trigger sometimes misses a tap, most often at vending machines, transport gates and parking.")
                .fixedSize(horizontal: false, vertical: true)
            Link("Learn more", destination: ApplePayStatus.learnMoreURL)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.brand)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
