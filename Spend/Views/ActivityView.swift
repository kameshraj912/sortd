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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var search = ""
    @State private var cardFilter: Card?
    @State private var categoryFilter: SpendCategory?
    @State private var showingAdd = false
    @State private var recategorising: Transaction?
    @State private var deleted = 0
    /// Swiped away but kept for a few seconds so Undo can bring them back.
    /// Each new delete restarts the timer; Undo brings back all of them.
    @State private var pendingDeletes: [Transaction] = []
    /// What the last pull-to-refresh found.
    @State private var refreshNote: RefreshNote?
    @State private var undoTask: Task<Void, Never>?
    /// A category picked in the sheet, waiting for the sheet to close.
    @State private var stagedChange: CategoryChange?
    /// Asks "Change all N … purchases?" when other purchases share the shop.
    @State private var confirmingChange: CategoryChange?

    var body: some View {
        Group {
            if transactions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    PageTitle(title: fixedCard?.name ?? "Activity")
                        .padding(.horizontal, 20)
                    EmptyState("No purchases yet", symbol: "list.bullet.rectangle.portrait",
                               message: "Your purchases will show up here.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // The list always shows (title, search box, chips), with a
                // "nothing matches" message inside it, so a search can be cleared.
                list
            }
        }
        .background(Color.page)
        .brandedTitle(fixedCard?.name ?? "Activity")
        // A card's own list always has search; the main list has it when
        // there's no Search tab (nav option A). Hand-rolling this field lost
        // the Cancel button and scroll-to-reveal, and left the app with two
        // different searches — the Search tab already uses .searchable.
        .modifier(ActivitySearch(enabled: fixedCard != nil || NavOption.current.searchInActivity,
                                 text: $search))
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            if fixedCard == nil, !transactions.isEmpty {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                    .sharedBackgroundVisibility(.hidden)
            }
            if NavLayout.current == .header || NavLayout.current == .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Purchase", systemImage: "plus") { showingAdd = true }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .sheet(isPresented: $showingAdd) { AddTransactionView() }
        .sheet(item: $recategorising, onDismiss: {
            // The question waits until the sheet is gone, or it can't show.
            confirmingChange = stagedChange
            stagedChange = nil
        }) { t in
            CategoryPickerSheet(selected: t.category, footer: CategoryPickerSheet.askFooter) { category in
                pick(category, for: t)
            }
        }
        .confirmationDialog(confirmingChange.map { "Change all \($0.total) \($0.transaction.merchant) purchases?" } ?? "",
                            isPresented: Binding(get: { confirmingChange != nil },
                                                 set: { if !$0 { confirmingChange = nil } }),
                            titleVisibility: .visible,
                            presenting: confirmingChange) { change in
            Button("All \(change.total)") {
                try? TransactionLogger.recategorise(change.transaction, to: change.category, in: context)
            }
            Button("Just This One") {
                try? TransactionLogger.recategorise(change.transaction, to: change.category, in: context,
                                                    applyToOthers: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: { change in
            Text("\"All\" also puts new \(change.transaction.merchant) purchases in \(change.category.name).")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: deleted)
        .overlay(alignment: .bottom) {
            if !pendingDeletes.isEmpty {
                UndoToast(text: undoText) { undoDelete() }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: pendingDeletes.isEmpty)
        // The list used to jump on every keystroke and every chip tap.
        .animation(.snappy, value: search)
        .animation(.snappy, value: categoryFilter)
        .animation(.snappy, value: cardFilter)
        .refreshable {
            // Finish a pending delete first, so a receipt from the sync can't
            // merge into a purchase that is about to go.
            commitDelete()
            // Pull down to fetch new Gmail receipts and exchange rates.
            refreshNote = await RefreshNote.run(in: context)
        }
        .refreshNote($refreshNote, bottomPadding: 16)
        .onDisappear { commitDelete() }
        // Leaving the app ends the Undo window: save the delete now, or the
        // 6-second timer may never fire and the widgets keep the purchase.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { commitDelete() }
        }
    }

    // MARK: Delete with undo

    private func delete(_ t: Transaction) {
        guard !pendingDeletes.contains(where: { $0.persistentModelID == t.persistentModelID }) else { return }
        pendingDeletes.append(t)
        deleted += 1
        // A new delete gives the whole batch a fresh 6 seconds.
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            commitDelete()
        }
    }

    private func undoDelete() {
        undoTask?.cancel()
        pendingDeletes = []
    }

    private func commitDelete() {
        undoTask?.cancel()
        guard !pendingDeletes.isEmpty else { return }
        let gone = pendingDeletes
        pendingDeletes = []
        for t in gone { context.delete(t) }
        try? context.save()
        WidgetBridge.refresh(from: context)
    }

    /// "Deleted Woolworths" or "Deleted 2 purchases".
    private var undoText: String {
        if pendingDeletes.count == 1, let t = pendingDeletes.first { return "Deleted \(t.merchant)" }
        return "Deleted \(pendingDeletes.count) purchases"
    }

    // MARK: Category

    /// No other purchases from the shop: change it and learn, as before.
    /// Otherwise ask first, once the sheet has closed.
    private func pick(_ category: SpendCategory, for t: Transaction) {
        let others = (try? TransactionLogger.samePlace(as: t, in: context)) ?? []
        if others.allSatisfy({ $0.category == category }) {
            try? TransactionLogger.recategorise(t, to: category, in: context)
        } else {
            stagedChange = CategoryChange(transaction: t, category: category, total: others.count + 1)
        }
    }

    // MARK: List

    private var list: some View {
        List {
            ListPageTitle(title: fixedCard?.name ?? "Activity")
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
                        Text(search.isEmpty ? "No purchases match these filters." : "No results for “\(search)”.")
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
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 48 }
                        .swipeActions(edge: .leading) {
                            Button("Category", systemImage: "tag") { recategorising = t }
                                .tint(t.category.color)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(t) }
                                .tint(.red)
                        }
                        .contextMenu {
                            Button("Change Category", systemImage: "tag") { recategorising = t }
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(t) }
                        } preview: {
                            TransactionPreview(transaction: t)
                        }
                    }
                } header: {
                    // At the largest text sizes the day gets its own line, so
                    // "September" isn't broken in the middle.
                    let big = typeSize.isAccessibilitySize
                    let layout = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                     : AnyLayout(HStackLayout())
                    layout {
                        Text(dayTitle(day.date))
                        if !big { Spacer() }
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
        let q = SearchText.fold(search)
        let hidden = Set(pendingDeletes.map(\.persistentModelID))
        return transactions.filter { t in
            !hidden.contains(t.persistentModelID)
            && (fixedCard == nil || t.card == fixedCard)
            && (cardFilter == nil || t.card == cardFilter)
            && (categoryFilter == nil || t.category == categoryFilter)
            && SearchText.matches(t, folded: q)
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

/// A category picked for one purchase, waiting on "All N" or "Just This One".
struct CategoryChange: Identifiable {
    let transaction: Transaction
    let category: SpendCategory
    /// This purchase plus the others from the same shop.
    let total: Int
    var id: PersistentIdentifier { transaction.persistentModelID }
}

/// Grid of categories. Choosing one also teaches the app for next time.
struct CategoryPickerSheet: View {
    /// Where picking moves every purchase from the shop straight away.
    static let moveAllFooter = "Other purchases from this shop move too. New ones will use this category."
    /// Where Raj is asked first (Activity).
    static let askFooter = "You can move other purchases from this shop too. Then new ones will use this category."

    let selected: SpendCategory
    var footer: String = CategoryPickerSheet.moveAllFooter
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
                Text(footer)
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
        .presentationDragIndicator(.visible)
    }
}

/// "Deleted Uber Eats · Undo", in glass above the tab bar.
struct UndoToast: View {
    let text: String
    var symbol = "trash"
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Label(text, systemImage: symbol)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Color.ink)
            Button("Undo", action: undo)
                .fontWeight(.semibold)
                .foregroundStyle(Color.ink)
        }
        .font(.subheadline)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

/// What a long press shows above the menu: the purchase at a glance.
struct TransactionPreview: View {
    let transaction: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CategoryIcon(category: transaction.category, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.merchant).font(.headline)
                    Text(transaction.category.name).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(transaction.needsReview ? "Amount missing" : Money.format(transaction.amount, transaction.currencyCode))
                .font(.money)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 4) {
                Label(transaction.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label(transaction.paidWithLabel, systemImage: "creditcard")
                if !transaction.note.isEmpty { Label(transaction.note, systemImage: "note.text") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(idealWidth: 300, maxWidth: 340, alignment: .leading)
        .background(Color.card)
    }
}


/// `.searchable` only when this list is the one that carries search.
private struct ActivitySearch: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: "Shop, category or note")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            content
        }
    }
}
