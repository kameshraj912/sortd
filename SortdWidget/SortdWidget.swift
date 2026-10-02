import WidgetKit
import SwiftUI

/// Sortd's widgets. Six on the Home Screen, plus the Lock Screen.
///
/// It started as seven, was cut to three on purpose, and grew to six on
/// 2 Oct 2026. Apple's guidance is blunt about this: build the widget that
/// best represents the content rather than one for every idea. The three
/// that were kept each answer a real question:
///
///   Spending  — am I okay today, and for the rest of the month?
///   Quick Add — log it now, before I forget (the thing that kills trackers)
///   Bills     — what's about to charge me?
///
/// Recent purchases and the category breakdown were cut because both are
/// "look back" screens, and looking back is what opening the app is for.
/// Raj then approved three more from mockups, and with them reversed the
/// privacy decision that came with the cut (widgets showed no shop names):
///
///   Budget ring   — how much of this month's budget is left?
///   Today         — today's total, and what I last paid for
///   Recent        — the last three purchases, each opening its detail
///
/// The rule that goes with it: shop names AND amounts are hidden while the
/// iPhone is locked (`.privacySensitive()`). Amounts still honour Settings ›
/// "Show Amounts When Locked"; shop names are hidden whatever that says.
///
/// None of them opens the database. They read the small summary file the app
/// leaves in the App Group container, so a home screen tile can never get in
/// the way of the real data.

// MARK: - Timeline

struct SortdEntry: TimelineEntry {
    var date: Date
    var summary: WidgetSummary?

    /// What the widget gallery shows. Real-looking, so the preview is honest.
    static let sample = SortdEntry(date: .now, summary: {
        var s = WidgetSummary()
        s.currency = "AUD"
        s.today = Decimal(string: "43.10")!
        s.week = Decimal(string: "213.55")!
        s.month = Decimal(string: "812.40")!
        s.budget = 1500
        s.leftThisMonth = Decimal(string: "687.60")!
        s.perDay = Decimal(string: "45.84")!
        s.dayAllowance = Decimal(50)
        s.hasAnyPurchases = true
        s.todayCount = 3
        s.recent = [
            .init(merchant: "Seven Seeds", amount: Decimal(string: "5.50")!, currency: "AUD",
                  category: "eatingOut", date: .now.addingTimeInterval(-25 * 60)),
            .init(merchant: "Woolworths Metro", amount: Decimal(string: "23.10")!, currency: "AUD",
                  category: "groceries", date: .now.addingTimeInterval(-3 * 3600)),
            .init(merchant: "myki", amount: Decimal(string: "14.50")!, currency: "AUD",
                  category: "transport", date: .now.addingTimeInterval(-5 * 3600)),
        ]
        s.categories = [
            .init(category: "groceries", name: "Groceries", total: Decimal(string: "312.10")!),
            .init(category: "eatingOut", name: "Eating Out", total: Decimal(string: "204.80")!),
            .init(category: "transport", name: "Transport", total: Decimal(string: "155.50")!),
            .init(category: "subscriptions", name: "Subscriptions", total: Decimal(string: "88.00")!),
            .init(category: "shopping", name: "Shopping", total: Decimal(string: "52.00")!),
        ]
        s.bills = [
            .init(name: "Netflix", amount: Decimal(string: "18.99")!, currency: "AUD", due: .now.addingTimeInterval(86400)),
            .init(name: "Spotify", amount: Decimal(string: "13.99")!, currency: "AUD", due: .now.addingTimeInterval(5 * 86400)),
            .init(name: "Rent", amount: Decimal(380), currency: "AUD", due: .now.addingTimeInterval(9 * 86400)),
        ]
        return s
    }())
}

struct SortdProvider: TimelineProvider {
    func placeholder(in context: Context) -> SortdEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (SortdEntry) -> Void) {
        completion(context.isPreview ? .sample : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SortdEntry>) -> Void) {
        // Today's total stops being true at midnight (asOf zeroes it). During
        // the day the app refreshes the widget after every save, including taps
        // logged by Shortcuts while the app is closed.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [current()], policy: .after(midnight)))
    }

    private func current() -> SortdEntry {
        SortdEntry(date: .now, summary: WidgetSummary.readNow())
    }
}

