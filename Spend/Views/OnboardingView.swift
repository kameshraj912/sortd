import SwiftUI
import SwiftData
import UserNotifications

/// First launch: a short guided setup. Everything that can be filled in for
/// the user is (currency from the phone, bank details from a preset list),
/// every step can be skipped, and anything skipped can be done later in
/// Settings. Apple Pay setup checks itself: it turns green on the first tap.
struct OnboardingView: View {
    /// Called when setup is finished. RootView needs this because with
    /// SPEND_ONBOARD_STEP set it forces the cover open, so watching the
    /// "done" flag alone left the last button looking broken.
    var onFinish: () -> Void = {}

    static let doneKey = "onboardingDone"

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @AppStorage(Money.homeKey) private var home = Money.detectedHome
    @AppStorage("monthlyBudget") private var budget: Double = 0
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @AppStorage(OnboardingView.doneKey) private var done = false
    // What they tell us about themselves. Kept on this iPhone.
    @AppStorage(SetupProfile.goalsKey) private var goalsRaw = ""
    @AppStorage(SetupProfile.paymentKey) private var paymentRaw = ""
    @AppStorage(SetupProfile.checkInKey) private var checkInRaw = SetupProfile.CheckIn.sunday.rawValue
    @AppStorage(SetupProfile.billsKey) private var billIntent = false
    @AppStorage(SetupProfile.rerunKey) private var rerun = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// They answered the check-in question this time (not skipped, not "Not now").
    @State private var checkInChosen = false
    /// Asking iOS for notification permission; one tap is enough.
    @State private var requesting = false
    /// Notifications aren't allowed, so no check-in will come: the building
    /// and plan pages say so instead of promising one.
    @State private var notificationsOff = false
    /// When the step last changed. A double tap on a bottom button would
    /// otherwise land its second tap on the next screen's button in the same
    /// spot (e.g. skip Apple Pay by accident).
    @State private var stepChangedAt = Date.distantPast
    /// finish() has run: ignore every tap after that.
    @State private var finished = false
    /// The payment question just picked an answer and is about to advance by
    /// itself: Continue, Back and Skip are all ignored until it does, so a
    /// second tap can't advance twice and skip a question.
    @State private var autoAdvancing = false
    /// "Bring in past spending" / "Restore from iCloud" on the welcome
    /// screen: one plain-text link opens both, instead of a row each.
    /// The `.account` step: who just signed in, shown for a moment before
    /// moving on by itself. Nil for the sign-in buttons.
    @State private var accountConfirmed: String?
    /// The `.account` step: a sign-in failure, in the same words
    /// AccountSettingsView shows. A cancel never sets this.
    @State private var accountError: String?
    /// The `.account` step's way through, for `setup_step_completed`'s
    /// `choice` property: apple, google or guest. Cleared once sent.
    @State private var accountChoice: String?
    /// Each new step opens at the top, title in view.
    @State private var scroll = ScrollPosition(edge: .top)
    /// The budget before setup started, so un-ticking "Spend less" undoes
    /// a limit set a moment ago without wiping one set weeks ago.
    @State private var budgetBefore: Double?
    /// For analytics: how many steps this run showed, and whether Skip was
    /// used. Never what was answered.
    @State private var stepsSeen = 0
    @State private var usedSkip = false
    #if SORTD_ICLOUD
    /// "Restore from iCloud" on the welcome screen (new flow): what happened.
    @State private var restoring = false
    @State private var restoreNote: String?
    #endif

    typealias Step = SetupFlow.Step
    #if DEBUG
    @State private var step: Step = Step(rawValue: Int(ProcessInfo.processInfo.environment["SPEND_ONBOARD_STEP"] ?? "") ?? 0) ?? .welcome
    #else
    @State private var step: Step = .welcome
    #endif
    /// Reduce Motion or Prefer Cross-Fade Transitions: no sliding. One
    /// implementation for the whole app, in `Feedback.swift`.
    @Environment(\.crossFades) private var crossFade

    @State private var showingImport = false
    @State private var forward = true
    @State private var customBudget = ""
    @State private var bankCountry: String = Locale.current.region?.identifier ?? "AU"
    @State private var editing: CardInfo?
    @State private var connectingGmail = false
    @State private var gmail = GmailSync.accounts
    /// "S$25.00 ≈ A$28.40 today", once a rate has come in.
    @State private var ratePreview: String?
    @FocusState private var budgetFocused: Bool
    /// The budget amount grows with the text-size setting, within reason.
    @ScaledMetric(relativeTo: .largeTitle) private var budgetAmountSize: CGFloat = 52
    @ScaledMetric(relativeTo: .title) private var budgetSymbolSize: CGFloat = 30

