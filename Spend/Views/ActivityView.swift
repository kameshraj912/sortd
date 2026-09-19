import SwiftUI
import SwiftData

struct ActivityView: View {
    var body: some View {
        NavigationStack {
            TransactionsScreen(fixedCard: nil)
        }
    }
}

/// The purchase list. With `fixedCard` set it shows only that card's purchases
/// (opened by tapping a card on Home).
struct TransactionsScreen: View {
    let fixedCard: Card?
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var search = ""
    @State private var cardFilter: Card?
    @State private var categoryFilter: SpendCategory?
    @State private var showingAdd = false
    @State private var recategorising: Transaction?
    @State private var deleted = 0

    var body: some View {
        Group {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "No Purchases Yet",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text("Purchases you log, or that come in from Apple Pay, show up here.")
                )
            } else {
                // The list always shows (title, search box, chips), with a
                // "nothing matches" message inside it, so a search can be cleared.
                list
            }
        }
        .background(Color.page)
        .brandedTitle(fixedCard?.name ?? "Activity")
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { filterMenu }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                Button("Add Purchase", systemImage: "plus") { showingAdd = true }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showingAdd) { AddTransactionView() }
        .sheet(item: $recategorising) { t in
            CategoryPickerSheet(selected: t.category) { category in
                try? TransactionLogger.recategorise(t, to: category, in: context)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: deleted)
    }

    // MARK: List

    private var list: some View {
        List {
            ListPageTitle(title: fixedCard?.name ?? "Activity")
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Merchant, category or note", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Color.card, in: .capsule)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            // Category chips, like the reference's outlined pills.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: categoryFilter == nil) { categoryFilter = nil }
                    ForEach(usedCategories) { c in
                        chip(c.name, dot: c.color, selected: categoryFilter == c) {
                            categoryFilter = categoryFilter == c ? nil : c
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if filtered.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                        Text(search.isEmpty ? "No purchases fit these filters." : "No results for “\(search)”.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Clear") { search = ""; cardFilter = nil; categoryFilter = nil }
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            }
            ForEach(days, id: \.date) { day in
                Section {
                    ForEach(day.items) { t in
                        ZStack {
                            // Hidden link so the row has no chevron.
                            NavigationLink { TransactionDetailView(transaction: t) } label: { EmptyView() }
                                .opacity(0)
                            TransactionRow(transaction: t)
                        }
                        .listRowBackground(Color.card)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 52 }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                context.delete(t)
                                try? context.save()
                                deleted += 1
                            }
                            Button("Category", systemImage: "tag") { recategorising = t }
                                .tint(Color(.systemGray))
                        }
                    }
                } header: {
                    HStack {
                        Text(dayTitle(day.date))
                        Spacer()
                        Text(Money.format(day.items.audTotal, Money.home))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.page)
    }

    private var usedCategories: [SpendCategory] {
        let used = Set(transactions.filter { fixedCard == nil || $0.card == fixedCard }.map(\.category))
        return SpendCategory.allCases.filter(used.contains)
    }

    private func chip(_ title: String, dot: Color? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .chip(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var filterMenu: some View {
        Menu {
            if fixedCard == nil {
                Picker("Card", selection: $cardFilter) {
                    Text("All Cards").tag(Card?.none)
                    ForEach(Card.mine) { Text($0.name).tag(Card?.some($0)) }
                }
            }
            Picker("Category", selection: $categoryFilter) {
                Text("All Categories").tag(SpendCategory?.none)
                ForEach(SpendCategory.allCases) {
                    Label($0.name, systemImage: $0.symbol).tag(SpendCategory?.some($0))
                }
            }
            if isFiltering {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    cardFilter = nil
                    categoryFilter = nil
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: Data

    private var isFiltering: Bool { cardFilter != nil || categoryFilter != nil }

    private var filtered: [Transaction] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return transactions.filter { t in
            (fixedCard == nil || t.card == fixedCard)
            && (cardFilter == nil || t.card == cardFilter)
            && (categoryFilter == nil || t.category == categoryFilter)
            && (q.isEmpty
                || t.merchant.lowercased().contains(q)
                || t.category.name.lowercased().contains(q)
                || t.note.lowercased().contains(q))
        }
    }

    private var days: [(date: Date, items: [Transaction])] {
        let groups = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    private func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = cal.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear
            ? .dateTime.weekday(.wide).day().month(.wide)
            : .dateTime.day().month(.wide).year())
    }
}

/// Grid of categories. Choosing one also teaches the app for next time.
struct CategoryPickerSheet: View {
    let selected: SpendCategory
    let onPick: (SpendCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(SpendCategory.allCases) { category in
                        Button {
                            picked += 1
                            onPick(category)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                CategoryIcon(category: category, size: 44)
                                Text(category.name)
                                    .font(.caption.weight(.medium))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2, reservesSpace: true)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(category == selected ? Color.brand.opacity(0.25) : Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(category == selected ? Color.primary : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == selected ? .isSelected : [])
                    }
                }
                .padding()
                Text("Other purchases at this merchant will move too, and new ones will use this category.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .background(Color.page)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sensoryFeedback(.selection, trigger: picked)
        }
        .presentationDetents([.medium, .large])
    }
}
