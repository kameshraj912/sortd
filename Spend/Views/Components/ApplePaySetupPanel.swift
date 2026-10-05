import SwiftUI

/// The Apple Pay Logging panel: the status card, three numbered steps to
/// connect the ready-made shortcut, and the picture guide behind a
/// disclosure. Used by the setup step (`OnboardingView.applePay`) and by
/// Settings › Purchase Sources › Apple Pay Logging (`SetupGuideView`), so the
/// two always agree (spec 2026-09-25, option A: every state comes from a
/// real event).
///
/// Rewritten 27 Sep 2026: the shortcut at `sortd.page/apple-pay.shortcut` now
/// carries the whole automation (the Wallet trigger and Sortd's action, both
/// already filled in), so the old "make a Wallet automation by hand, then
/// add Run Shortcut" route no longer matches what iOS shows and is gone. All
/// that's left by hand is running the shortcut once (so iOS can ask
/// permission) and switching its own automation on. The by-hand build stays
/// as a smaller, collapsed fallback for when the download fails.
///
/// 5 Oct 2026: that is the iOS 27 route. On iOS 26 the shortcut can't work
/// (`ApplePaySetupSteps.Route`), so the panel shows the steps for the iOS it
/// is running on and nothing from the other route: there, one card that
/// opens the walk-through (`ApplePayAutomationGuide`).
struct ApplePaySetupPanel: View {
    let status: ApplePayStatus
    /// How many logged taps still need a look (spec 2026-09-26, failsafes
    /// #2/#10) — `ApplePayStatus.needsCheckCount`, computed by the caller
    /// (it already has the `@Query`).
    var needsCheckCount: Int = 0

    @Environment(\.openURL) private var openURL
    @State private var shortcutOpened = false
    /// One state each, so a tap on one never opens the other (seen on
    /// iOS 26.4 with no state of their own).
    @State private var showingHow = false
    @State private var showingByHand = false
    /// The shortcut file opens here, in Sortd's own Safari sheet, never the
    /// default browser.
    @State private var safariPage: SafariPage?
    /// A long-press on the status card reveals what Apple Pay last sent, in
    /// plain text — support staff point people to it. Kept out of the way
    /// so the page itself stays short (router feel check, 26 Sep 2026).
    @State private var showingRawTap = false

    /// Which steps the app can honestly tick off right now.
    private var ticked: ApplePaySetupSteps.Ticked { ApplePaySetupSteps.ticked(for: status) }

    @State private var healthCheck: ApplePayHealthCheck.State?
    @State private var healthCheckStartedAt: Date?
    /// `ApplePayNudge.lastShown()`/`markShown()` store a real `Date` in
    /// `UserDefaults` (matching `LogPurchaseIntent`'s own keys) — a plain
    /// `@State`, refreshed on appear, reads the same way rather than
    /// mismatching it against `@AppStorage`'s own numeric representation.
    @State private var nudgeLastShownAt: Date? = ApplePayNudge.lastShown()
    @State private var nudgeDismissed = false

    private let route = ApplePaySetupSteps.route

    /// iOS 27 has Wallet's Notification trigger, so the shortcut has two
    /// automations; earlier iOS only the tap.
    private var hasNotificationTrigger: Bool { route == .shortcut }

    @AppStorage(ApplePaySetupSteps.automationBuiltKey) private var automationBuilt = false
    @State private var showingAutomationGuide = false

    /// The card's words: the status's own, except while nothing is connected
    /// on the iOS 26 route (`ApplePaySetupSteps.card`).
    private var card: (title: String, detail: String) {
        ApplePaySetupSteps.card(for: status, route: route, saysBuilt: automationBuilt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            versionChip
            statusCard
            if let line = ApplePayStatus.needsCheckLine(count: needsCheckCount) {
                // Opens Activity, where the flagged rows carry a "Needs a
                // check" badge. During first-run setup there are no taps
                // yet, so this never shows there.
                Button {
                    openURL(URL(string: "sortd://activity")!)
                } label: {
                    Label(line, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens Activity")
            }
            switch route {
            case .shortcut:
                healthCheckSection
                steps
            case .automation:
                automationCard
            }
            scopeNote
            nudgeLine
        }
        .sheet(isPresented: $showingAutomationGuide) {
            ApplePayAutomationGuide()
        }
    }

    // MARK: - Which iOS these steps are for

    private var versionChip: some View {
        Label(ApplePaySetupSteps.versionLine(), systemImage: "checkmark")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.up)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.up.opacity(0.12), in: .capsule)
    }

