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
                            PageTitle(title: "Insights", subtitle: "Where your money goes, and how this month compares.")
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

        // One dry line, and only when a single category really ran away
        // with the month. Most months it says nothing.
        let quip = rows.first.flatMap { row -> String? in
            guard total > 0 else { return nil }
            return SortdVoice.topCategory(row.category.name, share: row.total.double / total)
        }

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Categories this month")
            if let quip {
                Text(quip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    .accessibilityLabel("\(row.category.name), \(Money.format(row.total, Money.home))\(progress.map { ", " + (limitNote($0) ?? "") } ?? ""), \(row.count) purchases")
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

    var body: some View {
        let items = all.filter { $0.category == category }
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let month = items.filter { $0.date >= start }

        List {
            Section {
                VStack(spacing: 8) {
                    CategoryIcon(category: category, size: 56)
                    Text(Money.format(month.audTotal, Money.home))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    BrandBar(width: 14, height: 3)
                    Text("this month · \(month.count) \(month.count == 1 ? "purchase" : "purchases")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                Button { editingLimit = true } label: {
                    HStack {
                        Text("Monthly limit")
                        Spacer()
                        if let limit {
                            let p = CategoryBudgets.progress(spent: month.audTotal.double, limit: limit)
                            Text("\(Money.format(month.audTotal, Money.home, cents: false)) of \(Money.format(Decimal(limit), Money.home, cents: false))")
                                .monospacedDigit()
                                .foregroundStyle(p.status == .ok ? Color.secondary : p.status.color(category))
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
        .sheet(isPresented: $editingLimit) { if ProStore.shared.isPro { CategoryLimitSheet(category: category) } else { PaywallView(feature: .budgets) } }
        .onCategoryLimitsChange {
            let now = CategoryBudgets.limit(for: category)
            if now != limit { limit = now }
        }
    }
}
