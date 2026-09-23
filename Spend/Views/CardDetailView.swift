import SwiftUI
import SwiftData
import Charts

/// Apple Card-style screen for one card: the card itself, a grid of tiles,
/// then its recent purchases.
struct CardDetailView: View {
    let card: Card
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]
    /// The month-bar chart grows with Dynamic Type so its month letters keep room.
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 64

    private var cal: Calendar { .current }

    private var transactions: [Transaction] { all.filter { $0.card == card } }

    private var thisMonth: [Transaction] {
        let start = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        return transactions.filter { $0.date >= start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(title: card.name)
                WalletCard(card: card, transactions: thisMonth)
                    .padding(.bottom, 8)

                tiles

                recent
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.page)
        .brandedTitle(card.name)
    }

    // MARK: Tiles

    private var tiles: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Tile(title: "Spent This Month") {
                    Text(Money.format(thisMonth.audTotal, Money.home))
                        .font(.moneySmall)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(thisMonth.count == 1 ? "1 purchase" : "\(thisMonth.count) purchases")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Tile(title: "Top Category") {
                    if let top = topCategory {
                        HStack(spacing: 8) {
                            CategoryIcon(category: top.category, size: 28)
                            Text(top.category.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Text(Money.format(top.total, Money.home))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("—").font(.title2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
            }
            GridRow {
                Tile(title: "6-Month Activity") {
                    activityBars
                }
                Tile(title: "Biggest Purchase") {
                    if let big = thisMonth.max(by: { $0.audValue < $1.audValue }) {
                        Text(Money.format(big.audValue, Money.home))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                        Text(big.merchant)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("—").font(.title2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var topCategory: (category: SpendCategory, total: Decimal)? {
        Dictionary(grouping: thisMonth, by: \.category)
            .mapValues(\.audTotal)
            .max { $0.value < $1.value }
            .map { ($0.key, $0.value) }
    }

    private struct MonthTotal: Identifiable {
        let month: Date
        let total: Double
        var id: Date { month }
    }

    private var months: [MonthTotal] {
        let start = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        return (0..<6).reversed().compactMap { back in
            guard let m = cal.date(byAdding: .month, value: -back, to: start),
                  let end = cal.date(byAdding: .month, value: 1, to: m) else { return nil }
            let total = transactions.filter { $0.date >= m && $0.date < end }.audTotal.double
            return MonthTotal(month: m, total: total)
        }
    }

    private var activityBars: some View {
        Chart(months) { m in
            BarMark(x: .value("Month", m.month, unit: .month), y: .value("Spent", m.total), width: .ratio(0.5))
                .foregroundStyle(cal.isDate(m.month, equalTo: .now, toGranularity: .month)
                                 ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color(.systemGray4)))
                .cornerRadius(3)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d.formatted(.dateTime.month(.narrow)))
                    }
                }
            }
        }
        .frame(height: chartHeight)
        .accessibilityLabel("Spending over the last 6 months")
        .accessibilityValue(months.map { "\($0.month.formatted(.dateTime.month(.wide))) \(Money.format(Decimal($0.total), Money.home, cents: false))" }.joined(separator: ", "))
    }

    // MARK: Recent

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Same shape as Home's SectionHeader, which this used to differ
            // from: .headline instead of .title3, and a "See All" with no
            // minimum height.
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink {
                    TransactionsScreen(fixedCard: card)
                } label: {
                    Text("See All").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .frame(minHeight: 44).contentShape(.rect)
                }
                .accessibilityLabel("See All, Recent")
            }
            .padding(.horizontal, 4)
            .padding(.top, 12)

            if transactions.isEmpty {
                EmptyState("No purchases yet", symbol: "creditcard",
                           message: "Pay with \(card.name) and it shows up here.")
            } else {
                let shown = Array(transactions.prefix(8))
                VStack(spacing: 0) {
                    ForEach(shown) { t in
                        NavigationLink {
                            TransactionDetailView(transaction: t)
                        } label: {
                            TransactionRow(transaction: t, showTime: false)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if t.id != shown.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .surface()
            }
        }
    }
}

/// Rounded tile with a small caption on top, like Apple Card's summary grid.
private struct Tile<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .surface()
        .accessibilityElement(children: .combine)
    }
}