    // MARK: - iOS 26: one card, and the walk-through behind it

    private var automationCard: some View {
        let allDone = ApplePaySetupSteps.ticked(for: status).turnOnAutomation
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("You set this up in Shortcuts")
                    .font(.headline)
                Text("On this iOS there is no shortcut to download. You make one small automation yourself. We show you every tap.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ApplePaySetupSteps.automationSteps) { step in
                    HStack(spacing: 12) {
                        stepBadge(step.id + 1, done: allDone)
                        Text(step.title).font(.subheadline)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(step.id + 1): \(step.title)\(allDone ? ". Done." : "")")
                }
            }

            // Done once, the button steps back: the card above is what to watch.
            Group {
                if automationBuilt {
                    guideButton.buttonStyle(.glass)
                } else {
                    guideButton.buttonStyle(.glassProminent).tint(Color.brand)
                }
            }
            .controlSize(.large)

            if automationBuilt, !status.isConnected {
                Text(ApplePaySetupSteps.automationTestLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .setupCard()
    }

    // MARK: - 14-day nudge (spec 2026-09-26, failsafes #1/#3)

    private var nudgeLine: some View {
        let everReached = LogPurchaseIntent.shortcutHasReachedApp
        let due = !nudgeDismissed && ApplePayNudge.shouldShow(setupEverReached: everReached,
                                                              lastActivityAt: LogPurchaseIntent.lastTapReceivedAt,
                                                              lastShownAt: nudgeLastShownAt)
        return Group {
            if due {
                HStack(alignment: .top, spacing: 8) {
                    Text(ApplePayNudge.line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss") {
                        nudgeLastShownAt = ApplePayNudge.markShown()
                        nudgeDismissed = true
                    }
                    .font(.caption.weight(.semibold))
                    .minTapTarget(growsBy: 28)
                }
                .onAppear { if nudgeLastShownAt == nil { nudgeLastShownAt = ApplePayNudge.markShown() } }
            }
        }
    }

    // MARK: - Check the Shortcut (spec 2026-09-26, failsafe #11)

    private var healthCheckSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                runHealthCheck()
            } label: {
                Label("Check the Shortcut", systemImage: "checkmark.shield")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            if let text = healthCheckText {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(healthCheck == .timedOut ? .secondary : Color.up)
                    .fixedSize(horizontal: false, vertical: true)
                if healthCheck == .timedOut {
                    Link("Learn more", destination: ApplePayStatus.learnMoreURL)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.brand)
                }
            }
        }
    }

    private var healthCheckText: String? {
        switch healthCheck {
        case nil: return nil
        case .waiting: return "Checking… run the automation from Shortcuts."
        case .reached(let date): return "Shortcut reached Sortd · \(date.formatted(date: .omitted, time: .shortened))"
        case .timedOut: return "Nothing arrived. Check the automation is on and set to Run Immediately."
        }
    }

    private func runHealthCheck() {
        guard let url = ApplePayHealthCheck.runURL else { return }
        let now = Date.now
        healthCheckStartedAt = now
        healthCheck = .waiting
        openURL(url)
        Task { await pollHealthCheck() }
    }

    /// Polls every second until the check resolves. Nothing runs unless a
    /// check is actually in progress (`healthCheckStartedAt` set by
    /// `runHealthCheck`); `ApplePayHealthCheck.resolve` itself is pure and
    /// tested with no sleeps at all.
    private func pollHealthCheck() async {
        guard let startedAt = healthCheckStartedAt else { return }
        while !Task.isCancelled {
            let state = ApplePayHealthCheck.resolve(startedAt: startedAt, lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, now: .now)
            healthCheck = state
            if state != .waiting { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: status.symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 46, height: 46)
                .background(status.isFlagged ? Color.orange : status.isConnected ? Color.up : Color.brand, in: .circle)
                .symbolEffect(.variableColor.iterative, isActive: !status.isConnected)
                .symbolEffect(.bounce, value: status.isConnected)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).font(.headline)
                Text(card.detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.isFlagged ? Color.orange.opacity(0.12) : status.isConnected ? Color.up.opacity(0.12) : Color.card, in: .rect(cornerRadius: 20, style: .continuous))
        .animation(.snappy, value: status)
        .feedback(.confirm, trigger: status)
        .contentShape(.rect)
        .onLongPressGesture {
            guard UserDefaults.standard.string(forKey: LogPurchaseIntent.lastTapKey) != nil else { return }
            showingRawTap = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status == .notConnected ? "\(card.title). \(card.detail)" : status.accessibilityLabel)
        .sheet(item: $safariPage) { page in
            SafariSheet(url: page.url).ignoresSafeArea()
        }
        .alert("Last Tap Received", isPresented: $showingRawTap) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(UserDefaults.standard.string(forKey: LogPurchaseIntent.lastTapKey) ?? "")
        }
    }

    // MARK: - The three steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(1, ticked.addShortcut, "Add the shortcut", "Opens Shortcuts. Tap Add Shortcut.")
            Button {
                shortcutOpened = true
                safariPage = SafariPage(url: ApplePaySetupSteps.shortcutURL)
            } label: {
                Label(shortcutOpened ? "Get It Again" : "Get the Shortcut", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .foregroundStyle(Color.onBrand)
                    .frame(maxWidth: .infinity, minHeight: ButtonMetrics.labelHeight)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.brand)
            .controlSize(.large)

            // What the Safari sheet shows for the file (checked on the iOS 27
            // simulator, 4 Oct 2026): a file card with "Open in Shortcuts".
            Text("A page opens. Tap Open in \u{201C}Shortcuts\u{201D}.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            stepRow(2, ticked.runAndAllow, ApplePaySetupSteps.runStep.title, ApplePaySetupSteps.runStep.detail)
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

            Divider()

            let automation = ApplePaySetupSteps.automationStep(notificationTrigger: hasNotificationTrigger)
            stepRow(3, ticked.turnOnAutomation, automation.title, automation.detail)

            DisclosureGroup("Show me how", isExpanded: $showingHow) {
                Group {
                    if #available(iOS 27.0, *) {
                        WalletSetupGuide(route: .quick)
                    } else {
                        legacySteps
                    }
                }
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
            .tint(Color.ink)

            DisclosureGroup("Build it by hand instead", isExpanded: $showingByHand) {
                WalletSetupGuide(route: .byHand)
                    .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
            .tint(Color.ink)
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
        "Add the shortcut: opens Shortcuts, tap Add Shortcut.",
        "Run it once. Tap Allow when Shortcuts asks.",
        "Tap › next to “tapped”, then switch on Automation.",
    ]

    /// One numbered step. Ticks itself green once `done` is true — steps 1
    /// and 3 can't be seen on their own, so `ticked` (`ApplePaySetupSteps`)
    /// decides which ones light up for the current status.
    private func stepRow(_ n: Int, _ done: Bool, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(n, done: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(n): \(title). \(detail)\(done ? ". Done." : "")")
    }

    private var guideButton: some View {
        Button {
            showingAutomationGuide = true
        } label: {
            Label(automationBuilt ? "Go Through the Steps Again" : "Show Me Step by Step",
                  systemImage: "list.number")
                .font(.headline)
                .foregroundStyle(automationBuilt ? Color.ink : Color.onBrand)
                .frame(maxWidth: .infinity, minHeight: ButtonMetrics.labelHeight)
        }
    }

    /// The number in its circle, or a green tick once the step is done.
    private func stepBadge(_ n: Int, done: Bool) -> some View {
        Group {
            if done {
                Image(systemName: "checkmark").font(.subheadline.weight(.bold))
            } else {
                Text("\(n)").font(.subheadline.weight(.bold))
            }
        }
        .foregroundStyle(Color.onBrand)
        .frame(width: 26, height: 26)
        .background(done ? Color.up : Color.ink, in: .circle)
        .accessibilityHidden(true)
    }

    // MARK: - Scope

    /// What the shortcut can and can't see — replaces the longer timeout
    /// paragraph that used to sit here (router feel check, 27 Sep 2026:
    /// this screen carried the same steps three times over).
    private var scopeNote: some View {
        Text(ApplePaySetupSteps.scopeLine(notificationTrigger: hasNotificationTrigger))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
