import SwiftUI
import SwiftData

/// The search tab. Before you type it shows where you spend most (merchants
/// and categories this month) so there's always something to tap; once you
/// type it searches every purchase by merchant, category or note.
struct SearchView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty { landing } else { results }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Merchant, category or note")
            .navigationDestination(for: Transaction.self) { TransactionDetailView(transaction: $0) }
        }
    }

    // MARK: Before typing

    @ViewBuilder
    private var landing: some View {
        if transactions.isEmpty {
            ContentUnavailableView("Nothing to search yet",
                                   systemImage: "magnifyingglass",
                                   description: Text("Purchases you log show up here."))
                .listRowBackground(Color.clear)
        } else {
            Section("Top merchants this month") {
                ForEach(topMerchants, id: \.name) { m in
                    Button { query = m.name } label: {
                        HStack {
                            Text(m.name).foregroundStyle(Color.ink)
                            Spacer()
                            Text(Money.format(m.total, Money.home))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("\(m.name), \(Money.format(m.total, Money.home)) this month")
                }
            }
            Section("Categories") {
                ForEach(usedCategories) { c in
                    Button { query = c.name } label: {
                        Label {
                            Text(c.name).foregroundStyle(Color.ink)
                        } icon: {
                            Image(systemName: c.symbol).foregroundStyle(c.color)
                        }
                    }
                }
            }
        }
    }

    // MARK: After typing

    @ViewBuilder
    private var results: some View {
        let found = matches
        if found.isEmpty {
            ContentUnavailableView.search(text: trimmed)
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(found) { t in
                    NavigationLink(value: t) { TransactionRow(transaction: t) }
                        .listRowBackground(Color.card)
                }
            } header: {
                HStack {
                    Text("\(found.count) result\(found.count == 1 ? "" : "s")")
                    Spacer()
                    Text(Money.format(found.audTotal, Money.home)).monospacedDigit()
                }
                .textCase(nil)
            }
        }
    }

    // MARK: Data

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var matches: [Transaction] {
        let q = trimmed.lowercased()
        return transactions.filter {
            $0.merchant.lowercased().contains(q)
            || $0.category.name.lowercased().contains(q)
            || $0.note.lowercased().contains(q)
        }
    }

    private var thisMonth: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    private var topMerchants: [(name: String, total: Decimal)] {
        Dictionary(grouping: thisMonth, by: \.merchant)
            .map { (name: $0.key, total: $0.value.audTotal) }
            .sorted { $0.total > $1.total }
            .prefix(5)
            .map { $0 }
    }

    private var usedCategories: [SpendCategory] {
        let used = Set(transactions.map(\.category))
        return SpendCategory.allCases.filter(used.contains)
    }
}