/// Dresses a widget in the chosen look.
///
/// This has to set the content's scheme and the card behind it from the same
/// value. `containerBackground` is read outside the view it decorates, so
/// setting only the environment gave a dark widget a white card — black
/// text on black, white text on white, depending which half you looked at.
private struct Chrome<Content: View>: View {
    var look: SortdLook
    @Environment(\.colorScheme) private var systemScheme
    @ViewBuilder var content: Content

    private var scheme: ColorScheme { look.colorScheme ?? systemScheme }

    var body: some View {
        content
            .environment(\.colorScheme, scheme)
            .containerBackground(Sortd.card(scheme), for: .widget)
    }
}

// MARK: - Shared pieces

/// Sortd's mark: the four dashes that sit under every title in the app.
/// Small enough to be a signature rather than decoration.
private struct BrandMark: View {
    var width: CGFloat = 9
    var height: CGFloat = 2.5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Sortd.brandPalette.indices, id: \.self) { i in
                Capsule().fill(Sortd.brandPalette[i]).frame(width: width, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A header line with the brand mark under it.
private struct Heading: View {
    var text: String
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let trailing {
                    Text(trailing)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            BrandMark()
        }
    }
}

/// The spending bar, in category colours — the same idea as the bar on Home.
/// Each category takes its share of the budget; the rest is empty track.
/// Over budget it fills completely and the label says so, because a widget
/// can be shown desaturated and colour alone must never carry the meaning.
private struct SpendBar: View {
    var slices: [WidgetSummary.Slice]
    var spent: Decimal
    var limit: Decimal?
    var height: CGFloat = 8

    private var spentValue: Double { (spent as NSDecimalNumber).doubleValue }
    private var limitValue: Double {
        guard let limit, limit > 0 else { return spentValue }
        return (limit as NSDecimalNumber).doubleValue
    }

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.width
            // Over the limit, the coloured part takes the whole bar.
            let scale = spentValue > limitValue ? spentValue : limitValue
            HStack(spacing: 1.5) {
                ForEach(slices) { slice in
                    Rectangle()
                        .fill(Sortd.color(forCategory: slice.category))
                        .frame(width: width(for: slice, in: full, scale: scale))
                }
                Spacer(minLength: 0)
            }
            // Accented (tinted Home Screen) rendering drops every colour and
            // keeps only two groups: accent and primary. The slices go in the
            // accent group so they still read against the track.
            .widgetAccentable()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Sortd.track)
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func width(for slice: WidgetSummary.Slice, in full: CGFloat, scale: Double) -> CGFloat {
        guard scale > 0 else { return 0 }
        let share = (slice.total as NSDecimalNumber).doubleValue / scale
        return max(2, full * min(1, share))
    }
}

/// A row that never wraps: the amount keeps its full width and the name
/// gives way. The other way round turns "A$58.30" into "A$58." / "30".
private struct MoneyRow: View {
    var title: String
    var detail: String?
    var amount: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2)
                    .frame(width: 14)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Sortd.ink)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            Text(amount)
                .font(.footnote.monospacedDigit())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown instead of a confident $0 when there's nothing to show yet.
private struct NotReady: View {
    var line: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BrandMark(width: 11, height: 3)
            Spacer(minLength: 6)
            Text(line).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 1. Spending

struct SpendingView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SpendingEntry

    private var period: SortdPeriod { entry.configuration.period }

    var body: some View {
        if let s = entry.summary, s.hasAnyPurchases {
            family == .systemMedium ? AnyView(medium(s)) : AnyView(small(s))
        } else {
            NotReady(line: "Nothing logged", detail: "Tap to add your first purchase")
        }
    }

    // Small: today against what a day is worth. One number, one limit.
    private func small(_ s: WidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Heading(text: period.title)
            Spacer(minLength: 6)

            Text(Sortd.money(period.total(s), s.currency))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .foregroundStyle(Sortd.ink)
                .widgetAccentable()
                .contentTransition(.numericText())

            Text(subtitle(s))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)
            SpendBar(slices: s.categories, spent: s.month, limit: s.budget, height: 7)
            if s.budgetUsed > 1 {
                Text("Over budget")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(period.title), \(Sortd.money(period.total(s), s.currency)). \(subtitle(s))")
    }

