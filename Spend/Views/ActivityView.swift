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
    // Excludes the removed "Send a Test Tap" button's rows everywhere here
    // (every day page, search and a card's own list): `Transaction.excludingLegacyTest`.
    @Query(filter: Transaction.excludingLegacyTest, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var search = ""
    @State private var saveFailed = false
    @State private var cardFilter: Card?
    @State private var categoryFilter: SpendCategory?
    @State private var showingAdd = false
    @State private var recategorising: Transaction?
    @State private var deleted = 0
    @State private var undone = 0
    /// The day on screen in the day pager (`dayPages`).
    @State private var dayPage: Date?
    /// Chevron taps that changed the day. The haptic plays on these, not
    /// when the pager picks a day itself (first show, a filter, a delete).
    @State private var dayChanges = 0
    /// Which way the last day change went, for the slide.
    @State private var dayDirection: Motion.Direction = .forward
    @Environment(\.crossFades) private var crossFades
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
    @State private var router = Router.shared
    /// The purchase a widget row linked to, pushed as its detail.
    @State private var linked: Transaction?
    /// True only while the intro's `.move` step is on screen: gates whether
    /// `pagerHeader` spends a `GeometryReader` reporting its frame for the
    /// intro's cutout.
    @Environment(\.introWatchingDayHeader) private var introWatchingDayHeader
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
                               message: "Your purchases will show up here.") {
                        if fixedCard == nil {
                            Button("Add a Purchase") { showingAdd = true }
                                .buttonStyle(.glassProminent).tint(Color.brand).foregroundStyle(Color.onBrand)
                        }
                    }
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
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                TipState.searchUsed()
                Analytics.shared.trackOncePerSession(.searchUsed)
            }
        }
        // The intro's `.move` step: a real day change alongside its finger
        // tap, if there's a second day to move to (fresh, empty demo data
        // has only one). Only this view knows that.
        .onChange(of: router.pendingIntroDayTap, initial: true) { _, pending in
            guard pending, fixedCard == nil else { return }
            router.pendingIntroDayTap = false
            if days.count > 1 { stepDay(1) }
        }
        // A Recent widget row ("sortd://purchase/<id>"): open that purchase.
        // Deleted or merged since the widget was drawn: do nothing, so the
        // person simply lands on Activity.
        .onChange(of: router.pendingPurchase, initial: true) { _, id in
            guard let id, fixedCard == nil else { return }
            router.pendingPurchase = nil
            var find = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
            find.fetchLimit = 1
            linked = (try? context.fetch(find))?.first
        }
        .navigationDestination(item: $linked) { TransactionDetailView(transaction: $0) }
        .toolbar {
            if fixedCard == nil, !transactions.isEmpty {
                // No `.sharedBackgroundVisibility(.hidden)`: keeps its glass
                // circle, like the gear (`SettingsToolbarButton`) beside it.
                ToolbarItem(placement: .topBarLeading) { filterMenu }
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
                let from = change.transaction.category
                do {
                    _ = try TransactionLogger.recategorise(change.transaction, to: change.category, in: context,
                                                           applyToOthers: false)
                } catch {
                    ErrorLog.report(error, where: "Activity.recategorise")
                    saveFailed = true
                }
                Analytics.shared.track(.categoryChanged, ["from": .string(from.rawValue), "to": .string(change.category.rawValue)])
            }
            Button("Cancel", role: .cancel) {}
        } message: { change in
            Text("\"All\" also puts new \(change.transaction.merchant) purchases in \(change.category.name).")
        }
        .feedback(.delete, trigger: deleted)
        .saveFailedAlert($saveFailed)
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
            // Pull down to refresh exchange rates.
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
        let from = t.category
        let change: RecategoriseChange
        do {
            change = try TransactionLogger.recategorise(t, to: category, in: context,
                                                        excluding: pendingDeleteIDs)
        } catch {
            ErrorLog.report(error, where: "Activity.recategorise")
            saveFailed = true
            return
        }
        Analytics.shared.track(.categoryChanged, ["from": .string(from.rawValue), "to": .string(category.rawValue)])
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

    /// One day at a time, newest first: tap the chevrons in the day's header
    /// to move a day. Rows keep the sideways swipe for their own actions
    /// (leading = Category, trailing = Delete, the iOS convention), so
    /// paging the day never fights a swipe on a row. It is one List, the
    /// direct content of the navigation stack, so the bar tracks it:
    /// scrolling up folds the large title into the bar and hides the search
    /// field, and a pull down at the top brings them back. (Each day in a
    /// paging TabView had its own list, and the bar tracked none of them.)
    private var dayPager: some View {
        let all = days
        let index = dayPage.flatMap { DayPager.dayIndex(for: $0, in: all.map(\.date)) } ?? 0
        return ScrollViewReader { proxy in
            List {
                // The same small title and brand bar as Home and Insights, so
                // the three tabs line up (Raj, 27 Sep; the large system title
                // sat higher and bigger than the other two).
                ListPageTitle(title: fixedCard?.name ?? "Activity")
                // Its own section, margins zeroed: an inset-grouped List
                // otherwise clips the row to the section's card, cutting the
                // chips off short of the real screen edge.
                Section { chipsRow }
                    .listSectionMargins(.horizontal, 0)
                if all.isEmpty {
                    Section { noMatches.listRowBackground(Color.clear) }
                } else {
                    let day = all[index]
                    Section {
                        ForEach(day.items) { t in
                            row(t).transition(Motion.transition(dayDirection, crossFades: crossFades))
                        }
                    } header: {
                        pagerHeader(day, position: DayPager.position(index, of: all.count))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            // A short day (its content shorter than the screen) can leave
            // this List's scroll offset a hair off zero after a push and
            // pop of the detail page, which the Liquid Glass tab bar reads
            // as "scrolled down" and never un-minimises (only Activity uses
            // a List here; Home's ScrollView never showed this). Pinning
            // the anchor to the top keeps the offset at a clean zero, so
            // popping back always reports "at the top" to the tab bar.
            .defaultScrollAnchor(.top)
            .task(id: dayPage) {
                #if DEBUG
                guard Self.startScrolled, let last = all.indices.contains(index) ? all[index].items.last : nil else { return }
                try? await Task.sleep(for: .seconds(1))
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                #endif
            }
        }
        // Paging to another day is a choice, like the card carousel.
        .feedback(.select, trigger: dayChanges)
        // The day on screen can go: cleared by a search or a chip, or
        // its last purchase swiped away. Stay next to where you were.
        .onChange(of: all.map(\.date), initial: true) { old, new in
            if dayPage.map({ !new.contains($0) }) ?? true {
                dayPage = DayPager.neighbour(of: dayPage, in: old, still: new)
            }
        }
        // There are no page dots, so VoiceOver hears which day this is and
        // what it cost.
        .onChange(of: dayPage) { old, new in
            guard old != nil, let new, let i = DayPager.dayIndex(for: new, in: all.map(\.date)) else { return }
            let day = all[i]
            AccessibilityNotification.Announcement(
                "\(dayTitle(day.date)), \(DayPager.position(i, of: all.count).spoken), "
                + Money.spoken(day.items.audTotal, Money.home)).post()
        }
        .background(Color.page)
    }

    /// Moves one day: +1 is the next older day, -1 the next newer. Nothing
    /// past either end.
    private func stepDay(_ delta: Int) {
        let dates = days.map(\.date)
        guard let current = dayPage ?? dates.first,
              let next = DayPager.day(delta, from: current, in: dates) else { return }
        dayDirection = delta > 0 ? .forward : .backward
        withAnimation(crossFades ? .easeInOut(duration: 0.2) : .snappy) { dayPage = next }
        dayChanges += 1
    }

    /// The day's header with a chevron either side: the only way to move a
    /// day (rows keep sideways swipe for their own actions), and the way in
    /// for VoiceOver and Switch Control. Each chevron gets a 44x44pt tap
    /// target, grown around the glyph rather than by scaling it up.
    private func pagerHeader(_ day: (date: Date, items: [Transaction]), position: DayPager.Position) -> some View {
        // The 44pt frame sits inside the label, so the whole square takes
        // the tap; outside it, only the glyph would.
        let newer = Button {
            stepDay(-1)
            Analytics.shared.track(.dayStepped, ["direction": .string("newer")])
        } label: {
            Label("Newer Day", systemImage: "chevron.left")
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .disabled(position.index == 0)
        let older = Button {
            stepDay(1)
            Analytics.shared.track(.dayStepped, ["direction": .string("older")])
        } label: {
            Label("Older Day", systemImage: "chevron.right")
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .disabled(position.index + 1 >= position.count)
        // The intro's `.move` step points its finger at this button's own
        // frame, not the header row's — the row's measured frame doesn't
        // line up with the chevron's 44pt square (it hangs out past the
        // row's own bounds, the `.padding(.horizontal, -14)` below).
        .background {
            if introWatchingDayHeader {
                GeometryReader { proxy in
                    Color.clear.preference(key: IntroDayHeaderKey.self,
                                            value: IntroDayFrames(chevron: proxy.frame(in: .global)))
                }
            }
        }
        // At the largest sizes the chevrons get their own row, so the day
        // keeps the full width.
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    dayHeader(day, position: position)
                    HStack { newer; Spacer(); older }
                }
            } else {
                // The squares hang out past the header's inset, so the
                // glyphs sit where the small chevrons did and the day keeps
                // one line.
                HStack(spacing: 0) { newer; dayHeader(day, position: position); older }
                    .padding(.horizontal, -14)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.footnote.weight(.semibold))
        .textCase(nil)
        // The intro's `.move` step needs this row's real frame for its
        // cutout — only measured while it's actually on screen for that
        // (docs/specs/2026-09-26-app-intro-v2.md), a plain `PreferenceKey`
        // read at `RootView` via `.overlayPreferenceValue`, since this sits
        // inside a `List` well below that level.
        .background {
            if introWatchingDayHeader {
                GeometryReader { proxy in
                    Color.clear.preference(key: IntroDayHeaderKey.self,
                                            value: IntroDayFrames(header: proxy.frame(in: .global)))
                }
            }
        }
    }

    /// The chips as a list row, a section gap under the title and search
    /// field. Its section has its margins zeroed (`dayPager`), so the chips
    /// need their own inset (matching the search field's, 20pt) to still
    /// line up on the leading edge; the rest scroll out to the real screen
    /// edge instead of stopping at the card's margin.
    private var chipsRow: some View {
        chips(inset: 20)
            .scrollClipDisabled()
            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Category chips, like the reference's outlined pills.
    private var chips: some View { chips(inset: 20) }

    private func chips(inset: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: categoryFilter == nil) { categoryFilter = nil }
                ForEach(usedCategories) { c in
                    chip(c.name, dot: c.color, selected: categoryFilter == c) {
                        categoryFilter = categoryFilter == c ? nil : c
                    }
                }
            }
            .padding(.horizontal, inset)
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

    /// The page draws its own title everywhere now (see `dayPager`); the
    /// large system title is kept as an option but off.
    private var largeTitle: Bool { false }

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
                .lineLimit(big ? nil : 1)
                .minimumScaleFactor(big ? 1 : 0.85)
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
        .buttonStyle(.pressable)
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
        let matchesSearch = SearchText.matcher(for: search)
        let hidden = Set(pending.items.map(\.persistentModelID))
        return transactions.filter { t in
            !hidden.contains(t.persistentModelID)
            && (fixedCard == nil || t.card == fixedCard)
            && (cardFilter == nil || t.card == cardFilter)
            && (categoryFilter == nil || t.category == categoryFilter)
            && matchesSearch(t)
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
                        .buttonStyle(.pressable)
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
                // A search button in the bar that opens into the field
                // (iOS 26 minimize), so the page title sits where Home's and
                // Insights' do instead of under a permanent search pill.
                // The long prompt has no room at accessibility sizes and the
                // field showed as an empty pill (UI pass finding 8).
                .searchable(text: $text, placement: .toolbar,
                            prompt: typeSize.isAccessibilitySize ? "Search" : "Shop, category or note")
                .searchToolbarBehavior(.minimize)
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
