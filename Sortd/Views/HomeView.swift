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
    /// What the last pull-to-refresh found.
    @State private var refreshNote: RefreshNote?
    @State private var confirmingClearDemo = false

    /// Writing the month through here is what makes the numericText
    /// transition on the total — and the rest of the page — actually run.
    private var animatedMonth: Binding<Date> {
        Binding(get: { month }, set: { new in withAnimation(.snappy) { month = new } })
    }

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
                            if !demo { FinishSetupCard() }
                            if demo && !Self.hideDemoBanner { demoBanner }
                            budgetCard
                            cards
                            UpcomingSection(recurring: recurring)
                            categories
                            recent
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .animation(.snappy, value: focused)
                    }
                    .refreshable { refreshNote = await RefreshNote.run(in: context) }
                }
            }
            .background(Color.page)
            .navigationTitle("Home")
            // Home draws its own title; the bar only carries the gear.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar(transactions.isEmpty || NavLayout.current == .toolbar ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                // Top right, where the header puts it on the full Home.
                ToolbarItem(placement: .topBarTrailing) {
                    if NavOption.current.gearOnHome {
                        Button("Settings", systemImage: "gearshape") { Router.shared.showingSettings = true }
                            .tint(Color.ink)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if NavLayout.current == .header || NavLayout.current == .toolbar {
                        Button("Add Purchase", systemImage: "plus") { showingAdd = true }
                            .tint(Color.ink)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(for: Card.self) { card in
                CardDetailView(card: card)
            }
            .sheet(isPresented: $showingAdd) { AddTransactionView() }
            // "add" links open from RootView (one add sheet for the whole
            // app); Home only handles its own budget sheet.
            .onChange(of: Router.shared.sheet, initial: true) { _, pending in
                guard pending == .budget else { return }
                showingBudget = true
                Router.shared.clearSheet()
            }
            .sheet(isPresented: $showingSetup) {
                NavigationStack { SetupGuideView(isPresentedAsSheet: true) }
            }
            .sheet(isPresented: $showingBudget) { BudgetSheet(budget: $budget) }
            .refreshNote($refreshNote, bottomPadding: 16)
        }
        .onCategoryLimitsChange {
            let now = CategoryBudgets.all()
            if now != limits { limits = now }
        }
    }

    /// Shown while the sample data is in: one tap removes it and reopens setup.
    /// Debug: SORTD_HIDE_DEMO_BANNER=1 for website and App Store screenshots.
    #if DEBUG
    static let hideDemoBanner = ProcessInfo.processInfo.environment["SORTD_HIDE_DEMO_BANNER"] == "1"
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
                Text("Clear it to set up Sortd with your own.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // One tap used to delete everything on screen and throw you back
            // into setup, with no warning and no way back.
            Button("Clear", role: .destructive) { confirmingClearDemo = true }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(Color.ink)
        }
        .padding(14)
        .surface(radius: 16)
        .confirmationDialog("Clear the sample data?", isPresented: $confirmingClearDemo, titleVisibility: .visible) {
            Button("Clear and Set Up Sortd", role: .destructive) {
                DemoData.clear(in: context)
                onboarded = false
            }
            Button("Keep Looking Around", role: .cancel) {}
        } message: {
            Text("The sample purchases go, and setup starts so you can add your own.")
        }
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

    /// A card takes a bit over half the screen, so the next one peeks the
    /// same amount on an SE and a Pro Max (216pt was right only for 402pt).
    static func cardWidth(_ screen: CGFloat) -> CGFloat { min(screen * 0.54, 300) }

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
                        Picker("Month", selection: animatedMonth) {
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
                if NavLayout.current != .toolbar, NavOption.current.gearOnHome { HStack(spacing: 10) {
                    Button { Router.shared.showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .tint(Color.ink)
                    .accessibilityLabel("Settings")
                    if NavLayout.current == .header {
                        RoundIconButton(symbol: "plus", label: "Add Purchase") { showingAdd = true }
                    }
                } }
            }
            .padding(.top, 8)

            Text(Money.format(monthItems.audTotal, Money.home, cents: false))
                .font(.system(size: totalSize, weight: .bold))
                .foregroundStyle(Color.ink)
                .monospacedDigit()
                .contentTransition(.numericText(value: monthItems.audTotal.double))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 6)
                .accessibilityLabel("Spent \(Money.spoken(monthItems.audTotal, Money.home))")
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
        // Category limits are Pro: a lapsed subscription hides the warning too.
        guard isCurrentMonth, !limits.isEmpty, ProStore.shared.isPro else { return nil }
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
        // Every time a bill still falls this month (a weekly one can be 4-5 times).
        let bills = recurring.stillToCharge(before: monthEnd, calendar: cal).double
        let perDay = max(0, left - bills) / Double(daysLeft)
        return "\(Money.format(Decimal(left), Money.home, cents: false)) left of \(b) · \(Money.format(Decimal(perDay), Money.home, cents: false)) a day"
    }

    // MARK: Budget card

    /// The bar's contents in words, for VoiceOver: the shares it draws plus
    /// the total, which the colours alone can't convey.
    private var breakdownSpoken: String {
        let top = byCategory.prefix(3)
            .map { "\($0.category.name), \(Money.spoken($0.total, Money.home))" }
            .joined(separator: ", ")
        return "\(top). Total \(Money.spoken(monthItems.audTotal, Money.home))."
    }

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
                    // Wraps instead of truncating on a small iPhone or at big text.
                    FlowLayout(spacing: 12) {
                        ForEach(byCategory.prefix(3), id: \.category) { c in
                            HStack(spacing: 5) {
                                Circle().fill(c.category.color).frame(width: 7, height: 7)
                                Text(c.category.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
                .surface()
            }
            .buttonStyle(.plain)
            // `.combine` read out only the three category names — no amounts,
            // no total. This is the app's main spending breakdown, so it says
            // what it shows.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Where this month went")
            .accessibilityValue(breakdownSpoken)
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
            SectionHeader(title: "Your Cards")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { tab = .activity } label: {
                        WalletCard(card: nil, transactions: monthItems)
                            .containerRelativeFrame(.horizontal) { w, _ in Self.cardWidth(w) }
                    }
                    .buttonStyle(CardPressStyle())
                    .id("all")
                    ForEach(ranked, id: \.0) { card, items in
                        NavigationLink(value: card) {
                            WalletCard(card: card, transactions: items)
                                .containerRelativeFrame(.horizontal) { w, _ in Self.cardWidth(w) }
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
                SectionHeader(title: title("Where It Went")) { tab = .insights }
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
                        .accessibilityLabel("\(row.category.name), \(Money.spoken(row.total, Money.home)), \(row.count == 1 ? "1 purchase" : "\(row.count) purchases")")
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
                                    Divider().padding(.leading, 64)
                                }
                            }
                        }
                        .surface()
                    }
                }
            }
        }
    }

    /// Straight after setup: a welcome, the same checklist the plan showed,
    /// and a way to add the first purchase by hand.
    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to Sortd").font(.title.weight(.bold))
                    BrandBar(width: 14, height: 3)
                    Text("Your purchases show up here.").font(.body).foregroundStyle(.secondary)
                }
                FinishSetupCard(canHide: false)
                Button { showingAdd = true } label: {
                    HStack(spacing: 12) {
                        RowIcon("square.and.pencil")
                        Text("Add a Purchase").font(.body).foregroundStyle(Color.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
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

/// Section title with an optional "See All".
/// Bold black section title, like the headings in setup ("Your Cards").
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
                    Text("See All").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .frame(minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See All, \(title)")
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
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .opacity(0.75)
                }
            }
            .font(.subheadline.weight(.semibold))

            Spacer(minLength: 12)

            Text(Money.format(total, Money.home))
                .font(.moneySmall)
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
        .accessibilityLabel("\(card?.name ?? "All cards"), \(Money.spoken(total, Money.home)) this month, \(transactions.count == 1 ? "1 purchase" : "\(transactions.count) purchases")")
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

/// Kept as a name for the two card call sites; the behaviour is now the
/// app-wide press so a card and a button feel the same under a finger.
typealias CardPressStyle = PressableButtonStyle

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
            case .quarter: "Previous 3 months"
            }
        }
    }

    @State private var range: Range = .month
    @State private var selected: Date?
    /// Chart and empty-bars heights grow with Dynamic Type so the axis labels keep room.
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 190
    @ScaledMetric(relativeTo: .caption) private var placeholderHeight: CGFloat = 180

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
                        .chip(selected: r == range)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityLabel(r.title)
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
                PlaceholderBars().frame(height: placeholderHeight)
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
                    .accessibilityLabel(p.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .accessibilityValue(Money.spoken(Decimal(p.total), Money.home))
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
        .frame(height: chartHeight)
        .sensoryFeedback(.selection, trigger: selected.map { cal.startOfDay(for: $0) })
        .accessibilityLabel("Running total, \(range.title.lowercased())")
        .accessibilityValue("\(Money.spoken(Decimal(current.last?.total ?? 0), Money.home)) so far. \(range.previousLabel) total \(Money.spoken(Decimal(previous.last?.total ?? 0), Money.home)).")
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
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
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
    }
}