    // Medium: today on the left, the month on the right, colours between.
    private func medium(_ s: WidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Heading(text: period.title, trailing: trailing(s))
            Spacer(minLength: 8)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(Sortd.money(period.total(s), s.currency))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Sortd.ink)
                    .widgetAccentable()
                    .contentTransition(.numericText())
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(rightTitle(s))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(rightValue(s))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Sortd.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            Text(subtitle(s))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)
            SpendBar(slices: s.categories, spent: s.month, limit: s.budget)

            HStack(spacing: 10) {
                ForEach(s.categories.prefix(3)) { slice in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Sortd.color(forCategory: slice.category))
                            .frame(width: 6, height: 6)
                        Text(slice.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(period.title), \(Sortd.money(period.total(s), s.currency)). \(rightTitle(s)) \(rightValue(s)).")
    }

    /// "of A$50 a day" beats a bare number: a figure needs its limit.
    private func subtitle(_ s: WidgetSummary) -> String {
        if let limit = period.limit(s), limit > 0 {
            let unit = switch period {
            case .today: "a day"
            case .week: "a week"
            case .month: "this month"
            }
            return "of \(Sortd.money(limit, s.currency, cents: false)) \(unit)"
        }
        return "\(Sortd.money(s.month, s.currency, cents: false)) this month"
    }

    /// The other number worth knowing, whichever one isn't on show.
    private func trailing(_ s: WidgetSummary) -> String {
        switch period {
        case .today: "This week \(Sortd.money(s.week, s.currency, cents: false))"
        case .week, .month: "Today \(Sortd.money(s.today, s.currency, cents: false))"
        }
    }

    private func rightTitle(_ s: WidgetSummary) -> String {
        guard let left = s.leftThisMonth else { return "This month" }
        return left < 0 ? "Over budget" : "Left this month"
    }

    private func rightValue(_ s: WidgetSummary) -> String {
        guard let left = s.leftThisMonth else {
            return Sortd.money(s.month, s.currency, cents: false)
        }
        return Sortd.money(abs(left), s.currency, cents: false)
    }
}

struct SortdSpendingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SortdSpending",
                               intent: SpendingConfiguration.self,
                               provider: SpendingProvider()) { entry in
            Chrome(look: entry.configuration.look) {
                SpendingView(entry: entry)
            }
            .privacySensitive(entry.summary?.hidesWhenLocked ?? true)
            .widgetURL(SortdLink.home)
        }
        .configurationDisplayName("Spending")
        .description("Today, this week or this month — against what you have to spend, in your category colours.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 2. Quick Add

struct QuickAddView: View {
    @Environment(\.widgetFamily) private var family
    var entry: LookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Heading(text: "Log it now",
                    trailing: entry.summary.map { Sortd.money($0.today, $0.currency, cents: false) })

            if family == .systemSmall {
                // One big target beats three small ones in a small widget.
                Link(destination: SortdLink.add) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                        Text("Add").font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(Sortd.onInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        // In accented rendering a filled button and its label
                        // would both turn primary and the label would vanish.
                        // The fill takes the accent; the label stays primary.
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Sortd.ink)
                            .widgetAccentable()
                    }
                }
                .accessibilityLabel("Add a purchase")
                HStack(spacing: 6) {
                    pill("doc.text.viewfinder", "Scan", SortdLink.scan, "Scan a receipt")
                    pill("tray.and.arrow.down", "Import", SortdLink.importing, "Import a statement")
                }
            } else {
                HStack(spacing: 8) {
                    big("plus", "Add", SortdLink.add, filled: true)
                    big("doc.text.viewfinder", "Scan", SortdLink.scan, filled: false)
                    big("square.and.arrow.down", "Import", SortdLink.importing, filled: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Icon plus word. An icon on its own leaves people guessing, and a
    /// widget is the wrong place to make someone guess.
    private func pill(_ symbol: String, _ title: String, _ url: URL, _ label: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Sortd.ink)
            .widgetAccentable()
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Sortd.track, in: Capsule())
        }
        .accessibilityLabel(label)
    }

    private func big(_ symbol: String, _ title: String, _ url: URL, filled: Bool) -> some View {
        Link(destination: url) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(title).font(.caption2.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(filled ? Sortd.onInk : Sortd.ink)
            .widgetAccentable(!filled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(filled ? Sortd.ink : Sortd.track)
                    .widgetAccentable(filled)
            }
        }
    }
}

