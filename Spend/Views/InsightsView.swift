import SwiftUI
import SwiftData

/// Where the money goes: the range chart, a category breakdown with bars,
/// and the top merchants / biggest purchases / food cards.
struct InsightsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var selectedCategory: SpendCategory?
    @State private var limits: [SpendCategory: Double] = [:]

    private var thisMonth: [Transaction] {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        return transactions.filter { $0.date >= start }
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    EmptyState("No insights yet", symbol: "chart.bar.xaxis",
                               message: "After a few purchases, you'll see where your money goes.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            PageTitle(title: "Insights")
                            SpendChart(transactions: transactions)
                            breakdown
                            InsightCarousel(transactions: thisMonth)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                    .background(Color.page)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(transactions.isEmpty ? .visible : .hidden, for: .navigationBar)
            .navigationDestination(item: $selectedCategory) { category in
                CategoryDetailView(category: category)
            }
        }
        .onCategoryLimitsChange {
            let now = CategoryBudgets.all()
            if now != limits { limits = now }
        }
        // Tips: the rules read the purchase figures.
        .onChange(of: transactions.count, initial: true) { TipState.update(from: transactions) }
    }

    // MARK: Category breakdown

    private var categoryTotals: [(category: SpendCategory, total: Decimal, count: Int)] {
        Dictionary(grouping: thisMonth, by: \.category)
            .map { ($0.key, $0.value.audTotal, $0.value.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    private var breakdown: some View {
        let rows = categoryTotals
        let max = rows.first?.total.double ?? 1
        let total = thisMonth.audTotal.double

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Categories This Month")
            VStack(spacing: 0) {
                ForEach(rows, id: \.category) { row in
                    let progress = limits[row.category].map { CategoryBudgets.progress(spent: row.total.double, limit: $0) }
                    Button { selectedCategory = row.category } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: row.category, size: 36)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.category.name)
                                        .font(.body)
                                    Spacer()
                                    if let progress {
                                        Text("\(Money.format(row.total, Money.home, cents: false)) of \(Money.format(Decimal(progress.limit), Money.home, cents: false))")
                                            .font(.body)
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                            .foregroundStyle(progress.status == .over ? Color.down : Color.ink)
                                    } else {
                                        Text(Money.format(row.total, Money.home))
                                            .font(.body)
                                            .monospacedDigit()
                                    }
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.systemGray5))
                                        if let progress {
                                            Capsule().fill(progress.status.color(row.category))
                                                .frame(width: Swift.max(6, geo.size.width * Swift.min(1, progress.fraction)))
                                        } else {
                                            Capsule().fill(row.category.color)
                                                .frame(width: Swift.max(6, geo.size.width * row.total.double / max))
                                        }
                                    }
                                }
                                .frame(height: 6)
                                Text("\(limitNote(progress) ?? "\(Int((row.total.double / Swift.max(total, 1) * 100).rounded()))%") · \(row.count) \(row.count == 1 ? "purchase" : "purchases")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.category.name), \(Money.spoken(row.total, Money.home))\(progress.map { ", " + (limitNote($0) ?? "") } ?? ""), \(row.count) \(row.count == 1 ? "purchase" : "purchases")")
                    .accessibilityHint("Shows these purchases")
                }
            }
            .surface()
        }
    }

    private func limitNote(_ progress: CategoryBudgets.Progress?) -> String? {
        guard let progress else { return nil }
        if progress.status == .over {
            return "\(Money.format(Decimal(-progress.left), Money.home, cents: false)) over limit"
        }
        return "\(Money.format(Decimal(progress.left), Money.home, cents: false)) left"
    }
}

/// Every purchase in one category, newest first, with this month's total.
struct CategoryDetailView: View {
    let category: SpendCategory
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]
    @State private var limit: Double?
    @State private var editingLimit = false

    /// Spent against the limit, with "over" or "left" spelled out — near and
    /// over used to be amber vs red and nothing else.
    @ViewBuilder
    private func limitCell(_ limit: Double, spent: Decimal) -> some View {
        let p = CategoryBudgets.progress(spent: spent.double, limit: limit)
        let spentText = Money.format(spent, Money.home, cents: false)
        let limitText = Money.format(Decimal(limit), Money.home, cents: false)
        let over = p.status == .over
        let note = over
            ? Money.format(Decimal(-p.left), Money.home, cents: false) + " over"
            : Money.format(Decimal(p.left), Money.home, cents: false) + " left"
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(spentText) of \(limitText)")
                .monospacedDigit()
                .foregroundStyle(p.status == .ok ? Color.secondary : p.status.color(category))
            if p.status != .ok {
                Text(note).font(.caption).foregroundStyle(p.status.color(category))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    var body: some View {
        let items = all.filter { $0.category == category }
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let month = items.filter { $0.date >= start }

        List {
            Section {
                VStack(spacing: 8) {
                    CategoryIcon(category: category, size: 56)
                    Text(Money.format(month.audTotal, Money.home))
                        .font(.money)
                    BrandBar(width: 14, height: 3)
                    Text("This month · \(month.count) \(month.count == 1 ? "purchase" : "purchases")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                Button { editingLimit = true } label: {
                    HStack {
                        Text("Monthly Limit")
                        Spacer()
                        if let limit {
                            limitCell(limit, spent: month.audTotal)
                        } else {
                            Text("None").foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(limit == nil ? "Set a monthly limit" : "Change or remove the monthly limit")
            }
            Section(bold: "All Purchases") {
                ForEach(items) { t in
                    NavigationLink {
                        TransactionDetailView(transaction: t)
                    } label: {
                        TransactionRow(transaction: t, showTime: false, showCategory: false)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingLimit) { CategoryLimitSheet(category: category) }
        .onCategoryLimitsChange {
            let now = CategoryBudgets.limit(for: category)
            if now != limit { limit = now }
        }
    }
}
