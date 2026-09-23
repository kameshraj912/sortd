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
    @AppStorage(SetupProfile.feelingKey) private var feelingRaw = ""
    @AppStorage(SetupProfile.abroadKey) private var abroadRaw = ""
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
    /// Each new step opens at the top, title in view.
    @State private var scroll = ScrollPosition(edge: .top)
    /// The budget before setup started, so un-ticking "Spend less" undoes
    /// a limit set a moment ago without wiping one set weeks ago.
    @State private var budgetBefore: Double?

    typealias Step = SetupFlow.Step
    #if DEBUG
    @State private var step: Step = Step(rawValue: Int(ProcessInfo.processInfo.environment["SPEND_ONBOARD_STEP"] ?? "") ?? 0) ?? .welcome
    #else
    @State private var step: Step = .welcome
    #endif
    @State private var pro = ProStore.shared
    @State private var showingPaywall = false
    @State private var showingImport = false
    /// "14 days free", read from the App Store. Nil when there's no trial.
    @State private var trialText: String?
    @State private var forward = true
    @State private var showingGuide = false
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
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            if typeSize.isAccessibilitySize, step != .building { bottomBar }
            }
        }
        .scrollPosition($scroll)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        // Text scrolling under Back / progress / Skip gets a backdrop.
        .scrollEdgeEffectStyle(.hard, for: .top)
        // Glass controls float over the page, and the page scrolls under them.
        // Bars (not plain insets) so the page blurs softly under them as it
        // scrolls, instead of text running into the buttons.
        .safeAreaBar(edge: .top, spacing: 0) { topBar }
        .safeAreaBar(edge: .bottom, spacing: 0) { if step != .building, !typeSize.isAccessibilitySize { bottomBar } }
        .onAppear { if budgetBefore == nil { budgetBefore = budget } }
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
        .sheet(item: $editing) { CardEditor(original: $0) }
        .sheet(isPresented: $connectingGmail, onDismiss: { gmail = GmailSync.accounts }) { if ProStore.shared.isPro { ConnectGmailSheet() } else { PaywallView(feature: .gmail) } }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .sheet(isPresented: $showingImport) { NavigationStack { ImportView() } }
        .task(id: step) {
            guard step == .pro, trialText == nil else { return }
            await pro.load()
            if let yearly = pro.product(ProStore.ID.yearly) {
                trialText = await pro.trialText(for: yearly)
            }
        }
        .sheet(isPresented: $showingGuide) {
            NavigationStack { SetupGuideView(isPresentedAsSheet: true) }
        }
        .sensoryFeedback(.selection, trigger: step)
        .onChange(of: step) {
            stepChangedAt = .now
            scroll.scrollTo(edge: .top)
        }
        // The real permission, for the building and plan text (it may have
        // been turned off in Settings, or asked in an earlier setup).
        .task(id: step) {
            guard step == .building || step == .plan else { return }
            notificationsOff = !(await Self.notificationsAllowed())
        }
    }

    /// True just after a step change, and for good once setup has finished.
    private var tapsLocked: Bool {
        finished || Date.now.timeIntervalSince(stepChangedAt) < 0.4
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
            return ("bell.slash", "Check-ins off (notifications are off)")
        }
        return (choice.symbol, choice == .needed ? "No regular check-ins" : choice.summary)
    }

    // MARK: Answers

    private var goals: Set<SetupProfile.Goal> { SetupProfile.goals(goalsRaw) }
    private var payment: SetupProfile.Payment? { SetupProfile.Payment(rawValue: paymentRaw) }
    private var checkIn: SetupProfile.CheckIn { SetupProfile.CheckIn(rawValue: checkInRaw) ?? .sunday }
    private var abroad: SetupProfile.Abroad? { SetupProfile.Abroad(rawValue: abroadRaw) }
    private var flow: SetupFlow {
        SetupFlow(goals: goals, payment: payment, hasCards: !book.active.isEmpty,
                  gmailFeature: Features.gmail, isPro: pro.isPro)
    }
    private var wantsGmail: Bool { flow.wantsGmail }
    /// The check-in step asks for notifications only if something will use them.
    private var asksNotifications: Bool { checkIn != .needed || billIntent }

    private var goalsBinding: Binding<Set<SetupProfile.Goal>> {
        Binding(get: { goals }, set: { goalsRaw = SetupProfile.raw($0) })
    }
    private var paymentBinding: Binding<SetupProfile.Payment?> {
        Binding(get: { payment }, set: { paymentRaw = $0?.rawValue ?? "" })
    }
    private var feelingBinding: Binding<SetupProfile.Feeling?> {
        Binding(get: { SetupProfile.Feeling(rawValue: feelingRaw) }, set: { feelingRaw = $0?.rawValue ?? "" })
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
                .frame(maxWidth: .infinity, minHeight: 32)
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
                .frame(maxWidth: .infinity, minHeight: 28)
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
                case .pro where !pro.isPro:
                    // Buy, the price, then skip, together at the bottom.
                    primaryButton(trialLine) { showingPaywall = true }
                    Text(priceLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                    tertiaryButton(primaryTitle, action: primaryAction)
                case .welcome:
                    primaryButton(primaryTitle, action: primaryAction)
                    secondaryButton("Bring In Past Spending") { showingImport = true }
                    // Not when setup is run again: sample data would mix into
                    // real purchases, and its Clear forces a full setup.
                    if transactions.isEmpty, !rerun {
                        tertiaryButton("Look around with sample data") {
                            DemoData.load(in: context)
                            finish()
                        }
                    }
                case .plan:
                    primaryButton(primaryTitle, action: primaryAction)
                    tertiaryButton("Do this later and look around") { finish() }
                case .email where gmail.isEmpty:
                    primaryButton("Connect Gmail") { connectingGmail = true }
                    tertiaryButton("I'll do this later") { go(1) }
                case .applePay where !tapConnected:
                    primaryButton("Open Shortcuts") {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    }
                    tertiaryButton("I'll do this later") { go(1) }
                case .checkIn where asksNotifications:
                    primaryButton(primaryTitle, action: primaryAction)
                    tertiaryButton("Not now") {
                        // No notifications: no check-in, no bill reminders.
                        checkInRaw = SetupProfile.CheckIn.needed.rawValue
                        billIntent = false
                        checkInChosen = true
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
        let last = neighbour(of: step, 1) == nil
        switch step {
        case .welcome: return "Get Started"
        case .payment where payment == nil: return "Skip This One"
        case .feeling where feelingRaw.isEmpty: return "Skip This One"
        case .checkIn: return asksNotifications ? "Turn On Notifications" : "Continue"
        case .plan: return book.active.isEmpty ? "Add My First Card" : "Continue Setup"
        case .cards where book.active.isEmpty: return "Add Cards Later"
        case .cardDetails where !detailsComplete: return "Add Digits Later"
        case .applePay where !tapConnected: return last ? "Do This Later and Start" : "I'll Do This Later"
        case .email where gmail.isEmpty: return "I'll Do This Later"
        case .pro where !pro.isPro: return "Maybe Later"
        default: return last ? "Start Using Sortd" : "Continue"
        }
    }

    private func primaryAction() {
        guard !finished else { return }
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
                    requesting = false
                    if step == from { go(1) }
                }
                return
            }
        }
        go(1)
    }

    private func go(_ delta: Int) {
        guard !finished else { return }
        budgetFocused = false
        forward = delta > 0
        guard let next = neighbour(of: step, delta) else {
            if delta > 0 { finish() }
            return
        }
        withAnimation(.snappy) { step = next }
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
        // Skipped the question: keep an earlier answer, otherwise no check-in.
        if !checkInChosen, UserDefaults.standard.string(forKey: SetupProfile.checkInKey) == nil {
            checkInRaw = SetupProfile.CheckIn.needed.rawValue
        }
        // A limit set a moment ago, then "Spend less" un-ticked: undo it.
        if !goals.contains(.spendLess), let before = budgetBefore { budget = before }
        let choice = checkIn
        Task {
            // Only if notifications are allowed; otherwise clear any old one,
            // and say so in Settings rather than show a time that never comes.
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            let allowed = status == .authorized || status == .provisional
            await CheckInReminder.schedule(allowed ? choice : .needed)
            if !allowed {
                UserDefaults.standard.set(SetupProfile.CheckIn.needed.rawValue, forKey: SetupProfile.checkInKey)
            }
        }
        // Bill reminders are Pro: on now if they have it, otherwise the
        // intent waits and comes on when Pro starts (applyPendingBillReminders).
        if billIntent, pro.isPro {
            reminders = true
            billIntent = false
        }
        rerun = false
        done = true
        onFinish()
    }

    /// The limit that will actually be in place when setup ends.
    private var effectiveBudget: Double {
        goals.contains(.spendLess) ? budget : (budgetBefore ?? 0)
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .goals: GoalsPage(counter: counter(.goals), goals: goalsBinding)
        case .payment: PaymentPage(counter: counter(.payment), payment: paymentBinding) { if step == .payment { go(1) } }
        case .currency: currency
        case .feeling: FeelingPage(counter: counter(.feeling), feeling: feelingBinding)
        case .budget: budgetPage
        case .checkIn: CheckInPage(counter: counter(.checkIn), checkIn: checkInBinding, billReminders: $billIntent, isPro: pro.isPro)
        case .building: BuildingPage(lines: buildingLines) { if step == .building { go(1) } }
        case .plan: PlanPage(summary: planSummary, tasks: setupTasks, settings: planSettings)
        case .cards: cards
        case .cardDetails: cardDetails
        case .applePay: applePay
        case .pro: proPage
        case .email: emailPage
        }
    }

    // MARK: What the answers built

    private var buildingLines: [String] {
        var lines = ["Showing totals in \(home)"
                     + (abroad == .often || abroad == .sometimes || goals.contains(.countries) ? ", other currencies converted each day" : "")]
        if goals.contains(.spendLess), effectiveBudget > 0 {
            lines.append("Setting a \(Money.format(Decimal(effectiveBudget), home, cents: false)) monthly limit, with what's left each day")
        } else if goals.contains(.bills) {
            lines.append("Watching for subscriptions and bills")
        } else {
            lines.append("Putting where your money goes first")
        }
        lines.append(checkInLine.text)
        lines.append("Keeping everything on this iPhone. No bank login, ever.")
        return lines
    }

    private var planSummary: String { "Built from your answers. Change any of it in Settings." }

    private var planSettings: [(String, String)] {
        var chips = [(Self.currencySymbol(home), "Totals in \(home)"
                      + (abroad == .often || abroad == .sometimes || goals.contains(.countries) ? ", others converted daily" : ""))]
        if effectiveBudget > 0 { chips.append(("gauge.with.dots.needle.33percent", Money.format(Decimal(effectiveBudget), home, cents: false) + " monthly limit")) }
        chips.append((checkInLine.symbol, checkInLine.text))
        if billIntent { chips.append(("bell.badge", pro.isPro ? "Bill heads-ups" : "Bill heads-ups with Pro")) }
        return chips
    }

    private var setupTasks: [SetupTask] {
        SetupChecklist.tasks(flow: flow, hasCards: !book.active.isEmpty, tapped: tapConnected,
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
                Text("Your spending, logged by itself.")
                    .font(.body).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("wave.3.right", "Apple Pay logs itself", "Pay as usual. It shows up in a second.", Color.brandPalette[0])
                feature("creditcard", "Every card, every currency", "Converted at the day's rate.", Color.brandPalette[1])
                feature("arrow.triangle.2.circlepath", "Bills, seen coming", "Know what's due before it's charged.", Color.brandPalette[2])
                feature("lock", "Private by design", "No bank login. Stays on your iPhone.", Color.brandPalette[3])
            }
            .setupCard(padding: 20)
        }
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
                        subtitle: nil)
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
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
                }
            }

            Text("Do you spend in other currencies?")
                .font(.headline)
                .padding(.top, 24)
            HStack(spacing: 8) {
                ForEach(SetupProfile.Abroad.allCases) { a in
                    Button { withAnimation(.snappy) { abroadRaw = a.rawValue } } label: {
                        Text(a.title)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .chip(selected: abroad == a)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(abroad == a ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            .sensoryFeedback(.selection, trigger: abroadRaw)

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
            header("Your cards", "Tap each bank you pay with. Two cards at one bank? Tap twice.")
            countryPicker.padding(.bottom, 14)
            bankGrid(bankCountry)
            // Below the grid, so adding a card never moves the buttons.
            if !book.active.isEmpty {
                Text("Added (\(book.active.count))").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.top, 24).padding(.bottom, 8)
                pickedCards
            }
        }
        .onAppear {
            // A phone set to a country we have no banks for starts on the first one we do.
            if !allBankCountries.contains(bankCountry) { bankCountry = myCountries.first ?? "" }
        }
    }

    /// Cards added so far: one row each, with where it's from.
    private var pickedCards: some View {
        VStack(spacing: 0) {
            ForEach(Array(book.active.enumerated()), id: \.element.id) { i, info in
                if i > 0 { Divider().padding(.leading, 60) }
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.brandPalette[i % 4].gradient)
                        .frame(width: 34, height: 22)
                        .overlay(alignment: .bottomTrailing) {
                            Text(CardInfo.flag(for: info.country)).font(.system(size: 10)).padding(2)
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(countryName(info.country) + " · " + info.currency)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button {
                        let id = info.id
                        let used = ((try? context.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.cardRaw == id }))) ?? 0) > 0
                        withAnimation(.snappy) { book.remove(info, hasPurchases: used) }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.title3)
                            .symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                            .frame(width: 44, height: 44).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(info.name)")
                }
                .padding(.leading, 14).padding(.trailing, 4)
                .frame(minHeight: 54)
            }
        }
        .surface(radius: 16)
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
                                Text("\(picked)").font(.caption2.weight(.bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.brandPalette[0], in: .capsule)
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
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
    private func bankGrid(_ country: String) -> some View {
        let banks = BankPreset.all.filter { $0.country == country }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(banks) { bank in
                let count = book.active.filter { $0.bank == bank.name }.count
                Button { addCard(from: bank) } label: {
                    HStack(spacing: 8) {
                        Text(bank.name).font(.body).foregroundStyle(Color.ink).lineLimit(2).multilineTextAlignment(.leading)
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

    /// "Add digits for 2 more cards" — says how many are left, since the
    /// missing one may be further down the list.
    private var missingDigitsText: String {
        let n = book.active.filter { !Self.digitsComplete($0, in: book.active) }.count
        return n == 1 ? "Add digits for 1 more card" : "Add digits for \(n) more cards"
    }

    /// Every card has its card-number digits: that's how bank emails and
    /// receipts find it.
    private var detailsComplete: Bool {
        book.active.allSatisfy { Self.digitsComplete($0, in: book.active) }
    }

    /// Two cards from one bank look the same to Apple Pay except for the
    /// Apple Pay number, so then it's needed too.
    static func needsApplePayDigits(_ info: CardInfo, in cards: [CardInfo]) -> Bool {
        !info.bank.isEmpty && cards.filter { $0.bank == info.bank }.count > 1
    }

    static func digitsComplete(_ info: CardInfo, in cards: [CardInfo]) -> Bool {
        !info.last4.isEmpty && (!needsApplePayDigits(info, in: cards) || !(info.applePayLast4 ?? []).isEmpty)
    }

    private var cardDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Last 4 digits", "So receipts land on the right card. Only the last 4.")
            VStack(spacing: 16) {
                ForEach(book.active) { info in
                    CardDetailForm(info: info, needsPay: Self.needsApplePayDigits(info, in: book.active))
                }
            }
        }
    }

    /// Bank name, or the user's own name for the card once renamed.
    private func rowTitle(_ info: CardInfo) -> String {
        let generated = info.name.hasPrefix(info.bank) && !info.bank.isEmpty
        return generated ? BankPreset.short(info.bank) + numberSuffix(info) : info.name
    }

    /// Two cards from one bank can only be told apart on receipts by their
    /// last 4 digits.
    private func needsDigits(_ info: CardInfo) -> Bool {
        info.allLast4.isEmpty && book.active.filter { $0.bank == info.bank && !info.bank.isEmpty }.count > 1
    }

    private func rowDetail(_ info: CardInfo) -> String {
        if !info.allLast4.isEmpty { return info.allLast4.map { "•• \($0)" }.joined(separator: " · ") }
        return needsDigits(info) ? "Add last 4 digits" : "Tap to rename"
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

    private var applePay: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Log Apple Pay by itself", "A 2-minute setup in Apple's Shortcuts app.")
            tapStatus
            Group {
                if #available(iOS 27.0, *) {
                    WalletSetupGuide()
                        .setupCard()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        miniStep(1, "Shortcuts → Automation → +", "Tap Wallet, choose your cards, then Run Immediately and Next.")
                        miniStep(2, "Create New Shortcut", "Search Sortd and tap Log Wallet Tap.")
                        miniStep(3, "Fill the blue word", "Tap Transaction, then pick Shortcut Input above the keyboard. It should look like this:")
                        actionMock.padding(.leading, 38)
                    }
                    .setupCard()
                }
            }
            .padding(.top, 10)
            Button { showingGuide = true } label: {
                HStack(spacing: 12) {
                    RowIcon("list.number")
                    Text("Every step in detail").font(.body).foregroundStyle(Color.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }

    /// Checks itself: listens for the first tap and celebrates when it lands.
    private var tapStatus: some View {
        HStack(spacing: 14) {
            Image(systemName: tapConnected ? "checkmark" : "wave.3.right")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 46, height: 46)
                .background(tapConnected ? Color.up : Color.brand, in: .circle)
                .symbolEffect(.variableColor.iterative, isActive: !tapConnected)
                .symbolEffect(.bounce, value: tapConnected)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                if let t = firstTap {
                    Text("Connected").font(.headline)
                    Text("Logged \(Money.format(t.amount, t.currencyCode)) at \(t.merchant)")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Waiting for your first tap").font(.headline)
                    Text("Do the steps below, then pay with Apple Pay.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tapConnected ? Color.up.opacity(0.12) : Color.card, in: .rect(cornerRadius: 20, style: .continuous))
        .animation(.snappy, value: tapConnected)
        .sensoryFeedback(.success, trigger: tapConnected)
        .accessibilityElement(children: .combine)
    }

    /// What the finished Shortcuts action looks like, so people can check theirs.
    private var actionMock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image("BrandIcon").resizable().frame(width: 20, height: 20)
                    .clipShape(.rect(cornerRadius: 5, style: .continuous))
                Text("Log Wallet Tap").font(.footnote.weight(.semibold))
            }
            // Same wording as the real action in Shortcuts.
            FlowLayout(spacing: 4) {
                Text("Log").font(.footnote)
                token("Shortcut Input")
                Text("in Sortd").font(.footnote)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.page, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Log Shortcut Input in Sortd")
    }

    /// A Shortcuts variable token (blue, like in the Shortcuts app).
    private func token(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(red: 0.2, green: 0.47, blue: 0.96), in: .rect(cornerRadius: 5))
    }

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
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emailPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Catch online receipts", "From receipts and bank alerts in your Gmail.")
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
                         ("iphone", "Read on this iPhone, never a server."),
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
                        subtitle: "Change it any time.")

            // One big amount, typed or picked.
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Money.symbol(home))
                        .font(.system(size: budgetSymbolSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("0", text: $customBudget)
                        .font(.system(size: budgetAmountSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .keyboardType(.numberPad)
                        .focused($budgetFocused)
                        .fixedSize()
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
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
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

    /// Sortd Pro, offered once during setup.
    ///
    /// Without this someone can finish setup having never heard of the trial
    /// or of Pro, then hit a locked feature later and feel tricked. Said
    /// plainly here instead: what Pro adds, what the trial costs afterwards,
    /// and that everything on this screen is skippable.
    ///
    /// The price line is not decoration. The ACCC has free trials and
    /// subscriptions as an enforcement priority through 2027: a headline
    /// saying "free" has to say, just as clearly, what happens when the free
    /// part ends.
    private var proPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(pro.isPro ? "You have Sortd Pro" : "What Pro adds for you",
                   pro.isPro
                   ? "Everything below is unlocked. Thank you."
                   : "Picked from your answers. Logging, cards, budgets and export stay free.")

            VStack(spacing: 0) {
                ForEach(Array(SetupProfile.proOrder(goals: goals, payment: payment).enumerated()), id: \.element) { index, feature in
                    if index > 0 { Divider().padding(.leading, 46) }
                    HStack(alignment: .top, spacing: 12) {
                        RowIcon(feature.symbol)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.headline)
                            Text(feature.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))

            // How the trial works, said plainly: what happens today, and
            // what happens when it ends.
            if !pro.isPro, let trialText {
                VStack(alignment: .leading, spacing: 14) {
                    timelineRow("gift", "Today", "Everything in Pro unlocked. \(trialText.capitalized).")
                    timelineRow("calendar.badge.clock", "When the trial ends",
                                pro.product(ProStore.ID.yearly).map { "Your plan starts at \($0.displayPrice) a year." } ?? "Your plan starts.")
                    timelineRow("xmark.circle", "Any time before", "Cancel in the App Store and you pay nothing.")
                }
                .setupCard()
                .padding(.top, 12)
            }
        }
    }

    private func timelineRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Try Sortd Pro free" reads like a typo — free is left dangling. Say
    /// the actual offer when the App Store has told us what it is, and a
    /// plain invitation when it hasn't.
    private var proHeadline: String {
        guard let trial = trialText else { return "Try Sortd Pro" }
        return "Sortd Pro, \(trial.lowercased())"
    }

    /// Reads the real offer from the App Store when it's there, and stays
    /// vague rather than promising a trial that might not exist.
    private var trialLine: String {
        trialText.map { "Start \($0.lowercased())" } ?? "See Plans"
    }

    private var priceLine: String {
        guard let yearly = pro.product(ProStore.ID.yearly) else {
            return "Cancel any time in the App Store."
        }
        guard let trial = trialText else {
            return "\(yearly.displayPrice) a year. Cancel any time in the App Store."
        }
        return "\(trial.capitalized), then \(yearly.displayPrice) a year. Cancel any time in the App Store."
    }

}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
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
            let size = s.sizeThatFits(.unspecified)
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
            .foregroundStyle(isCredit ? Color.white : Color.ink)
            .background(isCredit ? Color.creditFill : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(isCredit ? .clear : Color.secondary.opacity(0.5), lineWidth: 1))
    }
}

/// One card's details during setup: a small card preview, then name,
/// type, and the two sets of last-4 digits. Saves as you type.
struct CardDetailForm: View {
    let info: CardInfo
    @State private var name: String
    @State private var isCredit: Bool
    @State private var digits: String
    @State private var payDigits: String
    @State private var showHelp = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Sizes that grow with the text size, so large text isn't clipped.
    @ScaledMetric(relativeTo: .footnote) private var previewWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .footnote) private var previewHeight: CGFloat = 58
    @ScaledMetric(relativeTo: .body) private var digitsWidth: CGFloat = 90

    var needsPay = false

    /// Side by side normally; stacked at the accessibility text sizes.
    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
    }

    init(info: CardInfo, needsPay: Bool = false) {
        self.needsPay = needsPay
        self.info = info
        _name = State(initialValue: info.name)
        _isCredit = State(initialValue: info.isCredit)
        _digits = State(initialValue: info.last4.first ?? "")
        _payDigits = State(initialValue: info.applePayLast4?.first ?? "")
    }

    private var missing: Bool { CardEditor.fours(digits).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            Divider().padding(.leading, 14)
            digitRow("Card number", text: $digits, required: true)
            Divider().padding(.leading, 14)
            digitRow("Apple Pay number", text: $payDigits, required: needsPay)

            Button {
                withAnimation(.snappy) { showHelp.toggle() }
            } label: {
                Label(showHelp ? "Hide" : "Where do I find these?", systemImage: "questionmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if showHelp {
                Text("Card number: the last 4 digits printed on your card or in your bank app. Apple Pay number: Wallet › this card › ••• › Card Details › Device Account Number. Apple Pay pays with that number, so receipts for Apple Pay purchases often show it instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
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
        .onChange(of: digits) { save() }
        .onChange(of: payDigits) { save() }
    }

    /// Credit cards are dark, debit cards light: the same rule everywhere.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BankPreset.short(info.bank.isEmpty ? name : info.bank))
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(missing ? "•• ····" : "•• \(CardEditor.fours(digits)[0])")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .opacity(0.8)
        }
        .foregroundStyle(isCredit ? Color.white : Color.ink)
        .padding(8)
        .frame(width: previewWidth, height: previewHeight, alignment: .leading)
        .background(isCredit ? Color.creditFill : Color.page, in: .rect(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(isCredit ? .clear : Color.secondary.opacity(0.35), lineWidth: 1))
        .animation(.snappy, value: isCredit)
        .accessibilityHidden(true)
    }

    private func digitRow(_ title: String, text: Binding<String>, required: Bool) -> some View {
        let stacked = typeSize.isAccessibilitySize
        return (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(required ? (title == "Apple Pay number" ? "Required — tells same-bank cards apart" : "Required") : "Recommended")
                    .font(.caption)
                    .foregroundStyle(required && text.wrappedValue.count < 4 ? Color.orange : Color.secondary)
            }
            if !stacked { Spacer() }
            TextField("Last 4", text: text)
                .keyboardType(.numberPad)
                .onChange(of: text.wrappedValue) { _, new in
                    let clean = String(new.filter(\.isNumber).prefix(4))
                    if clean != new { text.wrappedValue = clean }
                }
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .font(.body.monospacedDigit())
                .frame(width: stacked ? nil : digitsWidth)
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, stacked ? 8 : 0)
        .frame(minHeight: 52)
    }

    private func save() {
        var c = info
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        c.name = trimmed.isEmpty ? info.name : trimmed
        c.shortName = c.name
        c.isCredit = isCredit
        c.last4 = CardEditor.fours(digits)
        let pay = CardEditor.fours(payDigits)
        c.applePayLast4 = pay.isEmpty ? nil : pay
        // Nicknames are for the user; Wallet matching keeps the bank's words.
        let bankWords = Set(BankPreset.match(info.bank)?.words ?? [])
        c.walletWords.removeAll { $0 == info.name.lowercased() && !bankWords.contains($0) }
        CardBook.shared.upsert(c)
    }
}
