import SwiftUI
import SwiftData

/// The search tab. Before you type it shows where you spend most (merchants
/// and categories this month) so there's always something to tap; once you
/// type it searches every purchase by merchant, category or note.
struct SearchView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    /// Set when the search field lives on the TabView instead of here.
    var external: Binding<String>? = nil
    @State private var own = ""
    private var query: String {
        get { external?.wrappedValue ?? own }
        nonmutating set { if let external { external.wrappedValue = newValue } else { own = newValue } }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty { landing } else { results }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .navigationTitle("Search")
            .toolbar { SettingsToolbarButton() }
            .modifier(OwnSearchField(enabled: external == nil, query: $own))
            .navigationDestination(for: Transaction.self) { TransactionDetailView(transaction: $0) }
        }
        // Tips: the rules read the purchase figures; typing is the search tip's "done".
        .onChange(of: transactions.count, initial: true) { TipState.update(from: transactions) }
        .onChange(of: trimmed) { _, text in if !text.isEmpty { TipState.searchUsed() } }
    }

    // MARK: Before typing

    @ViewBuilder
    private var landing: some View {
        if transactions.isEmpty {
            EmptyState("Nothing to search yet", symbol: "magnifyingglass",
                       message: "Purchases you log show up here.")
                .listRowBackground(Color.clear)
        } else {
            // The search field is the system's own, so the tip sits under
            // it as a card rather than pointing at it.
            SortdTipView(tip: SearchTip())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            Section(bold: "Top Shops This Month") {
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
                    .accessibilityLabel("\(m.name), \(Money.spoken(m.total, Money.home)) this month")
                }
            }
            Section(bold: "Categories") {
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
            EmptyState("No results", symbol: "magnifyingglass",
                       message: "Nothing matches \u{201C}\(trimmed)\u{201D}.")
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(found) { t in
                    NavigationLink(value: t) { TransactionRow(transaction: t, showTime: false) }
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
        let q = SearchText.fold(trimmed)
        return transactions.filter { SearchText.matches($0, folded: q) }
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

private struct OwnSearchField: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    func body(content: Content) -> some View {
        if enabled {
            // Always showing: the whole point of this tab is the field.
            content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                               prompt: "Shop, category or note")
        } else {
            content
        }
    }
}

/// Search that forgives how a name is written: "mcdonalds" finds
/// "McDonald's", "cafe" finds "Café", "7 eleven" finds "7-Eleven".
nonisolated enum SearchText {
    /// Lowercase, accents folded, and only letters and digits kept.
    static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: nil)
        return String(folded.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)).lowercased()
    }

    /// True when `folded` (already run through `fold`) is in the shop,
    /// category or note. An empty query matches everything.
    static func matches(_ t: Transaction, folded q: String) -> Bool {
        q.isEmpty
            || fold(t.merchant).contains(q)
            || fold(t.category.name).contains(q)
            || fold(t.note).contains(q)
    }
}
