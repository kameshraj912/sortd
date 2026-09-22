import SwiftUI
import SwiftData
import Charts

/// Home, after Raj's reference: month picker and a big centred total,
/// a budget card with a colour-split bar (one colour per category), the two
/// cards, top categories, then a plain dated list of purchases.
struct HomeView: View {
    @Binding var tab: AppTab
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @AppStorage("monthlyBudget") private var budget: Double = 0
    @State private var month: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var showingAdd = false
    @State private var showingSetup = false
    @State private var showingBudget = false
    @State private var limits: [SpendCategory: Double] = [:]
    @AppStorage(DemoData.activeKey) private var demo = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(OnboardingView.doneKey) private var onboarded = true
    @Environment(\.modelContext) private var context
    /// Card in view in the carousel: "all" or a Card rawValue.
    @State private var focused: String? = "all"
    @ScaledMetric(relativeTo: .largeTitle) private var totalSize: CGFloat = 52

    // MARK: Pull-to-refresh and celebrations
    @State private var refreshStatus: RefreshStatusLine.State?
    @State private var refreshHaptic = 0
    @State private var confettiTrigger = 0
    @State private var celebrationHaptic = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cal: Calendar { .current }
    private var isCurrentMonth: Bool { cal.isDate(month, equalTo: .now, toGranularity: .month) }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            header
                            // Only actually in the layout while non-nil, so it
                            // doesn't leave a gap the rest of the time.
                            if let refreshStatus { RefreshStatusLine(state: refreshStatus) }
                            if demo && !Self.hideDemoBanner { demoBanner }
                            budgetCard
                            cards
                            UpcomingSection(recurring: recurring)
                            categories
                            recent
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                    .clearsTabBar()
                    .refreshable { await refresh() }
                }
            }
            .background(Color.page)
            // A Gmail connect or sync that's still going, or that stopped.
            .safeAreaInset(edge: .bottom) { GmailStatusBanner() }
            .navigationTitle("Home")
            .toolbar(transactions.isEmpty ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Purchase", systemImage: "plus") { showingAdd = true }
                        .tint(Color.ink)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(for: Card.self) { card in
                CardDetailView(card: card)
            }
            .sheet(isPresented: $showingAdd) { AddTransactionView() }
            .onChange(of: Router.shared.sheet, initial: true) { _, pending in
                switch pending {
                case .add: showingAdd = true
                case .budget: showingBudget = true
                case nil: return
                }
                Router.shared.clearSheet()
            }
            .sheet(isPresented: $showingSetup) {
                NavigationStack { SetupGuideView(isPresentedAsSheet: true) }
            }
            .sheet(isPresented: $showingBudget) { BudgetSheet(budget: $budget) }
            .animation(.snappy, value: refreshStatus)
        }
        .onCategoryLimitsChange {
            let now = CategoryBudgets.all()
            if now != limits { limits = now }
        }
        // Confetti draws over the whole screen, not just the scroll content.
        .overlay { ConfettiView(trigger: confettiTrigger).ignoresSafeArea() }
        .sensoryFeedback(.success, trigger: refreshHaptic)
        .sensoryFeedback(.success, trigger: celebrationHaptic)
        .task { checkBudgetWinCelebration() }
        .onChange(of: transactions) { _, _ in checkFirstTapCelebration() }
        .task { checkFirstTapCelebration() }
        #if DEBUG
        .task { debugConfettiIfNeeded() }
        #endif
    }

    // MARK: Pull-to-refresh

    private func refresh() async {
        // .refreshable already prevents overlapping pulls on the same view;
        // RefreshCoordinator also covers a pull racing the app-active sync.
        refreshStatus = .refreshing
        let result = await RefreshCoordinator.refresh(in: context)
        let shown: RefreshStatusLine.State = result.newPurchases > 0 ? .newPurchases(result.newPurchases) : .upToDate
        refreshStatus = shown
        refreshHaptic += 1
        try? await Task.sleep(for: .seconds(2))
        // Another pull may have already replaced this status; only clear our own.
        if refreshStatus == shown { refreshStatus = nil }
    }

    // MARK: Celebrations

    /// Once per finished month: confetti the first time the app opens after
    /// a month closed at or under the monthly budget.
    private func checkBudgetWinCelebration() {
        guard budget > 0, let finishedMonth = cal.date(byAdding: .month, value: -1, to: .now) else { return }
        let interval = cal.dateInterval(of: .month, for: finishedMonth)
        let total = transactions.filter { interval?.contains($0.date) ?? false }.audTotal
        let already = CelebrationFlags.celebratedBudgetMonths()
        guard Celebrations.shouldCelebrateBudgetWin(finishedMonthTotal: total, budget: budget, now: .now,
                                                     finishedMonth: finishedMonth, alreadyCelebrated: already,
                                                     calendar: cal) else { return }
        CelebrationFlags.markBudgetMonthCelebrated(Celebrations.monthKey(finishedMonth, calendar: cal))
        celebrate()
    }

    /// The first Apple Pay tap ever, whichever screen sees it first —
    /// Onboarding's "Connected" moment, or (if onboarding was skipped) here.
    private func checkFirstTapCelebration() {
        let hasTap = transactions.contains { $0.seenIn.contains(.tap) }
        guard Celebrations.shouldCelebrateFirstTap(hasTapTransaction: hasTap,
                                                    alreadyCelebrated: CelebrationFlags.firstTapCelebrated()) else { return }
        CelebrationFlags.markFirstTapCelebrated()
        celebrate()
    }

    private func celebrate() {
        guard !reduceMotion else { return }
        confettiTrigger += 1
        celebrationHaptic += 1
    }

    #if DEBUG
    /// SPEND_CONFETTI=1: fire a budget-win celebration once at launch, so a
    /// screen recording can show it without waiting for a real month to end.
    private func debugConfettiIfNeeded() {
        guard ProcessInfo.processInfo.environment["SPEND_CONFETTI"] == "1" else { return }
        celebrate()
    }
    #endif

    /// Shown while the sample data is in: one tap removes it and reopens setup.
    /// Debug: SPEND_HIDE_DEMO_BANNER=1 for website and App Store screenshots.
    #if DEBUG
    static let hideDemoBanner = ProcessInfo.processInfo.environment["SPEND_HIDE_DEMO_BANNER"] == "1"
    #else
    static let hideDemoBanner = false
    #endif

    private var demoBanner: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Image(systemName: "sparkles").foregroundStyle(Color.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're looking at sample data").font(.subheadline.weight(.semibold))
                Text("Clear it when you're ready to use your own.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Clear") {
                DemoData.clear(in: context)
                onboarded = false
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Color.ink)
        }
        .padding(14)
        .surface(radius: 16)
    }

    // MARK: Data

    private var monthItems: [Transaction] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        return transactions.filter { interval.contains($0.date) }
    }

    /// Spend per category this month, biggest first.
    private var byCategory: [(category: SpendCategory, total: Decimal, count: Int)] {
        Self.categoryRows(monthItems)
    }

    private static func categoryRows(_ items: [Transaction]) -> [(category: SpendCategory, total: Decimal, count: Int)] {
        Dictionary(grouping: items, by: \.category)
            .map { ($0.key, $0.value.audTotal, $0.value.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    /// Subscriptions and bills, from all history (not just this month).
    private var recurring: [Recurring] { transactions.recurring() }

    /// The card swiped into view, nil for all cards.
    private var focusedCard: Card? {
        guard let focused, focused != "all" else { return nil }
        return Card(rawValue: focused)
    }

    /// This month's purchases on the card in view.
    private var cardItems: [Transaction] {
        guard let card = focusedCard else { return monthItems }
        return monthItems.filter { $0.card == card }
    }

    private var lastTwelveMonths: [Date] {
        let start = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        return (0..<12).compactMap { cal.date(byAdding: .month, value: -$0, to: start) }
    }

    // MARK: Header

    /// Setup-style title: the month (tap to change), logo bar, a round "+",
    /// then the big total and one plain line about the budget.
    private var header: some View {
        let spent = monthItems.audTotal.double
        let over = budget > 0 && spent > budget
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Menu {
                        Picker("Month", selection: $month) {
                            ForEach(lastTwelveMonths, id: \.self) { m in
                                Text(m.formatted(.dateTime.month(.wide).year())).tag(m)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(isCurrentMonth ? month.formatted(.dateTime.month(.wide)) : month.formatted(.dateTime.month(.wide).year()))
                            Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                        }
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.ink)
                    }
                    .accessibilityLabel("Month, \(month.formatted(.dateTime.month(.wide).year()))")
                    BrandBar(width: 14, height: 3)
                }
                Spacer()
                RoundIconButton(symbol: "plus", label: "Add Purchase") { showingAdd = true }
            }
            .padding(.top, 8)

            Text(Money.format(monthItems.audTotal, Money.home, cents: false))
                .font(.system(size: totalSize, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 6)
                .accessibilityLabel("Spent \(Money.format(monthItems.audTotal, Money.home))")
            Button { showingBudget = true } label: {
                HStack(spacing: 4) {
                    Text(budgetLine(spent: spent))
                    if budget == 0 { Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                }
                .font(.subheadline.weight(over ? .semibold : .regular))
                .foregroundStyle(over ? Color.down : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit your monthly budget")
            if let line = overLimitLine {
                Button { tab = .insights } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(line)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.down)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows your categories")
            }
        }
    }

    /// One line about categories over their limit, this month only.
    private var overLimitLine: String? {
        guard isCurrentMonth, !limits.isEmpty else { return nil }
        let over = CategoryBudgets.progress(for: monthItems, limits: limits)
            .filter { $0.value.status == .over }
            .sorted { $0.value.left < $1.value.left }
        guard let worst = over.first else { return nil }
        if over.count == 1 {
            return "\(worst.key.name) is \(Money.format(Decimal(-worst.value.left), Money.home, cents: false)) over its limit"
        }
        return "\(worst.key.name) and \(over.count - 1) more are over their limits"
    }

    private func budgetLine(spent: Double) -> String {
        guard budget > 0 else { return "Set a monthly budget" }
        let left = budget - spent
        let b = Money.format(Decimal(budget), Money.home, cents: false)
        if left < 0 { return "\(Money.format(Decimal(-left), Money.home, cents: false)) over your \(b) budget" }
        guard isCurrentMonth else { return "\(Money.format(Decimal(left), Money.home, cents: false)) under your \(b) budget" }
        let daysLeft = max(1, (cal.range(of: .day, in: .month, for: .now)?.count ?? 30) - cal.component(.day, from: .now) + 1)
        let monthEnd = cal.dateInterval(of: .month, for: .now)?.end ?? .now
        let bills = recurring.filter { $0.status == .active && $0.nextDate < monthEnd }.reduce(0) { $0 + $1.audAmount.double }
        let perDay = max(0, left - bills) / Double(daysLeft)
        return "\(Money.format(Decimal(left), Money.home, cents: false)) left of \(b) · \(Money.format(Decimal(perDay), Money.home, cents: false)) a day"
    }

    // MARK: Budget card

    /// Where this month went, as one colour bar with a small key.
    @ViewBuilder
    private var budgetCard: some View {
        let spent = monthItems.audTotal.double
        let segments = byCategory.map {
            SegmentedBar.Segment(id: $0.category.rawValue, value: $0.total.double, color: $0.category.color)
        }
        if !segments.isEmpty {
            Button { showingBudget = true } label: {
                VStack(alignment: .leading, spacing: 10) {
                    SegmentedBar(segments: segments, total: max(budget, spent), height: 10)
                    HStack(spacing: 12) {
                        ForEach(byCategory.prefix(3), id: \.category) { c in
                            HStack(spacing: 5) {
                                Circle().fill(c.category.color).frame(width: 7, height: 7)
                                Text(c.category.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .padding(16)
                .surface(radius: 18)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edit your monthly budget")
        }
    }

    // MARK: Cards

    /// Cards as a swipeable row, like Wallet: "All cards" first, then most
    /// spent. Categories and Transactions below follow the card in view.
    private var cards: some View {
        let ranked = Card.mine
            .map { card in (card, monthItems.filter { $0.card == card }) }
            .sorted { $0.1.audTotal > $1.1.audTotal }
        let ids = ["all"] + ranked.map(\.0.rawValue)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your cards")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { tab = .activity } label: {
                        WalletCard(card: nil, transactions: monthItems)
                            .frame(width: 216)
                    }
                    .buttonStyle(CardPressStyle())
                    .id("all")
                    ForEach(ranked, id: \.0) { card, items in
                        NavigationLink(value: card) {
                            WalletCard(card: card, transactions: items)
                                .frame(width: 216)
                        }
                        .buttonStyle(CardPressStyle())
                        .id(card.rawValue)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focused, anchor: .leading)
            .scrollClipDisabled()
            .sensoryFeedback(.selection, trigger: focused)

            // Page dots, like Wallet.
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    Capsule()
                        .fill(id == (focused ?? "all") ? Color.ink : Color.track)
                        .frame(width: id == (focused ?? "all") ? 16 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: focused)
            .accessibilityHidden(true)
        }
    }

    /// "Categories" or "Categories · SC Debit".
    private func title(_ base: String) -> String {
        guard let card = focusedCard else { return base }
        return "\(base) · \(card.shortLabel)"
    }

    // MARK: Categories

    @ViewBuilder
    private var categories: some View {
        let rows = Array(Self.categoryRows(cardItems).prefix(4))
        if rows.isEmpty {
            Text(focusedCard == nil ? "No purchases this month." : "Nothing on this card this month.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
                .surface()
        } else {
            let top = rows[0].total.double
            VStack(spacing: 10) {
                SectionHeader(title: title("Where it went")) { tab = .insights }
                VStack(spacing: 0) {
                    ForEach(rows, id: \.category) { row in
                        HStack(spacing: 14) {
                            CategoryIcon(category: row.category, size: 40)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.category.name)
                                        .font(.body)
                                    Spacer()
                                    Text(Money.format(row.total, Money.home))
                                        .font(.body)
                                        .monospacedDigit()
                                }
                                SegmentedBar(segments: [.init(id: "v", value: row.total.double, color: row.category.color)],
                                             total: top, height: 5)
                                Text(row.count == 1 ? "1 purchase" : "\(row.count) purchases")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.category.name), \(Money.format(row.total, Money.home)), \(row.count) purchases")
                    }
                }
                .padding(.vertical, 4)
                .surface()
            }
        }
    }

    // MARK: Recent (Budgeta-style dated list)

    @ViewBuilder
    private var recent: some View {
        let items = Array(cardItems.prefix(10))
        if !items.isEmpty {
            let days = Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title("Recent")) { tab = .activity }
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    let rows = days[day] ?? []
                    VStack(alignment: .leading, spacing: 6) {
                        Text(DayTitle.text(day))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        VStack(spacing: 0) {
                            ForEach(rows) { t in
                                NavigationLink {
                                    TransactionDetailView(transaction: t)
                                } label: {
                                    TransactionRow(transaction: t, showTime: true)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                if t.id != rows.last?.id {
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }
                        .surface()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Purchases Yet", systemImage: "creditcard")
        } description: {
            Text("Set up the Apple Pay automation once, and every tap lands here by itself.")
        } actions: {
            Button("Set Up Auto-Logging") { showingSetup = true }
                .buttonStyle(.borderedProminent).tint(Color.brand).foregroundStyle(Color.onBrand)
            Button("Add a Purchase") { showingAdd = true }
        }
    }
}

/// "Today", "Yesterday", "Wednesday, 16 September".
enum DayTitle {
    static func text(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// Section title with an optional "See all".
/// Bold black section title, like the headings in setup ("Your cards").
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action: action) {
                    Text("See all").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .frame(minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all, \(title)")
            }
        }
    }
}

/// Page title in the setup style: left-aligned, bold, with the logo bar.
struct PageTitle<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                BrandBar(width: 14, height: 3)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.top, 8)
    }
}

extension PageTitle where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Round black "+" (or other symbol) button, as on the new Home.
struct RoundIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 44, height: 44)
                .background(Color.brand, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Card stack

/// A card drawn like Apple Card: its colours come from what it was spent
/// on this month (category colours, sized by share). Unused cards are grey.
/// `card == nil` is the "All cards" summary.
struct WalletCard: View {
    let card: Card?
    let transactions: [Transaction]
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("cardStyle") private var styleRaw = SpendGradient.Style.satin.rawValue
    var styleOverride: SpendGradient.Style?

    private var style: SpendGradient.Style { styleOverride ?? SpendGradient.Style(rawValue: styleRaw) ?? .satin }
    private var used: Bool { transactions.audTotal > 0 }
    private var name: String { card?.shortLabel ?? "All cards" }

    var body: some View {
        let total = transactions.audTotal
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let card {
                    Text(card.flag)
                } else {
                    Image(systemName: "square.stack.fill")
                }
                Text(name)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let card, !typeSize.isAccessibilitySize,
                   !card.shortLabel.localizedCaseInsensitiveContains(card.isCredit ? "credit" : "debit") {
                    Text(card.isCredit ? "CREDIT" : "DEBIT")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .opacity(0.75)
                }
            }
            .font(.subheadline.weight(.semibold))

            Spacer(minLength: 12)

            Text(Money.format(total, Money.home))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.caption.weight(.medium))
                .opacity(0.85)
                .lineLimit(1)
        }
        .foregroundStyle(style.systemFace ? Color.primary
                         : style.lightFace ? Color(white: 0.1)
                         : (used || style.isPlain ? Color.white : Color.primary.opacity(0.7)))
        .shadow(color: .black.opacity((used || style.isPlain) && !style.lightFace && !style.systemFace ? 0.18 : 0), radius: 3, y: 1)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(typeSize.isAccessibilitySize ? nil : 1.586, contentMode: .fit)
        .background { SpendGradient(transactions: transactions, style: style) }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style.systemFace ? Color.hairline : .white.opacity(used ? 0.25 : 0),
                              lineWidth: style.systemFace ? 1 : 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card?.name ?? "All cards"), \(Money.format(total, Money.home)) this month, \(transactions.count) purchases")
        .accessibilityHint(card == nil ? "Shows all purchases" : "Shows this card's purchases")
    }

    private var subtitle: String {
        let n = transactions.count
        guard n > 0 else { return "Not used this month" }
        let count = "\(n) \(n == 1 ? "purchase" : "purchases")"
        // Like Wise: a card billed in another currency also shows what was
        // spent in that currency.
        guard let card, card.homeCurrency != Money.home else { return count }
        let own = transactions.filter { $0.currencyCode == card.homeCurrency }
        guard !own.isEmpty else { return count }
        let local = own.reduce(Decimal(0)) { $0 + $1.amount }
        return "\(count) · \(Money.format(local, card.homeCurrency))"
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Chart

/// Running total for the period (solid), last period at the same point
/// (dashed), and the budget line — the way money apps show spending, not
/// Screen Time bars. Drag along the line to read any day.
struct SpendChart: View {
    let transactions: [Transaction]
    @AppStorage("monthlyBudget") private var budget: Double = 0

    enum Range: String, CaseIterable, Identifiable {
        case week = "1W", month = "1M", quarter = "3M"
        var id: Self { self }

        var title: String {
            switch self {
            case .week: "This week"
            case .month: "This month"
            case .quarter: "Last 3 months"
            }
        }

        var previousLabel: String {
            switch self {
            case .week: "Last week"
            case .month: "Last month"
            case .quarter: "3 months before"
            }
        }
    }

    @State private var range: Range = .month
    @State private var selected: Date?

    private struct Point: Identifiable {
        let date: Date
        let total: Double
        var id: Date { date }
    }

    private var cal: Calendar { .current }

    private var interval: DateInterval {
        switch range {
        case .week:
            return cal.dateInterval(of: .weekOfYear, for: .now) ?? DateInterval(start: .now, duration: 1)
        case .month:
            return cal.dateInterval(of: .month, for: .now) ?? DateInterval(start: .now, duration: 1)
        case .quarter:
            let month = cal.dateInterval(of: .month, for: .now) ?? DateInterval(start: .now, duration: 1)
            let start = cal.date(byAdding: .month, value: -2, to: month.start) ?? month.start
            return DateInterval(start: start, end: month.end)
        }
    }

    private var previousStart: Date {
        let back: DateComponents = switch range {
        case .week: DateComponents(weekOfYear: -1)
        case .month: DateComponents(month: -1)
        case .quarter: DateComponents(month: -3)
        }
        return cal.date(byAdding: back, to: interval.start) ?? interval.start
    }

    /// Cumulative spend per day from `start`, for `days` days, plotted on
    /// the current period's dates so the two lines line up.
    private func series(from start: Date, days: Int) -> [Point] {
        var byDay: [Int: Double] = [:]
        for t in transactions {
            let offset = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: t.date)).day ?? -1
            if offset >= 0 && offset < days, t.category != .transfers { byDay[offset, default: 0] += t.audValue.double }
        }
        var running = 0.0
        return (0..<days).compactMap { i in
            running += byDay[i] ?? 0
            guard let d = cal.date(byAdding: .day, value: i, to: interval.start) else { return nil }
            return Point(date: d, total: running)
        }
    }

    private var totalDays: Int {
        max(1, cal.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
    }

    private var daysSoFar: Int {
        min(totalDays, (cal.dateComponents([.day], from: interval.start, to: .now).day ?? 0) + 1)
    }

    private var current: [Point] { series(from: interval.start, days: daysSoFar) }
    private var previous: [Point] { series(from: previousStart, days: totalDays) }

    private var showBudget: Bool { range == .month && budget > 0 }

    /// Fit the y-axis to the lines (and the budget), with a little headroom.
    private var yMax: Double {
        let top = max(current.last?.total ?? 0, previous.last?.total ?? 0, showBudget ? budget : 0)
        return max(10, top * 1.12)
    }

    var body: some View {
        let now = current.last?.total ?? 0
        let prevSameDay = previous.dropFirst(max(0, daysSoFar - 1)).first?.total ?? 0
        let point = selected.flatMap { d in current.first { cal.isDate($0.date, inSameDayAs: d) } }

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(point.map { $0.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? range.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Range.allCases) { r in
                        Button(r.rawValue) {
                            withAnimation(.snappy) { range = r; selected = nil }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .chip(selected: r == range)
                        .accessibilityAddTraits(r == range ? .isSelected : [])
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Money.format(Decimal(point?.total ?? now), Money.home))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if point == nil, prevSameDay > 0 {
                    let diff = now - prevSameDay
                    Label("\(Money.format(Decimal(abs(diff)), Money.home, cents: false)) \(diff >= 0 ? "more" : "less") than \(range.previousLabel.lowercased()) by now",
                          systemImage: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(diff >= 0 ? Color.down : Color.up)
                }
            }

            if now == 0 && previous.last?.total ?? 0 == 0 {
                PlaceholderBars().frame(height: 180)
            } else {
                chart
            }

            legend
        }
        .padding(18)
        .surface()
    }

    private var chart: some View {
        Chart {
            ForEach(previous) { p in
                LineMark(x: .value("Day", p.date), y: .value("Spent", p.total), series: .value("Period", "previous"))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .interpolationMethod(.monotone)
            }
            ForEach(current) { p in
                AreaMark(x: .value("Day", p.date), y: .value("Spent", p.total))
                    .foregroundStyle(Color.ink.opacity(0.06))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", p.date), y: .value("Spent", p.total), series: .value("Period", "current"))
                    .foregroundStyle(Color.ink)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = current.last, selected == nil {
                PointMark(x: .value("Day", last.date), y: .value("Spent", last.total))
                    .foregroundStyle(Color.ink)
                    .symbolSize(60)
            }
            if showBudget {
                RuleMark(y: .value("Budget", budget))
                    .foregroundStyle(Color.down.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("Budget \(Money.format(Decimal(budget), Money.home, cents: false))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.down)
                    }
            }
            if let d = selected, let p = current.first(where: { cal.isDate($0.date, inSameDayAs: d) }) {
                RuleMark(x: .value("Day", p.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                PointMark(x: .value("Day", p.date), y: .value("Spent", p.total))
                    .foregroundStyle(Color.ink)
                    .symbolSize(70)
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...yMax)
        .chartXSelection(value: $selected)
        .chartXAxis {
            switch range {
            case .week:
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(d.formatted(.dateTime.weekday(.narrow))) }
                    }
                }
            case .month:
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(d.formatted(.dateTime.day().month(.abbreviated))) }
                    }
                }
            case .quarter:
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(d.formatted(.dateTime.month(.abbreviated))) }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.hairline)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Money.format(Decimal(v), Money.home, cents: false)) }
                }
            }
        }
        .frame(height: 190)
        .sensoryFeedback(.selection, trigger: selected.map { cal.startOfDay(for: $0) })
        .accessibilityLabel("Running total, \(range.title.lowercased())")
        .accessibilityValue("\(Money.format(Decimal(current.last?.total ?? 0), Money.home)) so far. \(range.previousLabel) total \(Money.format(Decimal(previous.last?.total ?? 0), Money.home)).")
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(range.title, style: StrokeStyle(lineWidth: 2.5), color: .ink)
            legendItem(range.previousLabel, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]), color: .secondary)
            if showBudget {
                legendItem("Budget", style: StrokeStyle(lineWidth: 1, dash: [2, 3]), color: .down)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ title: String, style: StrokeStyle, color: Color) -> some View {
        HStack(spacing: 6) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 18, y: 4)) }
                .stroke(color, style: style)
                .frame(width: 18, height: 8)
            Text(title)
        }
    }
}

