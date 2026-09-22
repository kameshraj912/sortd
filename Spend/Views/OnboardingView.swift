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

    /// Questions first, then what the answers built, then the few chores,
    /// then Pro. Nothing is asked for before the app has earned it.
    enum Step: Int, CaseIterable {
        case welcome, goals, payment, currency, feeling, budget, checkIn, building, plan
        case cards, cardDetails, applePay, pro, email
    }
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

    private var book: CardBook { .shared }
    private var region: String { Locale.current.region?.identifier ?? "AU" }

    var body: some View {
        ScrollView {
            page
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        // Glass controls float over the page, and the page scrolls under them.
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { if step != .building { bottomBar } }
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
    }

    // MARK: Answers

    private var goals: Set<SetupProfile.Goal> { SetupProfile.goals(goalsRaw) }
    private var payment: SetupProfile.Payment? { SetupProfile.Payment(rawValue: paymentRaw) }
    private var checkIn: SetupProfile.CheckIn { SetupProfile.CheckIn(rawValue: checkInRaw) ?? .sunday }
    private var abroad: SetupProfile.Abroad? { SetupProfile.Abroad(rawValue: abroadRaw) }
    private var wantsGmail: Bool { payment == .online || goals.contains(.receipts) }
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

    private func isShown(_ s: Step) -> Bool {
        switch s {
        case .budget: goals.contains(.spendLess)
        case .cardDetails: !book.active.isEmpty
        case .applePay: payment != .cash
        case .email: Features.gmail && pro.isPro && wantsGmail
        default: true
        }
    }

    /// The next step this person will see, going forward or back. Going back
    /// never lands on the "building" pause.
    private func neighbour(of s: Step, _ delta: Int) -> Step? {
        var i = s.rawValue + delta
        while let c = Step(rawValue: i) {
            if isShown(c), !(delta < 0 && c == .building) { return c }
            i += delta
        }
        return nil
    }

    private var questionSteps: [Step] { [.goals, .payment, .currency, .feeling, .budget, .checkIn].filter(isShown) }

    private func counter(_ s: Step) -> String {
        let steps = questionSteps
        return "Question \((steps.firstIndex(of: s) ?? 0) + 1) of \(steps.count)"
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if step != .welcome && step != .building {
                Button { go(-1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            // One segment per step this person will actually see.
            HStack(spacing: 4) {
                let shown = Step.allCases.filter { $0 != .welcome && $0 != .building && isShown($0) }
                let reached = shown.lastIndex { $0.rawValue <= step.rawValue } ?? -1
                ForEach(Array(shown.indices), id: \.self) { i in
                    Capsule()
                        .fill(i <= reached ? Color.brandPalette[i % Color.brandPalette.count] : Color.track)
                        .frame(height: 4)
                }
            }
            .opacity(step == .welcome || step == .building ? 0 : 1)
            .accessibilityHidden(true)
            if questionSteps.contains(step) {
                // Straight to the plan with sensible defaults.
                Button("Skip") {
                    budgetFocused = false
                    forward = true
                    withAnimation(.snappy) { step = .plan }
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.glass)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .tint(Color.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
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
                    Button(action: primaryAction) {
                        Text(primaryTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.plain)
                case .welcome:
                    primaryButton(primaryTitle, action: primaryAction)
                    secondaryButton("I Already Have Spending to Bring In") { showingImport = true }
                    // Not when setup is run again over real purchases: sample
                    // data would mix into them.
                    if transactions.isEmpty {
                        Button("Look around with sample data") {
                            DemoData.load(in: context)
                            finish()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 36)
                    }
                case .plan:
                    primaryButton(primaryTitle, action: primaryAction)
                    Button("Do this later and look around") { finish() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 36)
                case .checkIn where asksNotifications:
                    primaryButton(primaryTitle, action: primaryAction)
                    Button("Not now") { go(1) }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 36)
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
        case .plan: return "Start with Step 1"
        case .cards where book.active.isEmpty: return "Add Cards Later"
        case .cardDetails where !detailsComplete: return "Add Digits Later"
        case .applePay where !tapConnected: return last ? "Do This Later and Start" : "I'll Do This Later"
        case .email where gmail.isEmpty: return "I'll Do This Later"
        case .pro where !pro.isPro: return "Maybe Later"
        default: return last ? "Start Using Sortd" : "Continue"
        }
    }

    private func primaryAction() {
        if step == .checkIn, asksNotifications {
            // One button, straight to Apple's own alert (no fake "Allow").
            Task {
                _ = await Reminders.requestPermission()
                go(1)
            }
            return
        }
        go(1)
    }

    private func go(_ delta: Int) {
        budgetFocused = false
        forward = delta > 0
        guard let next = neighbour(of: step, delta) else {
            if delta > 0 { finish() }
            return
        }
        withAnimation(.snappy) { step = next }
    }

    private func finish() {
        Task { await FXService.rebase(to: home, in: context) }
        let choice = checkIn
        Task { await CheckInReminder.schedule(choice) }
        // Bill reminders are Pro: on now if they have it, otherwise they
        // come on when a trial starts from Settings.
        if billIntent, pro.isPro { reminders = true }
        done = true
        onFinish()
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .goals: GoalsPage(counter: counter(.goals), goals: goalsBinding)
        case .payment: PaymentPage(counter: counter(.payment), payment: paymentBinding)
        case .currency: currency
        case .feeling: FeelingPage(counter: counter(.feeling), feeling: feelingBinding)
        case .budget: budgetPage
        case .checkIn: CheckInPage(counter: counter(.checkIn), checkIn: checkInBinding, billReminders: $billIntent, isPro: pro.isPro)
        case .building: BuildingPage(lines: buildingLines) { if step == .building { go(1) } }
        case .plan: PlanPage(summary: planSummary, items: planItems, settings: planSettings)
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
        if goals.contains(.spendLess), budget > 0 {
            lines.append("Setting a \(Money.format(Decimal(budget), home, cents: false)) monthly limit, with what's left each day")
        } else if goals.contains(.bills) {
            lines.append("Watching for subscriptions and bills")
        } else {
            lines.append("Putting where your money goes first")
        }
        lines.append(checkIn.summary)
        lines.append("Keeping everything on this iPhone. No bank login, ever.")
        return lines
    }

    private var planSummary: String {
        var s = "Built for spending in \(home)"
        if abroad == .often || abroad == .sometimes || goals.contains(.countries) { s += " and other currencies" }
        if budget > 0 { s += ", with a monthly limit of \(Money.format(Decimal(budget), home, cents: false))" }
        return s + "."
    }

    private var planSettings: [(String, String)] {
        var chips = [("dollarsign.circle", "Totals in \(home)")]
        if budget > 0 { chips.append(("gauge.with.dots.needle.33percent", Money.format(Decimal(budget), home, cents: false) + " a month")) }
        chips.append((checkIn.symbol, checkIn == .needed ? "Quiet mode" : checkIn.title))
        if billIntent { chips.append(("bell.badge", "Bill heads-ups")) }
        return chips
    }

    private var planItems: [PlanItem] {
        var items = [PlanItem(id: "cards", symbol: "creditcard", title: "Add the cards you pay with", time: "30 seconds", pro: false)]
        if payment != .cash {
            items.append(PlanItem(id: "tap", symbol: "wave.3.right", title: "Log Apple Pay taps by themselves", time: "2 minutes, once", pro: false))
        } else {
            items.append(PlanItem(id: "widget", symbol: "square.grid.2x2", title: "Quick add from your Home Screen", time: "Add the widget any time", pro: false))
        }
        if Features.gmail, wantsGmail {
            items.append(PlanItem(id: "gmail", symbol: "envelope", title: "Catch online receipts from Gmail", time: "1 minute", pro: true))
        }
        if goals.contains(.receipts) {
            items.append(PlanItem(id: "scan", symbol: "doc.text.viewfinder", title: "Scan paper receipts", time: "When you need it", pro: true))
        }
        return items
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
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
                feature("wave.3.right", "Apple Pay taps log themselves", "Pay as usual. Each tap lands in Sortd in a second.", Color.brandPalette[0])
                feature("square.stack", "Every card, every currency", "Debit, credit and travel cards, converted at the day's rate.", Color.brandPalette[1])
                feature("arrow.triangle.2.circlepath", "Bills and subscriptions, predicted", "See what's due before it's charged.", Color.brandPalette[2])
                feature("lock", "Private by design", "No bank logins. Your data stays on your iPhone.", Color.brandPalette[3])
            }
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 26)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var currency: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter(.currency), title: "Your main currency",
                        subtitle: "Totals and budgets are shown in this. Other currencies are converted at that day's rate.")
            VStack(spacing: 0) {
                currencyRow(Money.detectedHome, note: "From your iPhone")
                // A short list; the rest are one tap away under "Other currencies".
                ForEach(Array(["AUD", "SGD", "USD", "INR", "GBP"].filter { $0 != Money.detectedHome }.prefix(3)), id: \.self) {
                    Divider().padding(.leading, 16)
                    currencyRow($0, note: nil)
                }
            }
            .surface(radius: 16)
            Menu {
                ForEach(Money.supported, id: \.self) { code in
                    Button("\(code) · \(name(of: code))") { home = code }
                }
            } label: {
                Label("Other currencies", systemImage: "globe")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 44)
            }
            .padding(.top, 8)

            Text("Do you spend in other currencies?")
                .font(.headline)
                .padding(.top, 16)
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
                Label(ratePreview, systemImage: "arrow.left.arrow.right")
                    .font(.subheadline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
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
            header("Your cards", "Pick the bank for each card you pay with. Two cards from one bank? Add it twice. Debit or credit comes next.")
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
                        Text(bank.name).font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 2)
                        if count > 0 {
                            Text(count > 1 ? "\(count)" : "").font(.caption.weight(.bold))
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.up)
                        } else {
                            Image(systemName: "plus.circle").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.card, in: .rect(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            header("Card details", "The last 4 digits are how Sortd matches bank emails and receipts to the right card. Only the last 4 — never the full number.")
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
            header("Log Apple Pay taps", "A one-time setup in Apple's Shortcuts app. Apple doesn't let apps do this part for you, so it takes about two minutes.")
            if #available(iOS 27.0, *) {
                WalletSetupGuide()
                    .padding(16)
                    .surface(radius: 16)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    miniStep(1, "Shortcuts → Automation → +", "Tap Wallet, choose your cards, then Run Immediately and Next.")
                    miniStep(2, "Create New Shortcut", "Search Sortd and tap Log Wallet Tap.")
                    miniStep(3, "Fill the blue word", "Tap Transaction, then pick Shortcut Input above the keyboard. It should look like this:")
                    actionMock.padding(.leading, 38)
                }
                .padding(16)
                .surface(radius: 16)
            }

            HStack(spacing: 10) {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.onBrand)
                        .background(Color.brand, in: .capsule)
                }
                Button { showingGuide = true } label: {
                    Text("Detailed Steps")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.ink)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            // Checks itself: turns green as soon as a tap arrives.
            HStack(spacing: 12) {
                if let t = firstTap {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color.up)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected").font(.headline)
                        Text("Logged \(Money.format(t.amount, t.currencyCode)) at \(t.merchant)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for your first tap").font(.headline)
                        Text("Pay for anything with Apple Pay and it shows up here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: 16)
            .padding(.top, 14)
            .animation(.snappy, value: tapConnected)
            .sensoryFeedback(.success, trigger: tapConnected)
        }
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
            header("Email receipts", "Connect Gmail and Sortd adds purchases from receipts and bank alerts — delivery, rides, app stores, online shops. Read-only, on this iPhone.")
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
            Button { connectingGmail = true } label: {
                Label(gmail.isEmpty ? "Connect Gmail" : "Connect Another Gmail", systemImage: "envelope")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(gmail.isEmpty ? Color.onBrand : Color.ink)
                    .background(gmail.isEmpty ? Color.brand : Color.clear, in: .capsule)
                    .overlay(Capsule().strokeBorder(gmail.isEmpty ? .clear : Color.secondary.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
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
                        subtitle: "Sortd shows what's left each day, after bills that are still due. Change it any time.")

            // One big amount, typed or picked.
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Money.symbol(home))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("0", text: $customBudget)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .keyboardType(.numberPad)
                        .focused($budgetFocused)
                        .fixedSize()
                        .onChange(of: customBudget) { _, text in
                            budget = Double(text.filter(\.isNumber)) ?? 0
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
            .padding(.vertical, 26)
            .surface(radius: 20)
            .animation(.snappy, value: budget)

            FlowLayout(spacing: 8) {
                ForEach(budgetPresets, id: \.self) { value in
                    Button {
                        budget = value
                        customBudget = String(Int(value))
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

            Button("No budget for now") {
                budget = 0
                customBudget = ""
                budgetFocused = false
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .padding(.top, 4)
        }
        .onAppear { if budget > 0, customBudget.isEmpty { customBudget = String(Int(budget)) } }
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
                   : "Picked from your answers. Apple Pay logging, adding by hand, your cards, budgets, export and delete stay free forever.")

            VStack(spacing: 0) {
                ForEach(Array(SetupProfile.proOrder(goals: goals, payment: payment).enumerated()), id: \.element) { index, feature in
                    if index > 0 { Divider().padding(.leading, 46) }
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.symbol)
                            .font(.body)
                            .frame(width: 32)
                            .foregroundStyle(Color.ink)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.subheadline.weight(.semibold))
                            Text(feature.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .surface(radius: 16)

            // How the trial works, said plainly: what happens today, and
            // what happens when it ends.
            if !pro.isPro, let trialText {
                VStack(alignment: .leading, spacing: 14) {
                    timelineRow("gift", "Today", "Everything in Pro unlocked. \(trialText.capitalized).")
                    timelineRow("calendar.badge.clock", "When the trial ends",
                                pro.product(ProStore.ID.yearly).map { "Your plan starts at \($0.displayPrice) a year." } ?? "Your plan starts.")
                    timelineRow("xmark.circle", "Any time before", "Cancel in the App Store and you pay nothing.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: .rect(cornerRadius: 16, style: .continuous))
                .padding(.top, 14)
            }
        }
    }

    private func timelineRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

    var needsPay = false

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
            HStack(spacing: 14) {
                preview
                VStack(alignment: .leading, spacing: 8) {
                    // Looks like a field so people know they can call it
                    // something they'll recognise ("Groceries card").
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nickname").font(.caption).foregroundStyle(.secondary)
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
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(missing ? "•• ····" : "•• \(CardEditor.fours(digits)[0])")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .opacity(0.8)
        }
        .foregroundStyle(isCredit ? Color.white : Color.ink)
        .padding(8)
        .frame(width: 92, height: 58, alignment: .leading)
        .background(isCredit ? Color.creditFill : Color.page, in: .rect(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(isCredit ? .clear : Color.secondary.opacity(0.35), lineWidth: 1))
        .animation(.snappy, value: isCredit)
        .accessibilityHidden(true)
    }

    private func digitRow(_ title: String, text: Binding<String>, required: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(required ? (title == "Apple Pay number" ? "Required — tells same-bank cards apart" : "Required") : "Recommended")
                    .font(.caption)
                    .foregroundStyle(required && text.wrappedValue.count < 4 ? Color.orange : Color.secondary)
            }
            Spacer()
            TextField("Last 4", text: text)
                .keyboardType(.numberPad)
                .onChange(of: text.wrappedValue) { _, new in
                    let clean = String(new.filter(\.isNumber).prefix(4))
                    if clean != new { text.wrappedValue = clean }
                }
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 90)
        }
        .padding(.horizontal, 14)
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
