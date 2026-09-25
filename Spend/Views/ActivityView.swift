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
    @State private var undone = 0
    /// The day on screen in the day pager (`dayPages`).
    @State private var dayPage: Date?
    /// Swipes between days. The haptic plays on these, not when the pager
    /// picks a day itself (first show, a filter, a delete).
    @State private var daySwipes = 0
    /// Swiped away but kept for a few seconds so Undo can bring them back.
    /// Each new delete restarts the timer; Undo brings back all of them.
    @State private var pending = PendingDeletes()
    /// True while the toast fades out at the end of the window. It stays in
    /// the view tree (faded with its own opacity and offset) and keeps taking
    /// taps until the fade ends; only then is the delete committed and the
    /// toast removed. A view being removed stops taking taps, which is why
    /// the fade is not a transition.
    @State private var closingToast = false
    /// What the last pull-to-refresh found.
    @State private var refreshNote: RefreshNote?
    @Namespace private var zoom
    /// A category picked in the sheet, waiting for the sheet to close.
    @State private var stagedChange: CategoryChange?
    /// Asks "Change all N … purchases?" when other purchases share the shop.
    @State private var confirmingChange: CategoryChange?

    /// One day per page, swiping between days (the TeuxDeux reference in
    /// spec 5): the default since 25 Sep 2026. Debug builds show the old
    /// single list with SPEND_ACTIVITY_LIST=1.
    #if DEBUG
    static let dayPages = ProcessInfo.processInfo.environment["SPEND_ACTIVITY_LIST"] != "1"
    /// Screenshots: SPEND_SCROLL_END=1 opens each day scrolled to its end,
    /// to show the bar and search field in their scrolled state.
    static let startScrolled = ProcessInfo.processInfo.environment["SPEND_SCROLL_END"] == "1"
    #else
    static let dayPages = true
    static let startScrolled = false
    #endif

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
            } else if Self.dayPages {
                dayPager
            } else {
                // The list always shows (title, search box, chips), with a
                // "nothing matches" message inside it, so a search can be cleared.
                list
            }
        }
        .background(Color.page)
        .modifier(ActivityTitle(title: fixedCard?.name ?? "Activity", large: largeTitle))
        // A card's own list always has search; the main list has it when
        // there's no Search tab (nav option A). Hand-rolling this field lost
        // the Cancel button and scroll-to-reveal, and left the app with two
        // different searches — the Search tab already uses .searchable.
        .modifier(ActivitySearch(enabled: fixedCard != nil || NavOption.current.searchInActivity,
                                 text: $search))
        .scrollDismissesKeyboard(.immediately)
        // Tips: the rules read the purchase figures (visits are counted by
        // RootView, on the tab), and typing a search is the search tip's "done".
        .onChange(of: transactions.count, initial: true) { if fixedCard == nil { TipState.update(from: transactions) } }
        .onChange(of: search) { _, text in
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { TipState.searchUsed() }
        }
        .toolbar {
            if fixedCard == nil, !transactions.isEmpty {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                    .sharedBackgroundVisibility(.hidden)
            }
            if fixedCard == nil { SettingsToolbarButton() }
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
                recategorise(change.transaction, to: change.category)
            }
            Button("Just This One") {
                // Nobody else moves: nothing to offer Undo for.
                PendingRecategorise.shared.dismiss()
                _ = try? TransactionLogger.recategorise(change.transaction, to: change.category, in: context,
                                                        applyToOthers: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: { change in
            Text("\"All\" also puts new \(change.transaction.merchant) purchases in \(change.category.name).")
        }
        .feedback(.delete, trigger: deleted)
        .feedback(.undo, trigger: undone)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                RecategoriseUndoToast()
                if !pending.isEmpty {
                    UndoToast(text: pending.text) { undoDelete() }
                        .opacity(closingToast ? 0 : 1)
                        .offset(y: closingToast ? 40 : 0)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 12)
        }
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
        // 8-second timer may never fire and the widgets keep the purchase.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { commitDelete() }
        }
    }

    // MARK: Delete with undo

    private static let toastSpring = Animation.spring(duration: 0.35)

    private func delete(_ t: Transaction) {
        var staged = false
        withAnimation(Self.toastSpring) {
            // A swipe while the toast is fading brings it back for the batch.
            closingToast = false
            // A new delete gives the whole batch a fresh window.
            staged = pending.stage(t, onExpire: { expireUndo() })
        }
        guard staged else { return }
        deleted += 1
        AccessibilityNotification.Announcement("\(pending.text). Undo available.").post()
    }

    /// The window is over: fade the toast while it stays in the tree and
    /// keeps taking taps, then delete. Only after the delete is the toast
    /// removed (with no animation, as it is already invisible).
    private func expireUndo() {
        withAnimation(Self.toastSpring, completionCriteria: .removed) {
            closingToast = true
        } completion: {
            // Undo, a new swipe or an early commit got in first (each resets
            // `closingToast`, which also ends this animation): leave it alone.
            guard closingToast else { return }
            pending.commit(in: context)
            closingToast = false
        }
    }

    /// Cancels the pending commit, even mid-fade, and brings every row back.
    private func undoDelete() {
        withAnimation(Self.toastSpring) {
            closingToast = false
            pending.undo()
        }
        undone += 1
    }

    /// Delete now, with no toast animation: used when the list goes away.
    private func commitDelete() {
        closingToast = false
        pending.commit(in: context)
    }

    // MARK: Category

    /// No other purchases from the shop: change it and learn, as before.
    /// Otherwise ask first, once the sheet has closed.
    private func pick(_ category: SpendCategory, for t: Transaction) {
        let others = (try? TransactionLogger.samePlace(as: t, in: context, excluding: pendingDeleteIDs)) ?? []
        if others.allSatisfy({ $0.category == category }) {
            recategorise(t, to: category)
        } else {
            stagedChange = CategoryChange(transaction: t, category: category, total: others.count + 1)
        }
    }

    /// Rows swiped away but not yet deleted: a category change leaves them
    /// alone, and never counts them in "Moved N others".
    private var pendingDeleteIDs: Set<UUID> { Set(pending.items.map(\.id)) }

    /// Moves the shop and, when others moved too, offers Undo for a while
    /// (the shared `PendingRecategorise` window).
    private func recategorise(_ t: Transaction, to category: SpendCategory) {
        guard let change = try? TransactionLogger.recategorise(t, to: category, in: context,
                                                               excluding: pendingDeleteIDs) else { return }
        PendingRecategorise.shared.stage(change)
        if let text = change.toastText {
            AccessibilityNotification.Announcement("\(text). Undo available.").post()
        }
    }

    // MARK: List

    private var list: some View {
        let days = days
        // The swipe tip points at the first row of the main list.
        let firstRow = fixedCard == nil ? days.first?.items.first?.persistentModelID : nil
        return List {
            ListPageTitle(title: fixedCard?.name ?? "Activity")
            chips
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if fixedCard == nil, NavOption.current.searchInActivity {
                // The search field is the system's own, so the tip sits
                // under it as a card rather than pointing at it.
                SortdTipView(tip: SearchTip())
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if filtered.isEmpty {
                Section {
                    noMatches
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(days, id: \.date) { day in
                Section {
                    ForEach(day.items) { t in
                        row(t).sortdTip(t.persistentModelID == firstRow ? SwipeTip() : nil, arrowEdge: .top)
                    }
                } header: {
                    dayHeader(day)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.page)
    }

    /// One day per page, swiping sideways between days (newest first).
    /// Each page is its own list, so pull-to-refresh, swipe actions and
    /// the zoom into a purchase work as they do in `list`; search and the
    /// chips filter the days the same way.
    private var dayPager: some View {
        // The pager is the screen's root scroll view and the chips are the
        // first row of every page, so the navigation bar has a list to
        // track: with the chips in a VStack above it, the search field never
        // showed (the bar was watching the chips' horizontal scroll view).
        Group {
            if days.isEmpty {
                List {
                    chipsRow
                    Section { noMatches.listRowBackground(Color.clear) }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 12, for: .scrollContent)
            } else {
                let all = days
                TabView(selection: swipedDayPage) {
                    ForEach(pagedDays, id: \.date) { day in
                        ScrollViewReader { proxy in
                            List {
                                chipsRow
                                Section {
                                    ForEach(day.items) { t in row(t) }
                                } header: {
                                    // The page dots are hidden, so the header
                                    // says where this day sits ("2 of 14"):
                                    // nothing else hints there are more days.
                                    dayHeader(day, position: DayPager.dayIndex(for: day.date, in: all.map(\.date))
                                        .map { DayPager.position($0, of: all.count) })
                                }
                            }
                            .listStyle(.insetGrouped)
                            .scrollContentBackground(.hidden)
                            .contentMargins(.top, 12, for: .scrollContent)
                            .task {
                                guard Self.startScrolled, let last = day.items.last else { return }
                                try? await Task.sleep(for: .seconds(1))
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .tag(Optional(day.date))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Paging to another day is a choice, like the card carousel.
                .feedback(.select, trigger: daySwipes)
                // The day on screen can go: cleared by a search or a chip, or
                // its last purchase swiped away. Stay next to where you were.
                .onChange(of: days.map(\.date), initial: true) { old, new in
                    if dayPage.map({ !new.contains($0) }) ?? true {
                        dayPage = DayPager.neighbour(of: dayPage, in: old, still: new)
                    }
                }
                // The page dots are hidden, so VoiceOver hears which day
                // this is and what it cost.
                .onChange(of: dayPage) { old, new in
                    guard old != nil, let new, let i = DayPager.dayIndex(for: new, in: all.map(\.date)) else { return }
                    let day = all[i]
                    AccessibilityNotification.Announcement(
                        "\(dayTitle(day.date)), \(DayPager.position(i, of: all.count).spoken), "
                        + Money.spoken(day.items.audTotal, Money.home)).post()
                }
            }
        }
        .background(Color.page)
    }

    /// The chips as a list row, a section gap under the title and search
    /// field (the list's own top margin is the rest of it).
    private var chipsRow: some View {
        chips
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The pager's selection. A swipe writes through here and counts as one;
    /// the pager's own choices write `dayPage` directly and stay silent.
    /// A fast swipe can hand over a day two pages away (the window of built
    /// pages moves under it): it settles on the adjacent day instead.
    private var swipedDayPage: Binding<Date?> {
        Binding(get: { dayPage }, set: { new in
            let settled = new.map { DayPager.settle($0, from: dayPage, in: days.map(\.date)) }
            if let settled, dayPage != nil, settled != dayPage { daySwipes += 1 }
            dayPage = settled
        })
    }

    /// Only the days near the one on screen are built (`DayPager.reach`
    /// either side); the window follows the page, so paging never runs out
    /// and all of history is never a list each.
    private var pagedDays: [(date: Date, items: [Transaction])] {
        let all = days
        let i = dayPage.flatMap { DayPager.dayIndex(for: $0, in: all.map(\.date)) } ?? 0
        return Array(all[DayPager.window(around: i, count: all.count)])
    }

    /// Category chips, like the reference's outlined pills.
    private var chips: some View {
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
    }

    /// The system's own no-results view, so it reads and behaves the way
    /// it does everywhere else on iOS.
    private var noMatches: some View {
        Group {
            if search.isEmpty {
                ContentUnavailableView {
                    Label("No purchases match", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing here with these filters on.")
                } actions: {
                    Button("Clear Filters") { cardFilter = nil; categoryFilter = nil }
                }
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func row(_ t: Transaction) -> some View {
        ZStack {
            // Hidden link so the row has no chevron.
            NavigationLink {
                TransactionDetailView(transaction: t)
                    .navigationTransition(.zoom(sourceID: t.persistentModelID, in: zoom))
            } label: { EmptyView() }
                .opacity(0)
            TransactionRow(transaction: t)
        }
        // The detail grows out of the row you tapped instead
        // of sliding in from the side.
        .matchedTransitionSource(id: t.persistentModelID, in: zoom)
        .listRowBackground(Color.card)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 48 }
        .swipeActions(edge: .leading) {
            Button("Category", systemImage: "tag") { TipState.swipeUsed(); recategorising = t }
                .tint(t.category.color)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { TipState.swipeUsed(); delete(t) }
                .tint(.red)
        }
        .contextMenu {
            Button("Change Category", systemImage: "tag") { recategorising = t }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(t) }
        } preview: {
            TransactionPreview(transaction: t)
        }
    }

    /// The day pager is on: the bar shows the large "Activity" title with
    /// the search field under it, like Messages or WhatsApp.
    private var largeTitle: Bool { Self.dayPages && fixedCard == nil && !transactions.isEmpty }

    /// `position` (the pager only) adds "· 2 of 14" after the day.
    private func dayHeader(_ day: (date: Date, items: [Transaction]),
                           position: DayPager.Position? = nil) -> some View {
        // At the largest text sizes the day gets its own line, so
        // "September" isn't broken in the middle.
        let big = typeSize.isAccessibilitySize
        let layout = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                         : AnyLayout(HStackLayout())
        let title = dayTitle(day.date)
        return layout {
            Text(position.map { "\(title) · \($0.text)" } ?? title)
                .accessibilityLabel(position.map { "\(title), \($0.spoken)" } ?? title)
            if !big { Spacer() }
            Text(Money.format(day.items.audTotal, Money.home))
                .monospacedDigit()
                .accessibilityLabel(Money.spoken(day.items.audTotal, Money.home))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textCase(nil)
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
        let hidden = Set(pending.items.map(\.persistentModelID))
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
            .feedback(.select, trigger: picked)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                // Under the large title, like Messages: it scrolls away with
                // the list and a pull down brings it back, at every text size.
                // The long prompt has no room at accessibility sizes and the
                // field showed as an empty pill (UI pass finding 8).
                .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: typeSize.isAccessibilitySize ? "Search" : "Shop, category or note")
                .searchFocused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .task {
                    #if DEBUG
                    // Screenshots: SPEND_SEARCH=1 opens with the field active.
                    if ProcessInfo.processInfo.environment["SPEND_SEARCH"] == "1" {
                        try? await Task.sleep(for: .milliseconds(600))
                        focused = true
                    }
                    #endif
                }
        } else {
            content
        }
    }
}

/// The navigation title. The day pager uses the system's large title, which
/// shrinks into the bar as the list scrolls and carries the search field
/// under it. Everywhere else the page draws its own title and the bar keeps
/// it for Back and VoiceOver only.
private struct ActivityTitle: ViewModifier {
    let title: String
    let large: Bool

    func body(content: Content) -> some View {
        if large {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
        } else {
            content.brandedTitle(title)
        }
    }
}