/// The setup-style title as the first row of a List page. Pair with
/// `.brandedTitle(_:)` so the navigation bar doesn't repeat it.
struct ListPageTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        Section {
            PageTitle(title: title, subtitle: subtitle)
                // Bottom 14, not 4: the section clips to a rounded corner, and
                // a smaller inset cut the first letter of the last line.
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 14, trailing: 4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

extension View {
    /// Keeps the title for Back buttons and VoiceOver but doesn't show it in
    /// the bar: the page shows its own bold title with the logo bar.
    func brandedTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            // Lists add their own gap under the bar; the page title is the gap.
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(.compact)
            .clearsTabBar()
    }

    /// Lets the last row scroll up above the flat tab bar. Neither the bar's
    /// safe-area inset nor content margins set on the tab reach a scroll view
    /// inside a NavigationStack, so each page's scroll view sets it itself;
    /// `brandedTitle` already does. Zero outside the tabs.
    func clearsTabBar() -> some View {
        modifier(TabBarClearance())
    }

    /// For a root tab page with no navigation bar (Settings, Insights).
    /// Hiding the bar also dropped its scroll-edge blur, so the page title
    /// scrolled straight under the clock and Dynamic Island. An empty
    /// safe-area bar brings the system blur back without adding any height.
    func hidesNavigationBar(_ hidden: Bool = true) -> some View {
        toolbar(hidden ? .hidden : .visible, for: .navigationBar)
            .safeAreaBar(edge: .top, spacing: 0) { Color.clear.frame(height: 0) }
    }
}

extension EnvironmentValues {
    /// Height of the flat tab bar over the current tab, 0 elsewhere.
    @Entry var tabBarClearance: CGFloat = 0
}

private struct TabBarClearance: ViewModifier {
    @Environment(\.tabBarClearance) private var clearance

    func body(content: Content) -> some View {
        content.contentMargins(.bottom, clearance, for: .scrollContent)
    }
}
