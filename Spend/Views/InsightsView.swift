import SwiftUI
import SwiftData

/// Where the money goes: the range chart, a category breakdown with bars,
/// and the top merchants / biggest purchases / food cards.
struct InsightsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var selectedCategory: SpendCategory?

    private var thisMonth: [Transaction] {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        return transactions.filter { $0.date >= start }
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView("No Insights Yet", systemImage: "chart.bar.xaxis",
                                           description: Text("Once a few purchases come in, you'll see where your money goes."))
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
            SectionHeader(title: "Categories this month")
            VStack(spacing: 0) {
                ForEach(rows, id: \.category) { row in
                    Button { selectedCategory = row.category } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: row.category, size: 36)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.category.name)
                                        .font(.body)
                                    Spacer()
                                    Text(Money.format(row.total, Money.home))
                                        .font(.body)
                                        .monospacedDigit()
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.systemGray5))
                                        Capsule().fill(row.category.color)
                                            .frame(width: Swift.max(6, geo.size.width * row.total.double / max))
                                    }
                                }
                                .frame(height: 6)
                                Text("\(Int((row.total.double / Swift.max(total, 1) * 100).rounded()))% · \(row.count) \(row.count == 1 ? "purchase" : "purchases")")
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
                    .accessibilityLabel("\(row.category.name), \(Money.format(row.total, Money.home)), \(row.count) purchases")
                    .accessibilityHint("Shows these purchases")
                }
            }
            .surface()
        }
    }
}

/// Every purchase in one category, newest first, with this month's total.
struct CategoryDetailView: View {
    let category: SpendCategory
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]

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
    }
}