struct SortdQuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SortdQuickAdd",
                               intent: LookConfiguration.self,
                               provider: LookProvider()) { entry in
            Chrome(look: entry.configuration.look) {
                QuickAddView(entry: entry)
            }
            .privacySensitive(entry.summary?.hidesWhenLocked ?? true)
        }
        .configurationDisplayName("Quick Add")
        .description("Log a purchase, scan a receipt or import a statement in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 3. Bills

struct BillsView: View {
    @Environment(\.widgetFamily) private var family
    var entry: LookEntry

    var body: some View {
        if let s = entry.summary, !s.bills.isEmpty {
            content(s)
        } else {
            NotReady(line: "No bills found", detail: "Sortd spots repeat charges by itself")
        }
    }

    private func content(_ s: WidgetSummary) -> some View {
        let limit = family == .systemSmall ? 2 : 4
        let soon = Array(s.bills.prefix(limit))
        let total = soon.reduce(Decimal(0)) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 7) {
            Heading(text: "Coming up",
                    trailing: family == .systemSmall ? nil : Sortd.money(total, s.currency, cents: false))
            ForEach(soon) { bill in
                MoneyRow(title: bill.name,
                         detail: Sortd.countdown(to: bill.due),
                         amount: Sortd.money(bill.amount, bill.currency),
                         symbol: nil)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SortdBillsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SortdBills",
                               intent: LookConfiguration.self,
                               provider: LookProvider()) { entry in
            Chrome(look: entry.configuration.look) {
                BillsView(entry: entry)
            }
            .privacySensitive(entry.summary?.hidesWhenLocked ?? true)
            .widgetURL(SortdLink.bills)
        }
        .configurationDisplayName("Bills")
        .description("Subscriptions and bills about to charge, so none of them surprise you.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Privacy

/// Every shop name and amount goes through one of these two, so the rule
/// lives in one place.
///
/// Shop names: always hidden while the iPhone is locked, whatever Settings ›
/// "Show Amounts When Locked" says. Amounts: hidden unless that setting is on.
private extension View {
    func shopNameIsPrivate() -> some View { privacySensitive() }

    func amountIsPrivate(_ summary: WidgetSummary?) -> some View {
        privacySensitive(summary?.hidesWhenLocked ?? true)
    }
}

/// Which parts VoiceOver must not read right now. The visible text is
/// redacted while the phone is locked; speaking the same words aloud would
/// undo that.
private struct Hiding {
    var shop: Bool
    var amounts: Bool

    init(_ reasons: RedactionReasons, _ summary: WidgetSummary?) {
        let locked = reasons.contains(.privacy)
        shop = locked
        amounts = locked && (summary?.hidesWhenLocked ?? true)
    }
}

/// A shop name on one line, cut with "…" rather than wrapped. The only place
/// a shop name is drawn, and it is always private.
private struct ShopName: View {
    var name: String
    var font: Font = .footnote

    var body: some View {
        Text(name)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(Sortd.ink)
            .shopNameIsPrivate()
    }
}

/// The category's symbol on a tinted rounded square, as in the app's
/// Activity list.
private struct CategoryTile: View {
    var category: String
    var side: CGFloat = 28
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: Sortd.symbol(forCategory: category))
            .font(.system(size: side * 0.42, weight: .semibold))
            .foregroundStyle(Sortd.color(forCategory: category))
            .widgetAccentable()
            .frame(width: side, height: side)
            .background(Sortd.color(forCategory: category).opacity(scheme == .dark ? 0.22 : 0.14),
                        in: .rect(cornerRadius: side * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - 4. Budget ring

struct BudgetRingView: View {
    var entry: LookEntry
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        if let s = entry.summary {
            if let budget = s.budget, budget > 0 {
                ring(s, budget: budget)
            } else {
                noBudget(s)
            }
        } else {
            NotReady(line: "Nothing logged", detail: "Open Sortd to get started")
        }
    }

    /// Share of the budget still there, 0 to 1. An empty ring and an over
    /// budget one would look the same, so over budget fills the ring in red.
    static func share(left: Decimal, budget: Decimal) -> Double {
        guard budget > 0 else { return 0 }
        let value = (left as NSDecimalNumber).doubleValue / (budget as NSDecimalNumber).doubleValue
        return max(0, min(1, value))
    }

    private func ring(_ s: WidgetSummary, budget: Decimal) -> some View {
        let left = s.leftThisMonth ?? (budget - s.month)
        let over = left < 0
        let hiding = Hiding(redaction, s)
        return VStack(alignment: .leading, spacing: 6) {
            Heading(text: over ? "Over budget" : "Left this month")
                .overBudgetIsPrivate(over, s)

            ZStack {
                Circle().stroke(Sortd.track, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: over ? 1 : Self.share(left: left, budget: budget))
                    .stroke(over ? Sortd.over : Sortd.brandGreen,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                VStack(spacing: 0) {
                    Text(Sortd.money(abs(left), s.currency, cents: false))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(Sortd.ink)
                        .contentTransition(.numericText())
                    // Over budget, "A$40 of A$1,500" read as $40 left (feel check,
                    // 2 Oct): say "over" so the number can only be read one way.
                    Text("\(over ? "over" : "of") \(Sortd.money(budget, s.currency, cents: false))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 14)
            }
            .amountIsPrivate(s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(s, budget: budget, left: left, hidden: hiding.amounts))
    }

    private func noBudget(_ s: WidgetSummary) -> some View {
        let hiding = Hiding(redaction, s)
        return VStack(alignment: .leading, spacing: 0) {
            Heading(text: "This month")
            Spacer(minLength: 6)
            Text(Sortd.money(s.month, s.currency))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .foregroundStyle(Sortd.ink)
                .widgetAccentable()
                .amountIsPrivate(s)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Image(systemName: "target").font(.caption.weight(.semibold))
                Text("Set a budget").font(.footnote.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(Sortd.ink)
            .widgetAccentable()
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(Sortd.track, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hiding.amounts
            ? "This month. Hidden while your iPhone is locked. No budget set. Tap to set a budget."
            : "This month, \(Sortd.spoken(s.month, s.currency)) spent. No budget set. Tap to set a budget.")
    }

    private func label(_ s: WidgetSummary, budget: Decimal, left: Decimal, hidden: Bool) -> String {
        if hidden { return "Left this month. Hidden while your iPhone is locked." }
        let of = Sortd.spoken(budget, s.currency, cents: false)
        if left < 0 {
            return "Over budget. \(Sortd.spoken(-left, s.currency, cents: false)) over a budget of \(of)."
        }
        let percent = Int((Self.share(left: left, budget: budget) * 100).rounded())
        return "Left this month, \(Sortd.spoken(left, s.currency, cents: false)) of \(of). \(percent) percent of your budget is left."
    }
}

private extension View {
    /// "Over budget" is itself a fact about money, so it is hidden with the
    /// amounts when the month is over.
    @ViewBuilder func overBudgetIsPrivate(_ over: Bool, _ s: WidgetSummary) -> some View {
        if over { amountIsPrivate(s) } else { self }
    }
}

struct SortdBudgetRingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SortdBudgetRing",
                               intent: LookConfiguration.self,
                               provider: LookProvider()) { entry in
            Chrome(look: entry.configuration.look) {
                BudgetRingView(entry: entry)
            }
            // No budget yet: the tap goes to where one is set.
            .widgetURL(entry.summary?.budget ?? 0 > 0 ? SortdLink.home : SortdLink.budget)
        }
        .configurationDisplayName("Budget Ring")
        .description("How much of this month's budget is left, as a ring.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 5. Today and the last purchase

struct TodayView: View {
    var entry: LookEntry
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        if let s = entry.summary, s.hasAnyPurchases {
            content(s)
        } else {
            NotReady(line: "Nothing yet", detail: "Pay with Apple Pay and it shows up here.")
        }
    }

    private func content(_ s: WidgetSummary) -> some View {
        let last = s.recent.first
        let hiding = Hiding(redaction, s)
        return VStack(alignment: .leading, spacing: 0) {
            Heading(text: "Today")
            Spacer(minLength: 6)

            Text(Sortd.money(s.today, s.currency))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .foregroundStyle(Sortd.ink)
                .widgetAccentable()
                .contentTransition(.numericText())
                .amountIsPrivate(s)

            Spacer(minLength: 8)

            if let last {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: Sortd.symbol(forCategory: last.category))
                            .font(.caption)
                            .foregroundStyle(Sortd.color(forCategory: last.category))
                            .widgetAccentable()
                            .frame(width: 16)
                        ShopName(name: last.merchant)
                    }
                    HStack(spacing: 0) {
                        Text(Sortd.money(last.amount, last.currency))
                            .amountIsPrivate(s)
                        Text(" · \(Sortd.when(last.date, now: entry.date))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(s, last: last, hiding: hiding))
    }

    private func label(_ s: WidgetSummary, last: WidgetSummary.Item?, hiding: Hiding) -> String {
        var parts: [String] = []
        if hiding.amounts {
            parts.append("Today. Hidden while your iPhone is locked.")
        } else {
            var line = "Today, \(Sortd.spoken(s.today, s.currency))"
            if s.todayCount > 0 { line += ", \(s.todayCount) \(s.todayCount == 1 ? "purchase" : "purchases")" }
            parts.append(line + ".")
        }
        if let last {
            let shop = hiding.shop ? "A purchase" : last.merchant
            let amount = hiding.amounts ? "" : ", \(Sortd.spoken(last.amount, last.currency))"
            parts.append("Last: \(shop)\(amount), \(Sortd.when(last.date, now: entry.date)).")
        }
        return parts.joined(separator: " ")
    }
}

struct SortdTodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SortdToday",
                               intent: LookConfiguration.self,
                               provider: LookProvider()) { entry in
            Chrome(look: entry.configuration.look) {
                TodayView(entry: entry)
            }
            .widgetURL(SortdLink.activity)
        }
        .configurationDisplayName("Today")
        .description("What you've spent today, and the last thing you paid for.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 6. Recent

struct RecentView: View {
    var entry: LookEntry
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        if let s = entry.summary, !s.recent.isEmpty {
            content(s)
        } else {
            NotReady(line: "Nothing yet", detail: "Pay with Apple Pay and it shows up here.")
        }
    }

    private func content(_ s: WidgetSummary) -> some View {
        let hiding = Hiding(redaction, s)
        return VStack(alignment: .leading, spacing: 6) {
            Heading(text: "Recent")
            ForEach(s.recent.prefix(3)) { item in
                // A Link, so each row opens its own purchase.
                Link(destination: SortdLink.purchase(item.id)) {
                    HStack(spacing: 10) {
                        CategoryTile(category: item.category)
                        ShopName(name: item.merchant, font: .subheadline)
                        Spacer(minLength: 8)
                        Text(Sortd.money(item.amount, item.currency))
                            .font(.subheadline.monospacedDigit())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(Sortd.ink)
                            .amountIsPrivate(s)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(item, hiding: hiding))
                .accessibilityHint("Opens this purchase")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func label(_ item: WidgetSummary.Item, hiding: Hiding) -> String {
        let shop = hiding.shop ? "A purchase" : item.merchant
        guard !hiding.amounts else { return shop }
        return "\(shop), \(Sortd.spoken(item.amount, item.currency))"
    }
}

struct SortdRecentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SortdRecent",
                               intent: LookConfiguration.self,
                               provider: LookProvider()) { entry in
            Chrome(look: entry.configuration.look) {
                RecentView(entry: entry)
            }
            .widgetURL(SortdLink.activity)
        }
        .configurationDisplayName("Recent")
        .description("Your last three purchases. Tap one to open it.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Previews

extension LookEntry {
    /// Sample data with a chosen look, for previews.
    static func sample(_ look: SortdLook, _ edit: (inout WidgetSummary) -> Void = { _ in }) -> LookEntry {
        let configuration = LookConfiguration()
        configuration.look = look
        var summary = SortdEntry.sample.summary!
        edit(&summary)
        return LookEntry(date: .now, summary: summary, configuration: configuration)
    }
}

#Preview("Budget ring", as: .systemSmall) {
    SortdBudgetRingWidget()
} timeline: {
    LookEntry.sample(.light)
    LookEntry.sample(.dark)
    LookEntry.sample(.light) { $0.leftThisMonth = -40 }
    LookEntry.sample(.dark) { $0.leftThisMonth = -40 }
    LookEntry.sample(.light) { $0.budget = nil; $0.leftThisMonth = nil }
}

#Preview("Today", as: .systemSmall) {
    SortdTodayWidget()
} timeline: {
    LookEntry.sample(.light)
    LookEntry.sample(.dark)
    LookEntry.sample(.light) { $0.today = 0; $0.todayCount = 0 }
    LookEntry.sample(.light) { $0.hasAnyPurchases = false; $0.recent = [] }
}

#Preview("Recent", as: .systemMedium) {
    SortdRecentWidget()
} timeline: {
    LookEntry.sample(.light)
    LookEntry.sample(.dark)
    LookEntry.sample(.light) { $0.recent = Array($0.recent.prefix(2)) }
    LookEntry.sample(.light) { $0.recent = [] }
}

// MARK: - Lock Screen

struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SortdEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    /// A gauge, not a number in a ring: it reads at a glance and survives
    /// the Lock Screen's desaturated rendering.
    @ViewBuilder private var circular: some View {
        let used = entry.summary?.budgetUsed ?? 0
        Gauge(value: min(1, used)) {
            Image(systemName: "dollarsign")
        } currentValueLabel: {
            Text(entry.summary.map { Sortd.money($0.today, $0.currency, cents: false) } ?? "—")
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(used > 0 ? "Budget used \(Int(used * 100)) percent" : "Today's spending")
    }

    @ViewBuilder private var inline: some View {
        if let s = entry.summary {
            if let left = s.leftThisMonth, left > 0 {
                Text("\(Sortd.money(s.today, s.currency, cents: false)) today · \(Sortd.money(left, s.currency, cents: false)) left")
            } else {
                Text("Today \(Sortd.money(s.today, s.currency, cents: false))")
            }
        } else {
            Text("Sortd")
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let s = entry.summary, s.hasAnyPurchases {
            VStack(alignment: .leading, spacing: 1) {
                Text("Today").font(.caption2).widgetAccentable()
                Text(Sortd.money(s.today, s.currency))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail(s)).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sortd").font(.headline)
                Text("Open to get started").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(_ s: WidgetSummary) -> String {
        if let allowance = s.dayAllowance, allowance > 0 {
            return "of \(Sortd.money(allowance, s.currency, cents: false)) a day"
        }
        if let left = s.leftThisMonth {
            return left > 0
                ? "\(Sortd.money(left, s.currency, cents: false)) left this month"
                : "\(Sortd.money(-left, s.currency, cents: false)) over budget"
        }
        return "\(Sortd.money(s.month, s.currency, cents: false)) this month"
    }
}

struct SortdLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SortdLockScreen", provider: SortdProvider()) { entry in
            LockScreenView(entry: entry)
                .privacySensitive(entry.summary?.hidesWhenLocked ?? true)
                .containerBackground(.clear, for: .widget)
                .widgetURL(SortdLink.home)
        }
        .configurationDisplayName("Sortd")
        .description("Today's spending on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Bundle

@main
struct SortdWidgetBundle: WidgetBundle {
    var body: some Widget {
        SortdSpendingWidget()
        SortdBudgetRingWidget()
        SortdTodayWidget()
        SortdRecentWidget()
        SortdQuickAddWidget()
        SortdBillsWidget()
        SortdLockScreenWidget()
    }
}
