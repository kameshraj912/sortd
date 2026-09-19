#if DEBUG
import SwiftUI
import SwiftData

/// Proposed Home in the setup screens' style: left-aligned bold headings
/// with the logo bar, one big total, flat white cards, bold black section
/// titles, colour only for categories and the logo accents.
/// Debug-only preview (SPEND_SCREEN=homev2) — the real Home is unchanged.
struct HomeMockup: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @AppStorage("monthlyBudget") private var budget: Double = 0
    @State private var focused: String? = "all"

    private var cal: Calendar { .current }
    private var monthItems: [Transaction] {
        guard let i = cal.dateInterval(of: .month, for: .now) else { return [] }
        return transactions.filter { i.contains($0.date) }
    }
    private var focusedCard: Card? { focused == nil || focused == "all" ? nil : Card(rawValue: focused!) }
    private var cardItems: [Transaction] { focusedCard.map { c in monthItems.filter { $0.card == c } } ?? monthItems }
    private var byCategory: [(SpendCategory, Decimal, Int)] {
        Dictionary(grouping: cardItems, by: \.category).map { ($0.key, $0.value.audTotal, $0.value.count) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                budgetCard(for: monthItems)
                cards
                upcoming
                categories
                recent
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.page)
    }

    // MARK: Header — like a setup page title

    private var header: some View {
        let spent = monthItems.audTotal.double
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now.formatted(.dateTime.month(.wide)))
                        .font(.title2.weight(.bold))
                    BrandBar(width: 14, height: 3)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onBrand)
                    .frame(width: 40, height: 40)
                    .background(Color.brand, in: .circle)
            }
            .padding(.top, 8)

            Text(Money.format(Decimal(spent), Money.home, cents: false))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.top, 6)
            Text(summaryLine(spent: spent))
                .font(.subheadline.weight(budget > 0 && spent > budget ? .semibold : .regular))
                .foregroundStyle(budget > 0 && spent > budget ? Color.down : .secondary)
        }
    }

    private func summaryLine(spent: Double) -> String {
        guard budget > 0 else { return "spent this month" }
        let left = budget - spent
        let daysLeft = max(1, (cal.range(of: .day, in: .month, for: .now)?.count ?? 30) - cal.component(.day, from: .now) + 1)
        if left < 0 { return "\(Money.format(Decimal(-left), Money.home, cents: false)) over your \(Money.format(Decimal(budget), Money.home, cents: false)) budget" }
        return "\(Money.format(Decimal(left), Money.home, cents: false)) left of \(Money.format(Decimal(budget), Money.home, cents: false)) · \(Money.format(Decimal(left / Double(daysLeft)), Money.home, cents: false)) a day"
    }

    private func budgetCard(for items: [Transaction]) -> some View {
        let spent = items.audTotal.double
        let segments = byCategory.map { SegmentedBar.Segment(id: $0.0.rawValue, value: $0.1.double, color: $0.0.color) }
        return VStack(alignment: .leading, spacing: 10) {
            SegmentedBar(segments: segments, total: max(budget, spent), height: 10)
            HStack(spacing: 12) {
                ForEach(byCategory.prefix(3), id: \.0) { c in
                    HStack(spacing: 5) {
                        Circle().fill(c.0.color).frame(width: 7, height: 7)
                        Text(c.0.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
        .surface(radius: 18)
    }

    // MARK: Sections

    private func section(_ title: String, _ trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
    }

    private var cards: some View {
        let ranked = Card.mine.map { c in (c, monthItems.filter { $0.card == c }) }.sorted { $0.1.audTotal > $1.1.audTotal }
        return VStack(alignment: .leading, spacing: 12) {
            section("Your cards")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    WalletCard(card: nil, transactions: monthItems).frame(width: 216).id("all")
                    ForEach(ranked, id: \.0) { c, items in
                        WalletCard(card: c, transactions: items).frame(width: 216).id(c.rawValue)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focused, anchor: .leading)
            .scrollClipDisabled()
        }
    }

    private var upcoming: some View {
        let soon = Array(transactions.recurring().filter { $0.status == .active && $0.nextDate <= cal.date(byAdding: .day, value: 14, to: .now)! }.prefix(3))
        return VStack(alignment: .leading, spacing: 12) {
            if !soon.isEmpty {
                section("Coming up", "See all")
                VStack(spacing: 0) {
                    ForEach(soon) { r in
                        HStack(spacing: 12) {
                            CategoryIcon(category: r.category, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.merchant).lineLimit(1)
                                Text(RecurringView.when(r.nextDate)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(r.amount, r.currency)).monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .surface(radius: 18)
            }
        }
    }

    private var categories: some View {
        let rows = Array(byCategory.prefix(4))
        let top = rows.first?.1.double ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            section("Where it went", "See all")
            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 12) {
                        CategoryIcon(category: row.0, size: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.0.name)
                                Spacer()
                                Text(Money.format(row.1, Money.home)).monospacedDigit()
                            }
                            SegmentedBar(segments: [.init(id: "v", value: row.1.double, color: row.0.color)], total: top, height: 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if row.0 != rows.last?.0 { Divider().padding(.leading, 64) }
                }
            }
            .surface(radius: 18)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Recent", "See all")
            VStack(spacing: 0) {
                ForEach(Array(cardItems.prefix(6))) { t in
                    TransactionRow(transaction: t, showTime: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    if t.id != cardItems.prefix(6).last?.id { Divider().padding(.leading, 64) }
                }
            }
            .surface(radius: 18)
        }
    }
}
#endif