    private var book: CardBook { .shared }
    private var region: String { Locale.current.region?.identifier ?? "AU" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
            page
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .id(step)
                // Sliding pages are exactly what "Prefer Cross-Fade
                // Transitions" asks apps not to do; fade instead of moving.
                .transition(crossFade
                    ? .opacity
                    : .asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            if typeSize.isAccessibilitySize, step != .building { bottomBar }
            }
        }
        .scrollPosition($scroll)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        // Text scrolling under Back / progress / Skip fades out under the bar,
        // the way Home and Insights do. `.hard` drew a hairline (Raj, 27 Sep).
        .scrollEdgeEffectStyle(.soft, for: .top)
        // Glass controls float over the page, and the page scrolls under them.
        // Bars (not plain insets) so the page blurs softly under them as it
        // scrolls, instead of text running into the buttons.
        .safeAreaBar(edge: .top, spacing: 0) { topBar }
        .safeAreaBar(edge: .bottom, spacing: 0) { if step != .building, !typeSize.isAccessibilitySize { bottomBar } }
        .onAppear {
            if budgetBefore == nil { budgetBefore = budget }
            // Once per run of setup (a re-run from Settings counts as a run).
            if stepsSeen == 0 {
                stepsSeen = 1
                Analytics.shared.track(.setupStarted, ["rerun": .bool(rerun)])
            }
        }
        // A budget already set (Run Setup Again) is in the old currency.
        // Convert it now, so the budget step and the plan show what will be
        // saved, not the old number with a new symbol.
        .onChange(of: home) { _, new in rebaseForSetup(to: new) }
        .background {
            ZStack {
                Color.page.ignoresSafeArea()
                if step == .welcome || step == .building || step == .plan {
                    SetupAura().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: step)
        }
        // The `.cards` step's disclosure: nickname and debit/credit for one
        // card, no digits (those stay in Settings › Cards, sub-spec free-app
        // overhaul UX pass).
        .sheet(item: $editing) { info in
            NavigationStack {
                ScrollView { CardDetailForm(info: info).padding(20) }
                    .background(Color.page)
                    .navigationTitle(rowTitle(info))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = nil } }
                    }
            }
        }
        .onChange(of: SyncStatus.gmail.phase) { gmail = GmailSync.accounts }
        .sheet(isPresented: $connectingGmail, onDismiss: { gmail = GmailSync.accounts }) { ConnectGmailSheet() }
        .sheet(isPresented: $showingImport) { NavigationStack { ImportView() } }
        #if SORTD_ICLOUD
        .alert("Restore from iCloud", isPresented: Binding(get: { restoreNote != nil }, set: { if !$0 { restoreNote = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreNote ?? "")
        }
        #endif
        .feedback(.select, trigger: step)
        .onChange(of: step) {
            stepChangedAt = .now
            scroll.scrollTo(edge: .top)
        }
        // Where people get to, for the drop-off funnel: the step's name and
        // place, never an answer. `initial` counts the first screen.
        .onChange(of: step, initial: true) {
            Analytics.shared.track(.setupStepViewed, ["step": .string(String(describing: step)),
                                                      "index": .int(step.rawValue)])
        }
        // The real permission, for the building and plan text (it may have
        // been turned off in Settings, or asked in an earlier setup).
        .task(id: step) {
            guard step == .building || step == .plan else { return }
            notificationsOff = !(await Self.notificationsAllowed())
        }
    }

    /// True just after a step change, for good once setup has finished, and
    /// while the payment question is auto-advancing after a pick.
    private var tapsLocked: Bool {
        finished || autoAdvancing || Date.now.timeIntervalSince(stepChangedAt) < 0.4
    }

    /// The check-in that will actually be saved: skipped or never answered
    /// means none (as finish() does), and none without notifications.
    private var effectiveCheckIn: SetupProfile.CheckIn {
        if !checkInChosen, UserDefaults.standard.string(forKey: SetupProfile.checkInKey) == nil { return .needed }
        return checkIn
    }

    static func notificationsAllowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// The check-in line for the building and plan pages.
    private var checkInLine: (symbol: String, text: String) {
        let choice = effectiveCheckIn
        if choice != .needed, notificationsOff {
            // New flow: nothing has asked yet, so "off" would be wrong. The
            // aha card on Home asks, once.
            if newFlow {
                return ("bell", choice == .sunday ? "We'll ask about a Sunday recap later"
                                                  : "We'll ask about check-ins later")
            }
            return ("bell.slash", "Check-ins off (notifications are off)")
        }
        return (choice.symbol, choice == .needed ? "No regular check-ins" : choice.summary)
    }

    // MARK: Answers

    private var goals: Set<SetupProfile.Goal> { SetupProfile.goals(goalsRaw) }
    private var payment: SetupProfile.Payment? { SetupProfile.Payment(rawValue: paymentRaw) }
    private var checkIn: SetupProfile.CheckIn { SetupProfile.CheckIn(rawValue: checkInRaw) ?? .sunday }
    private var flow: SetupFlow {
        SetupFlow(goals: goals, payment: payment, hasCards: !book.active.isEmpty,
                  gmailFeature: Features.gmail, signInFeature: Features.signIn)
    }
    private var wantsGmail: Bool { flow.wantsGmail }
    /// Tap-through setup (sub-spec 6): Continue everywhere, no permission
    /// alert until the aha card on Home. See `SetupFlow.usesNewFlow`.
    private var newFlow: Bool { SetupFlow.usesNewFlow }
    /// The check-in step asks for notifications only if something will use
    /// them, and never in the new flow (the ask moved to Home).
    private var asksNotifications: Bool { !newFlow && (checkIn != .needed || billIntent) }

    private var goalsBinding: Binding<Set<SetupProfile.Goal>> {
        Binding(get: { goals }, set: { goalsRaw = SetupProfile.raw($0) })
    }
    private var paymentBinding: Binding<SetupProfile.Payment?> {
        // A pick starts the auto-advance: lock the buttons until `go(_:)`
        // clears it, so a fast second tap can't advance twice.
        Binding(get: { payment }, set: { paymentRaw = $0?.rawValue ?? ""; if $0 != nil { autoAdvancing = true } })
    }
    private var checkInBinding: Binding<SetupProfile.CheckIn> {
        Binding(get: { checkIn }, set: { checkInRaw = $0.rawValue })
    }

    // MARK: Flow

    private func isShown(_ s: Step) -> Bool { flow.isShown(s) }
    private func neighbour(of s: Step, _ delta: Int) -> Step? { flow.neighbour(of: s, delta) }
    private var progress: Double { flow.progress(at: step) }
    private var questionSteps: [Step] { flow.questionSteps }
    private func counter(_ s: Step) -> String { flow.counter(s) ?? "" }

    private var topBar: some View {
        HStack(spacing: 12) {
            if step == .welcome, rerun {
                // Running setup again from Settings: a way back out.
                Button {
                    rerun = false
                    onFinish()
                } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close")
            } else if step != .welcome && step != .building {
                Button { if !tapsLocked { go(-1) } } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Back")
            } else {
                placeholderCircle
            }
            // One bar that fills, counting only steps this person will see.
            Capsule()
                .fill(Color.track)
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule()
                            .fill(LinearGradient(colors: Color.brandPalette, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(5, g.size.width * progress))
                    }
                }
                .clipShape(.capsule)
                .animation(.snappy, value: progress)
                .opacity(step == .welcome || step == .building ? 0 : 1)
                .accessibilityHidden(true)
            if questionSteps.contains(step) {
                // Straight to the plan with sensible defaults.
                Button("Skip") {
                    guard !tapsLocked else { return }
                    budgetFocused = false
                    forward = true
                    usedSkip = true
                    stepDone(step, skipped: true)
                    withAnimation(.snappy) { step = .plan }
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.glass)
            } else {
                placeholderCircle
            }
        }
        .tint(Color.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// An invisible copy of the round back button, so the progress bar
    /// stays put on steps with nothing on one side.
    private var placeholderCircle: some View {
        Button {} label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .hidden()
            .accessibilityHidden(true)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { if !tapsLocked { action() } } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.onBrand)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.brand)
        .controlSize(.large)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { if !tapsLocked { action() } } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    /// Quiet text button under the main one. 44pt tall: Apple's minimum.
    private func tertiaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { if !tapsLocked { action() } } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                switch step {
                case .welcome:
                    primaryButton(primaryTitle, action: primaryAction)
                    // Not when setup is run again: sample data would mix into
                    // real purchases, and its Clear forces a full setup.
                    if transactions.isEmpty, !rerun {
                        secondaryButton("Look Around With Sample Data") {
                            DemoData.load(in: context)
                            finish()
                        }
                    }
                    // The two less-common ways in, as a menu on the link itself
                    // so it opens next to it (a dialog on the page anchored
                    // top-left, Raj, 27 Sep).
                    Menu {
                        Button("Bring in past spending", systemImage: "square.and.arrow.down") { showingImport = true }
                        #if SORTD_ICLOUD
                        if transactions.isEmpty, !rerun {
                            Button(restoring ? "Restoring…" : "Restore from iCloud", systemImage: "icloud.and.arrow.down") { restoreFromCloud() }
                                .disabled(restoring)
                        }
                        #endif
                    } label: {
                        Text("More Options")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Text("Free. No account needed.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, -2)
                case .account:
                    // Same spot as Continue on every other step (Raj, 27 Sep).
                    // Once signed in, the page shows the confirmation and the
                    // bar empties for the moment before it moves on.
                    if accountConfirmed == nil {
                        SignInButtons(onSignedIn: accountSignedIn) { accountError = $0 }
                        tertiaryButton("Continue as guest", action: continueAsGuest)
                        Text("You can sign in later in Settings › Account.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, -2)
                    }
                case .plan:
                    primaryButton(primaryTitle, action: primaryAction)
                    // New flow: the chores wait in the Finish Setup card on Home.
                    tertiaryButton(newFlow ? "Do this later" : "Do this later and look around") { finish() }
                case .email where gmail.isEmpty && newFlow:
                    primaryButton(primaryTitle, action: primaryAction)
                    secondaryButton("Connect Gmail") { connectingGmail = true }
                case .email where gmail.isEmpty:
                    primaryButton("Connect Gmail") { connectingGmail = true }
                    tertiaryButton("I'll do this later") { go(1) }
                case .applePay where !tapConnected && !shortcutReached && !newFlow:
                    primaryButton("Open Shortcuts") {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    }
                    tertiaryButton("I'll do this later") { go(1) }
                case .checkIn where asksNotifications:
                    primaryButton(primaryTitle, action: primaryAction)
                    tertiaryButton("Not now") {
                        // No notifications: no check-in, no bill reminders,
                        // and the aha card never asks again (research 03 §9).
                        checkInRaw = SetupProfile.CheckIn.needed.rawValue
                        billIntent = false
                        checkInChosen = true
                        Activation.markNotificationAsked()
                        go(1)
                    }
                default:
                    primaryButton(primaryTitle, action: primaryAction)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .padding(.top, 8)
    }

    private var primaryTitle: String {
        // New flow: one word on every step. Skipping is just continuing,
        // with the defaults (`SetupFlow.defaults`) left in place.
        if newFlow { return step == .welcome ? "Get Started" : "Continue" }
        let last = neighbour(of: step, 1) == nil
        switch step {
        case .welcome: return "Get Started"
        case .payment where payment == nil: return "Skip This One"
        case .checkIn: return asksNotifications ? "Turn On Notifications" : "Continue"
        case .plan: return book.active.isEmpty ? "Add My First Card" : "Continue Setup"
        case .cards where book.active.isEmpty: return "Add Cards Later"
        case .applePay where !tapConnected && !shortcutReached:
            return last ? "Do This Later and Start" : "I'll Do This Later"
        case .email where gmail.isEmpty: return "I'll Do This Later"
        default: return last ? "Start Using Sortd" : "Continue"
        }
    }

    private func primaryAction() {
        guard !finished else { return }
        // New flow: Continue past a question nobody answered is a skip, so
        // setup_finished(skipped) means the same thing in both flows.
        if newFlow, untouched(step) { usedSkip = true }
        if step == .checkIn {
            checkInRaw = checkIn.rawValue   // keep the pre-picked default too
            checkInChosen = true
            if asksNotifications {
                // One button, straight to Apple's own alert (no fake "Allow").
                guard !requesting else { return }
                requesting = true
                let from = step
                Task {
                    let allowed = await Reminders.requestPermission()
                    let actual = await Self.notificationsAllowed()
                    notificationsOff = !(allowed || actual)
                    // Asked here: the aha card must never ask a second time.
                    Activation.markNotificationAsked()
                    requesting = false
                    if step == from { go(1) }
                }
                return
            }
        }
        go(1)
    }

    /// A question left as it was: no goal, no payment, no limit. Currency
    /// and check-in always hold a default, so they never count.
    private func untouched(_ s: Step) -> Bool {
        switch s {
        case .goals: goals.isEmpty
        case .payment: payment == nil
        case .budget: budget == 0
        default: false
        }
    }

    private func go(_ delta: Int) {
        guard !finished else { return }
        autoAdvancing = false
        budgetFocused = false
        forward = delta > 0
        guard let next = neighbour(of: step, delta) else {
            if delta > 0 { finish() }
            return
        }
        if delta > 0 { stepDone(step, skipped: newFlow && untouched(step)) }
        withAnimation(.snappy) { step = next }
    }

    /// Which step was left going forward: the step's name and place, never
    /// an answer. Where people stop is what the funnel is for.
    private func stepDone(_ s: Step, skipped: Bool = false) {
        stepsSeen += 1
        var props: [String: Analytics.AnalyticsValue] = ["step": .string(String(describing: s)),
                                                          "index": .int(s.rawValue), "skipped": .bool(skipped)]
        // The `.account` step's own way through: apple, google or guest.
        if s == .account, let choice = accountChoice { props["choice"] = .string(choice) }
        accountChoice = nil
        Analytics.shared.track(.setupStepCompleted, props)
    }

    /// Converts the saved budget (and category limits) to the new home
    /// currency straight away. FXService runs one rebase at a time, so
    /// flicking between currencies can't convert twice.
    private func rebaseForSetup(to new: String) {
        let beforeRebase = budget
        Task {
            await FXService.rebase(to: new, in: context)
            // Picked another currency while this one ran: that call updates.
            guard home == new else { return }
            let after = UserDefaults.standard.double(forKey: FXService.budgetKey)
            // Keep the "undo" value in step with the budget it came from.
            if let before = budgetBefore, before > 0 {
                if before == beforeRebase {
                    budgetBefore = after
                } else if beforeRebase > 0, after > 0 {
                    budgetBefore = FXService.convertSetting(before, rate: after / beforeRebase)
                }
            }
            customBudget = BudgetSheet.text(for: after, currency: new)
        }
    }

    private func finish() {
        // Once only: a second tap must not run setup's ending again.
        guard !finished else { return }
        finished = true
        Task { await FXService.rebase(to: home, in: context) }
        // Skipped the question: keep an earlier answer. Otherwise the old
        // flow saves no check-in; the new flow saves the default (Sunday),
        // to be scheduled once the aha card on Home gets a yes.
        if !checkInChosen, UserDefaults.standard.string(forKey: SetupProfile.checkInKey) == nil {
            checkInRaw = (newFlow ? SetupFlow.defaults(locale: .current).checkIn : .needed).rawValue
        }
        // A limit set a moment ago, then "Spend less" un-ticked: undo it.
        if !goals.contains(.spendLess), let before = budgetBefore { budget = before }
        let choice = checkIn
        let keepUnscheduled = newFlow
        Task {
            // Only if notifications are allowed; otherwise clear any old one,
            // and say so in Settings rather than show a time that never comes.
            // The new flow keeps the answer: nothing has asked yet, and the
            // aha card on Home will.
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            let allowed = status == .authorized || status == .provisional
            await CheckInReminder.schedule(allowed ? choice : .needed)
            if !allowed, !keepUnscheduled {
                UserDefaults.standard.set(SetupProfile.CheckIn.needed.rawValue, forKey: SetupProfile.checkInKey)
            }
        }
        if billIntent {
            reminders = true
            billIntent = false
        }
        rerun = false
        done = true
        Analytics.shared.track(.setupFinished, ["skipped": .bool(usedSkip), "steps_seen": .int(stepsSeen)])
        onFinish()
    }

    #if SORTD_ICLOUD
    /// Puts the iCloud copy back (adding what's missing) and says what came
    /// back. Setup carries on after: the answers aren't in the backup.
    private func restoreFromCloud() {
        guard !restoring else { return }
        restoring = true
        Task {
            defer { restoring = false }
            do {
                guard let added = try await CloudBackup.shared.restoreIfPresent(into: context, mode: .merge) else {
                    restoreNote = "No backup in iCloud yet. Turn on Back up to iCloud on the iPhone that has your purchases."
                    return
                }
                Task { await FXService.backfill(in: context) }
                let badDates = CloudBackup.shared.lastRestoreBadDates
                if badDates > 0 {
                    restoreNote = "\(added) purchase\(added == 1 ? "" : "s") back. \(Backup.badDatesNote(badDates)). Carry on with setup."
                } else {
                    restoreNote = added == 0 ? "Nothing to add. Everything in the backup is already here."
                        : "\(added) purchase\(added == 1 ? "" : "s") back. Carry on with setup."
                }
            } catch {
                restoreNote = error.localizedDescription
            }
        }
    }
    #endif

    /// The limit that will actually be in place when setup ends.
    private var effectiveBudget: Double {
        goals.contains(.spendLess) ? budget : (budgetBefore ?? 0)
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .account: accountPage
        case .goals: GoalsPage(counter: counter(.goals), goals: goalsBinding)
        case .payment: PaymentPage(counter: counter(.payment), payment: paymentBinding) { if step == .payment { go(1) } }
        case .currency: currency
        case .budget: budgetPage
        // New flow: no bill toggle here; it would need the permission this
        // flow no longer asks for. Settings › Bills & reminders asks then.
        case .checkIn: CheckInPage(counter: counter(.checkIn), checkIn: checkInBinding, billReminders: $billIntent,
                                   showBills: !newFlow)
        case .building: BuildingPage(lines: buildingLines) { if step == .building { go(1) } }
        case .plan: PlanPage(summary: planSummary, tasks: setupTasks, settings: planSettings)
        case .cards: cards
        case .applePay: applePay
        case .email: emailPage
        }
    }

    // MARK: What the answers built

    private var buildingLines: [String] {
        var lines = ["Showing totals in \(home)"
                     + (goals.contains(.countries) ? ", other currencies converted each day" : "")]
        if goals.contains(.spendLess), effectiveBudget > 0 {
            lines.append("Setting a \(Money.format(Decimal(effectiveBudget), home, cents: false)) monthly limit, with what's left each day")
        } else if goals.contains(.bills) {
            lines.append("Watching for subscriptions and bills")
        } else {
            lines.append("Putting where your money goes first")
        }
        lines.append(checkInLine.text)
        lines.append(SetupCopy.buildingPrivacy)
        return lines
    }

    private var planSummary: String { SetupCopy.line(.plan) ?? "" }

    private var planSettings: [(String, String)] {
        var chips = [(Self.currencySymbol(home), "Totals in \(home)"
                      + (goals.contains(.countries) ? ", others converted daily" : ""))]
        if effectiveBudget > 0 { chips.append(("gauge.with.dots.needle.33percent", Money.format(Decimal(effectiveBudget), home, cents: false) + " monthly limit")) }
        chips.append((checkInLine.symbol, checkInLine.text))
        if billIntent { chips.append(("bell.badge", "Bill heads-ups")) }
        return chips
    }

    private var setupTasks: [SetupTask] {
        SetupChecklist.tasks(flow: flow, hasCards: !book.active.isEmpty,
                             tapped: applePayStatus.isConnected,
                             widgetAdded: false, gmailConnected: !gmail.isEmpty)
    }

    private func header(_ title: String, _ subtitle: String? = nil) -> some View {
        SetupHeader(title: title, subtitle: subtitle)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image("BrandIcon")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 15, style: .continuous))
                // The icon is black: an edge keeps its shape on a dark page.
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                .padding(.top, 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                // Wordmark: lowercase, heavy, tight, with the four category colours under it.
                VStack(alignment: .leading, spacing: 6) {
                    Text("sortd")
                        .font(.system(size: 40, weight: .heavy))
                        .tracking(-1.2)
                    HStack(spacing: 3) {
                        ForEach([SpendCategory.foodDelivery, .eatingOut, .subscriptions, .groceries], id: \.self) {
                            Capsule().fill($0.color).frame(width: 22, height: 4)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sortd")
                Text(SetupCopy.line(.welcome) ?? "")
                    .font(.body).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("wave.3.right", "Apple Pay logs itself", "Pay as usual. It shows up in a second.", Color.brandPalette[0])
                feature("arrow.triangle.2.circlepath", "Bills before they hit", "Know what's due before it's charged.", Color.brandPalette[2])
                feature("lock", SetupCopy.welcomePrivacy.title, SetupCopy.welcomePrivacy.detail, Color.brandPalette[3])
            }
            .setupCard(padding: 20)
        }
    }

    /// Optional sign-in (sub-spec 4): the only steps through are Apple,
    /// Google, or guest, so there's no "Continue" to disable by accident
    /// (`bottomBar` leaves this step out).
    private var accountPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keep it yours.").font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                BrandBar(width: 14, height: 3)
                Text("Optional. Two taps, no password.")
                    .font(.body).foregroundStyle(.secondary)
            }
            // What signing in is for, in the same three-row card as Welcome,
            // so the page carries its weight instead of floating three buttons.
            VStack(alignment: .leading, spacing: 14) {
                feature("person.crop.circle.badge.checkmark", "Help that knows you", "Ask a question and Sortd knows which install is yours.", Color.brandPalette[0])
                feature("icloud", "Your iCloud copy, tied to you", "Restore on a new iPhone with one tap.", Color.brandPalette[2])
                feature("lock", "Nothing else changes", "Your purchases stay on this iPhone. Signing in doesn't change that.", Color.brandPalette[3])
            }
            .setupCard()
            if let accountConfirmed {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.up)
                    Text("Signed in as \(accountConfirmed)").font(.body.weight(.medium)).foregroundStyle(Color.ink)
                }
                .setupCard()
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .feedback(.confirm, trigger: accountConfirmed)
        .alert("Sign-in didn't work", isPresented: Binding(get: { accountError != nil }, set: { if !$0 { accountError = nil } })) {
            Button("OK") {}
        } message: {
            Text(accountError ?? "")
        }
    }

    /// Apple or Google succeeded: a brief haptic, "Signed in as …" for a
    /// moment, then the same forward move as any other step.
    private func accountSignedIn(_ account: Account) {
        guard step == .account else { return }
        accountChoice = account.provider == .apple ? "apple" : "google"
        withAnimation(.snappy) { accountConfirmed = account.email ?? account.provider.name }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard step == .account else { return }
            go(1)
        }
    }

    private func continueAsGuest() {
        accountChoice = "guest"
        go(1)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var currency: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter(.currency), title: "Your main currency",
                        // "We picked the one your iPhone uses" only while
                        // that is still true.
                        subtitle: home == Money.detectedHome ? SetupCopy.line(.currency) : SetupCopy.currencyPicked)
            VStack(spacing: 10) {
                ForEach(currencyChoices, id: \.self) { code in
                    OptionCard(symbol: Self.currencySymbol(code), title: "\(code) · \(name(of: code))",
                               detail: code == Money.detectedHome ? "From your iPhone" : nil,
                               selected: home == code) {
                        withAnimation(.snappy) { home = code }
                    }
                }
                Menu {
                    ForEach(Money.supported, id: \.self) { code in
                        Button("\(code) · \(name(of: code))") { withAnimation(.snappy) { home = code } }
                    }
                } label: {
                    HStack(spacing: 12) {
                        RowIcon("globe")
                        Text("Other currencies").font(.body).foregroundStyle(Color.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
                }
            }

            if let ratePreview {
                HStack(spacing: 12) {
                    RowIcon("arrow.left.arrow.right")
                    Text(ratePreview).font(.body).monospacedDigit()
                }
                .setupCard()
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .task(id: home) { await loadRatePreview() }
    }

    /// A live conversion, so the currency choice already does something.
    private func loadRatePreview() async {
        let other = home == "SGD" ? "AUD" : home == "AUD" ? "SGD" : "USD"
        guard other != home, let rate = try? await FXService.latestRate(from: other, to: home) else { return }
        let converted = Decimal(25 * rate)
        withAnimation(.snappy) {
            // Codes, not symbols: "$" alone doesn't say which dollar.
            let fmt = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
            ratePreview = "25.00 \(other) ≈ \(NSDecimalNumber(decimal: converted).doubleValue.formatted(fmt)) \(home) today"
        }
    }

    private func name(of code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

    /// The phone's currency and three common ones, plus whatever was picked
    /// from "Other currencies", so the choice is always on screen.
    private var currencyChoices: [String] {
        var list = [Money.detectedHome]
        list += ["AUD", "SGD", "USD", "INR", "GBP"].filter { $0 != Money.detectedHome }.prefix(3)
        if !list.contains(home) { list.insert(home, at: 0) }
        return list
    }

    static func currencySymbol(_ code: String) -> String {
        switch code {
        case "GBP": "sterlingsign.circle"
        case "EUR": "eurosign.circle"
        case "INR": "indianrupeesign.circle"
        case "JPY", "CNY": "yensign.circle"
        case "MYR": "malaysianringgitsign.circle"
        case "KRW": "wonsign.circle"
        case "THB": "bahtsign.circle"
        case "PHP": "pesosign.circle"
        case "CHF": "francsign.circle"
        case "RUB": "rublesign.circle"
        case "TRY": "turkishlirasign.circle"
        case "ILS": "shekelsign.circle"
        case "BRL": "brazilianrealsign.circle"
        case "VND": "dongsign.circle"
        // Only dollar currencies get the dollar sign.
        case "AUD", "USD", "SGD", "NZD", "HKD", "CAD", "TWD", "BND", "FJD": "dollarsign.circle"
        default: "banknote"
        }
    }

    private func currencyRow(_ code: String, note: String?) -> some View {
        Button { home = code } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(code) · \(name(of: code))").foregroundStyle(Color.ink)
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if home == code {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(home == code ? .isSelected : [])
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Your cards", SetupCopy.line(.cards))
            countryPicker.padding(.bottom, 14)
            bankGrid(bankCountry)
            // Below the grid, so adding a card never moves the buttons. One
            // job here: pick the banks. A card's own details (nickname,
            // debit/credit) are a tap away on its chip, never shown twice.
            if !book.active.isEmpty {
                pickedCards.padding(.top, 20)
            }
        }
        .onAppear {
            // A phone set to a country we have no banks for starts on the first one we do.
            if !allBankCountries.contains(bankCountry) { bankCountry = myCountries.first ?? "" }
        }
    }

    /// Cards added so far, as plain removable chips. Tap the name to open
    /// its nickname and debit/credit; tap the X to remove it.
    private var pickedCards: some View {
        FlowLayout(spacing: 8) {
            ForEach(book.active) { info in
                HStack(spacing: 6) {
                    Button { editing = info } label: {
                        Text(rowTitle(info)).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(rowTitle(info)), \(info.isCredit ? "credit" : "debit")")
                    .accessibilityHint("Edit nickname and type")
                    Button {
                        let id = info.id
                        let used = ((try? context.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.cardRaw == id }))) ?? 0) > 0
                        withAnimation(.snappy) { book.remove(info, hasPurchases: used) }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.footnote)
                            .symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44).contentShape(.rect)
                    .accessibilityLabel("Remove \(rowTitle(info))")
                }
                .padding(.leading, 14).padding(.trailing, 4)
                .frame(minHeight: 44)
                .background(Color.card, in: .capsule)
            }
        }
    }

    /// One country at a time, so the list stays short. "" = works anywhere.
    private var countryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allBankCountries, id: \.self) { c in
                    let picked = book.active.filter { $0.country == c && !$0.bank.isEmpty }.count
                    Button { withAnimation(.snappy) { bankCountry = c } } label: {
                        HStack(spacing: 6) {
                            Text(c.isEmpty ? "🌐" : CardInfo.flag(for: c))
                            Text(c.isEmpty ? "Anywhere" : countryName(c)).font(.subheadline.weight(.medium))
                            if picked > 0 {
                                Text("\(picked)").font(.caption2.weight(.bold)).monospacedDigit()
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.brandPalette[0], in: .capsule)
                                    .foregroundStyle(Color.onColorBadge)
                            }
                        }
                        .chip(selected: bankCountry == c)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(bankCountry == c ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    /// Banks in the chosen country, two per row. Each tap adds one card.
    /// At accessibility sizes the grid becomes one full-width row per bank:
    /// a half-width cell cut "DBS" down to "D…" (UI pass, 25 Sep).
    @ViewBuilder private func bankGrid(_ country: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { bankButtons(country) }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) { bankButtons(country) }
        }
    }

    @ViewBuilder private func bankButtons(_ country: String) -> some View {
        let banks = BankPreset.all.filter { $0.country == country }
        Group {
            ForEach(banks) { bank in
                let count = book.active.filter { $0.bank == bank.name }.count
                Button { addCard(from: bank) } label: {
                    HStack(spacing: 8) {
                        Text(bank.name).font(.body).foregroundStyle(Color.ink)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 2)
                        if count > 0 {
                            if count > 1 { Text("\(count)").font(.footnote.weight(.bold)).monospacedDigit() }
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ink)
                        } else {
                            Image(systemName: "plus.circle").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(count > 0 ? Color.ink : .clear, lineWidth: 1.5)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(count > 0 ? "\(bank.name), \(count) added. Add another" : "Add \(bank.name)")
            }
            // Not listed: a plain card named after the country; renamed next page.
            Button {
                var card = CardInfo(name: "Card", shortName: "Card",
                                    currency: country.isEmpty ? home : (BankPreset.all.first { $0.country == country }?.currency ?? home),
                                    country: country.isEmpty ? region : country)
                let n = book.active.filter { $0.bank.isEmpty && $0.name.hasPrefix("Card") }.count
                if n > 0 { card.name = "Card \(n + 1)"; card.shortName = card.name }
                withAnimation(.snappy) { book.upsert(card) }
            } label: {
                Label("Other bank", systemImage: "plus")
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// Every tap adds one more card from this bank, named "DBS", "DBS 2"…
    /// Debit or credit is chosen on the next page, with the digits.
    private func addCard(from bank: BankPreset) {
        let mine = book.active.filter { $0.bank == bank.name }
        let next = (mine.compactMap { Int($0.name.split(separator: " ").last ?? "") }.max() ?? (mine.isEmpty ? 0 : 1)) + 1
        var card = bank.card(credit: false)
        card.name = next > 1 ? "\(bank.shortName) \(next)" : bank.shortName
        card.shortName = card.name
        withAnimation(.snappy) { book.upsert(card) }
    }

    private func countryName(_ code: String) -> String {
        code.isEmpty ? "Anywhere" : (Locale.current.localizedString(forRegionCode: code) ?? code)
    }

    /// The user's countries first (phone, home currency, cards added), then
    /// the rest, then banks that work anywhere.
    private var allBankCountries: [String] {
        myCountries + otherCountries + [""]
    }

    /// Bank name, or the user's own name for the card once renamed. The
    /// last-4 digits (card number and Apple Pay number) that used to be a
    /// separate `.cardDetails` step now live only in Settings › Cards: a
    /// new user shouldn't have to leave the app to find them (UX pass).
    private func rowTitle(_ info: CardInfo) -> String {
        let generated = info.name.hasPrefix(info.bank) && !info.bank.isEmpty
        return generated ? BankPreset.short(info.bank) + numberSuffix(info) : info.name
    }

    /// " 2" for the second debit (or credit) card from the same bank.
    private func numberSuffix(_ info: CardInfo) -> String {
        guard let n = info.name.split(separator: " ").last, Int(n) != nil else { return "" }
        return " \(n)"
    }

    private var myCountries: [String] {
        var list = [region]
        if let fromCurrency = CardEditor.country(for: home), !list.contains(fromCurrency) { list.append(fromCurrency) }
        // Countries of cards already added.
        for c in book.active.map(\.country) where !list.contains(c) { list.append(c) }
        return list.filter { c in BankPreset.all.contains { $0.country == c } }
    }

    private var otherCountries: [String] {
        var seen: [String] = []
        for p in BankPreset.all where !p.country.isEmpty && !myCountries.contains(p.country) && !seen.contains(p.country) {
            seen.append(p.country)
        }
        return seen
    }

    /// The first purchase that came from an Apple Pay tap.
    private var firstTap: Transaction? { transactions.first { $0.seenIn.contains(.tap) } }
    private var tapConnected: Bool { firstTap != nil }

    /// Shortcuts has reached the app, even if nothing was logged yet (a ▶ test
    /// run does this). Enough to say the setup is done.
    private var shortcutReached: Bool { LogPurchaseIntent.shortcutHasReachedApp }

    /// Every state comes from a real event (spec 2026-09-25, option A): a
    /// real ▶ run or a real shop tap, never the app's own check.
    private var applePayStatus: ApplePayStatus {
        ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions)
    }

    private var applePay: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Log Apple Pay by itself", SetupCopy.line(.applePay))
            ApplePaySetupPanel(status: applePayStatus, needsCheckCount: ApplePayStatus.needsCheckCount(in: transactions))
                .padding(.top, 10)
        }
    }


    private var emailPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Catch online receipts", SetupCopy.line(.email))
            FlowLayout(spacing: 8) {
                ForEach([("car", "Rides"), ("takeoutbag.and.cup.and.straw", "Food delivery"), ("app.badge", "App stores"),
                         ("shippingbox", "Online shops"), ("building.columns", "Bank alerts")], id: \.1) { symbol, name in
                    Label(name, systemImage: symbol)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.card, in: .capsule)
                }
            }
            .padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 14) {
                ForEach([("lock", "Read-only. Can't send, delete or change email."),
                         ("iphone", SetupCopy.gmailOnDevice),
                         ("xmark.circle", "Disconnect any time in Settings.")], id: \.1) { symbol, text in
                    HStack(alignment: .top, spacing: 12) {
                        RowIcon(symbol)
                        Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .setupCard()
            .padding(.bottom, 16)
            if !gmail.isEmpty {
                VStack(spacing: 0) {
                    ForEach(gmail) { a in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.up)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.email).lineLimit(1)
                                Text(a.lastResult ?? "Connected").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                    }
                }
                .surface(radius: 16)
                .padding(.bottom, 14)
            }
            // A connect still reading after its sheet closed: say so here.
            if SyncStatus.gmail.isBusyForPerson || (SyncStatus.gmail.phase.isEnd && !SyncStatus.gmail.quiet) {
                SyncProgressCard(status: SyncStatus.gmail) {
                    if case .failed(let f) = SyncStatus.gmail.phase { GmailSync.retry(f, in: context) }
                }
                .padding(.bottom, 14)
            }
            if !gmail.isEmpty {
                Button { connectingGmail = true } label: {
                    HStack(spacing: 12) {
                        RowIcon("plus")
                        Text("Connect another Gmail").font(.body).foregroundStyle(Color.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var budgetPresets: [Double] {
        // Round numbers for the currency (yen and rupiah need bigger ones).
        let base: Double = ["JPY": 100, "KRW": 1000, "IDR": 10000, "INR": 50, "PHP": 40, "THB": 25, "HUF": 250, "ISK": 100][home] ?? 1
        return [500, 1000, 1500, 2000, 3000].map { $0 * base }
    }

    private var budgetPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter(.budget), title: "Want a monthly limit?",
                        subtitle: SetupCopy.line(.budget))

            // One big amount, typed or picked.
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Money.symbol(home))
                        .font(.system(size: budgetSymbolSize, weight: .bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("0", text: $customBudget)
                        .font(.system(size: budgetAmountSize, weight: .bold))
                        .monospacedDigit()
                        .keyboardType(.numberPad)
                        .focused($budgetFocused)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityLabel("Monthly budget in \(home)")
                        .onChange(of: customBudget) { _, text in
                            // Same cap as the budget sheet, so a 19-digit
                            // typo can't be saved.
                            let limited = BudgetSheet.limitInput(text, currency: home)
                            if limited != text { customBudget = limited; return }
                            budget = BudgetSheet.sanitized(Double(limited) ?? 0, currency: home)
                        }
                }
                .onTapGesture { budgetFocused = true }
                Text(budget > 0
                     ? "About \(Money.format(Decimal(budget / 30), home, cents: false)) a day"
                     : "No budget set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .setupCard()
            .animation(.snappy, value: budget)

            FlowLayout(spacing: 8) {
                ForEach(budgetPresets, id: \.self) { value in
                    Button {
                        budget = value
                        customBudget = BudgetSheet.text(for: value, currency: home)
                        budgetFocused = false
                    } label: {
                        Text(Money.format(Decimal(value), home, cents: false))
                            .chip(selected: budget == value)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)

            Button("No limit for now") {
                budget = 0
                customBudget = ""
                budgetFocused = false
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .padding(.top, 4)
        }
        .onAppear { if budget > 0, customBudget.isEmpty { customBudget = BudgetSheet.text(for: budget, currency: home) } }
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Measured against the row width, not the item's ideal width: a single
    /// chip wider than the row (a long amount at accessibility text sizes)
    /// used to be placed at its ideal size and run off the screen.
    private func size(of s: LayoutSubview, in width: CGFloat) -> CGSize {
        let ideal = s.sizeThatFits(.unspecified)
        guard width.isFinite, ideal.width > width else { return ideal }
        return s.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = size(of: s, in: width)
            if x > 0, x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = size(of: s, in: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}


/// Debit or credit, told apart without colour so it never clashes with the
/// category colours: debit is outlined, credit is filled.
struct CardTypeBadge: View {
    let isCredit: Bool

    var body: some View {
        Text(isCredit ? "Credit" : "Debit")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(isCredit ? Color.onColorBadge : Color.ink)
            .background(isCredit ? Color.creditFill : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(isCredit ? .clear : Color.secondary.opacity(0.5), lineWidth: 1))
    }
}

/// One card's details during setup: a small card preview, its nickname and
/// debit/credit. Saves as you type. The last-4 digits (card number, Apple
/// Pay number) used to live here too; a new user shouldn't have to leave
/// the app to find them, so they moved to Settings › Cards (UX pass).
struct CardDetailForm: View {
    let info: CardInfo
    @State private var name: String
    @State private var isCredit: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Grows with the text size, so large text isn't clipped.
    @ScaledMetric(relativeTo: .footnote) private var previewWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .footnote) private var previewHeight: CGFloat = 58

    /// Side by side normally; stacked at the accessibility text sizes.
    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
    }

    init(info: CardInfo) {
        self.info = info
        _name = State(initialValue: info.name)
        _isCredit = State(initialValue: info.isCredit)
    }

    var body: some View {
        rowLayout {
            preview
            VStack(alignment: .leading, spacing: 8) {
                // Looks like a field so people know they can call it
                // something they'll recognise ("Groceries card").
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nickname").font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        TextField("e.g. Groceries card", text: $name)
                            .font(.headline)
                            .submitLabel(.done)
                        Image(systemName: "pencil")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.page, in: .rect(cornerRadius: 9, style: .continuous))
                }
                Picker("Type", selection: $isCredit) {
                    Text("Debit").tag(false)
                    Text("Credit").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .surface(radius: 18)
        .onChange(of: name) { save() }
        .onChange(of: isCredit) { _, credit in
            // Keep an automatic name in step with the switch ("… Debit" → "… Credit");
            // a name the user typed is left alone.
            let from = credit ? "Debit" : "Credit", to = credit ? "Credit" : "Debit"
            if name.contains(from), name.hasPrefix(info.bank), !info.bank.isEmpty {
                name = name.replacingOccurrences(of: from, with: to)
            }
            save()
        }
    }

    /// Credit cards are dark, debit cards light: the same rule everywhere.
    /// Any digits already on the card (added later, in Settings) still show.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BankPreset.short(info.bank.isEmpty ? name : info.bank))
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(info.last4.first.map { "•• \($0)" } ?? "•• ····")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .opacity(0.8)
        }
        .foregroundStyle(isCredit ? Color.onColorBadge : Color.ink)
        .padding(8)
        .frame(width: previewWidth, height: previewHeight, alignment: .leading)
        .background(isCredit ? Color.creditFill : Color.page, in: .rect(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(isCredit ? .clear : Color.secondary.opacity(0.35), lineWidth: 1))
        .animation(.snappy, value: isCredit)
        .accessibilityHidden(true)
    }

    private func save() {
        var c = info
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        c.name = trimmed.isEmpty ? info.name : trimmed
        c.shortName = c.name
        c.isCredit = isCredit
        // Nicknames are for the user; Wallet matching keeps the bank's words.
        let bankWords = Set(BankPreset.match(info.bank)?.words ?? [])
        c.walletWords.removeAll { $0 == info.name.lowercased() && !bankWords.contains($0) }
        CardBook.shared.upsert(c)
    }
}
