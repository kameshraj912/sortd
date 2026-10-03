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
    /// The search field is out (the magnifier was tapped). See `ActivitySearch`.
    @State private var searchOpen = false
    @State private var saveFailed = false
    @State private var cardFilter: Card?
    @State private var categoryFilter: SpendCategory?
    @State private var showingAdd = false
    @State private var recategorising: Transaction?
    @State private var deleted = 0
    @State private var undone = 0
    /// "Go to Date…" from the filter menu: the picker sheet is up.
    @State private var goingToDate = false
    /// The date picked in that sheet, waiting for the sheet to close.
    @State private var pickedDate: Date?
    /// The day the list should scroll to next (`ActivityDays.target`).
    @State private var jumpTarget: Date?
    /// Jumps made with "Go to Date…", for the haptic.
    @State private var jumps = 0
    #if DEBUG
    /// The day on screen in the old day pager (`showsDayPager`).
    @State private var dayPage: Date?
    /// Chevron taps that changed the day. The haptic plays on these, not
    /// when the pager picks a day itself (first show, a filter, a delete).
    @State private var dayChanges = 0
    /// Which way the last day change went, for the slide.
    @State private var dayDirection: Motion.Direction = .forward
    @Environment(\.crossFades) private var crossFades
    #endif
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
    /// True only while the intro's `.swipe` step is on screen: gates whether
    /// the first row spends a `GeometryReader` reporting its frame for the
    /// intro's cutout.
    @Environment(\.introWatchingFirstRow) private var introWatchingFirstRow
    /// A category picked in the sheet, waiting for the sheet to close.
    @State private var stagedChange: CategoryChange?
    /// Asks "Change all N … purchases?" when other purchases share the shop.
    @State private var confirmingChange: CategoryChange?

    #if DEBUG
    /// One scrolling list of every day is Activity again (spec
    /// 2026-10-03, option B). The one-day-per-page pager it replaced (25 Sep
    /// to 3 Oct 2026) stays in debug builds only, for one side-by-side look
    /// on the phone: SPEND_ACTIVITY_PAGER=1.
    static let showsDayPager = ProcessInfo.processInfo.environment["SPEND_ACTIVITY_PAGER"] == "1"
    /// Screenshots: SPEND_SCROLL_END=1 opens the list (or the pager's day)
    /// scrolled to its end, to show the last row against the tab bar.
    static let startScrolled = ProcessInfo.processInfo.environment["SPEND_SCROLL_END"] == "1"
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
            } else {
                // The list always shows (title, chips), with a "nothing
                // matches" message inside it, so a search can be cleared.
                #if DEBUG
                if Self.showsDayPager { dayPager } else { list }
                #else
                list
                #endif
            }
        }
        .background(Color.page)
        .modifier(ActivityTitle(title: fixedCard?.name ?? "Activity", large: largeTitle))
        // A card's own list always has search; the main list has it when
        // there's no Search tab (nav option A). Hand-rolling this field lost
        // the Cancel button and scroll-to-reveal, and left the app with two
        // different searches — the Search tab already uses .searchable.
        .modifier(ActivitySearch(enabled: searchEnabled, open: $searchOpen, text: $search))
        // Leaving the tab ends a search, so Activity is never found later
        // filtered by a query that is out of sight. (A push to a purchase
        // and back keeps it: that is the same tab.)
        .onChange(of: router.tab) { _, tab in
            if fixedCard == nil, tab != .activity, searchOpen { searchOpen = false; search = "" }
        }
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
            if searchEnabled, !searchOpen {
                // Our own magnifier beside the gear, opening the system search
                // field under the bar (`ActivitySearch`). In the top bar too
                // on a card's own list, so nothing floats over its rows.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") { searchOpen = true }
                        .tint(Color.ink)
                }
            }
            if NavLayout.current == .header || NavLayout.current == .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Purchase", systemImage: "plus") { showingAdd = true }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .sheet(isPresented: $showingAdd) { AddTransactionView() }
        .sheet(isPresented: $goingToDate, onDismiss: {
            // Scroll once the sheet is gone, so the move is seen.
            guard let picked = pickedDate else { return }
            pickedDate = nil
            jumpTarget = ActivityDays.target(for: picked, in: days.map(\.date))
        }) {
            GoToDateSheet(start: days.first?.date ?? .now, range: pickableDates) { pickedDate = $0 }
        }
        .feedback(.select, trigger: jumps)
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

    /// Every day in one scrolling list, newest first: a rounded card per
    /// day under its name and total. Search, the chips and the card filter
    /// cover every day at once; "Go to Date…" scrolls to a day. It is one
    /// List, the direct content of the navigation stack, so the bar and the
    /// tab bar track it.
    private var list: some View {
        let days = days
        // The swipe tip, and the intro's swipe step, point at the first row
        // of the main list.
        let firstRow = fixedCard == nil ? days.first?.items.first?.persistentModelID : nil
        return ScrollViewReader { proxy in
            List {
                // The same small title and brand bar as Home and Insights, so
                // the three tabs line up (Raj, 27 Sep).
                ListPageTitle(title: fixedCard?.name ?? "Activity")
                // Its own section, margins zeroed: an inset-grouped List
                // otherwise clips the row to the section's card, cutting the
                // chips off short of the real screen edge.
                Section { chipsRow }
                    .listSectionMargins(.horizontal, 0)
                if fixedCard == nil, NavOption.current.searchInActivity {
                    // Search is a bar button, so the tip sits under the
                    // chips as a card rather than pointing at it.
                    SortdTipView(tip: SearchTip())
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if days.isEmpty {
                    Section { noMatches.listRowBackground(Color.clear) }
                }
                ForEach(days) { day in
                    // The day's name and total as a real row in a section of
                    // its own, not a section header: a List only scrolls to
                    // rows (an id on a header lands on the row under it), and
                    // "Go to Date…" has to bring the day's name into view.
                    Section {
                        dayHeader(day)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .id(day.date)
                    }
                    .listSectionSpacing(0)
                    Section {
                        ForEach(day.items) { t in
                            row(t, introTarget: t.persistentModelID == firstRow)
                                .sortdTip(t.persistentModelID == firstRow ? SwipeTip() : nil, arrowEdge: .top)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            // No 44pt floor on row height: the day rows sit as close to
            // their card as a section header did, and the title row comes
            // out at the same height as Home's and Insights' (measured on
            // screenshots, 3 Oct 2026; with the floor it sat 2pt lower).
            .environment(\.defaultMinListRowHeight, 0)
            // At the end of the list the last card clears the floating tab
            // bar and the + circle with a little air, instead of touching it.
            .contentMargins(.bottom, 20, for: .scrollContent)
            // A short list (a filter or a search with few matches) can leave
            // this List's scroll offset a hair off zero after a push and pop
            // of the detail page, which the Liquid Glass tab bar reads as
            // "scrolled down" and never un-minimises (only Activity uses a
            // List here; Home's ScrollView never showed this). Pinning the
            // anchor to the top keeps the offset at a clean zero, so popping
            // back always reports "at the top" to the tab bar.
            .defaultScrollAnchor(.top)
            // "Go to Date…": the day's name lands just under the bar.
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                jumpTarget = nil
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
                jumps += 1
                AccessibilityNotification.Announcement("Showing \(dayTitle(target))").post()
            }
            .task {
                #if DEBUG
                // Screenshots: SPEND_GOTO_DATE=2026-09-20 jumps there the way
                // "Go to Date…" does; SPEND_GOTO_DATE=sheet opens its picker.
                if let goto = ProcessInfo.processInfo.environment["SPEND_GOTO_DATE"] {
                    try? await Task.sleep(for: .seconds(1))
                    if goto == "sheet" {
                        goingToDate = true
                    } else if let date = try? Date(goto, strategy: .iso8601.year().month().day()) {
                        jumpTarget = ActivityDays.target(for: date, in: days.map(\.date))
                    }
                }
                // `.top` on the last row runs into the end of the list, so it
                // stops where a person's own scroll would (bottom margin and
                // all); `.bottom` would stop short of the margin.
                guard Self.startScrolled, let last = days.last?.items.last else { return }
                try? await Task.sleep(for: .seconds(1))
                withAnimation { proxy.scrollTo(last.id, anchor: .top) }
                #endif
            }
        }
        .background(Color.page)
    }

    #if DEBUG
    /// The old pager (DEBUG `SPEND_ACTIVITY_PAGER=1` only, for one
    /// comparison with the list): one day at a time, newest first, moved
    /// with the chevrons in the day's header. Not wired to the intro or
    /// analytics; it goes once Raj has compared the two on his phone.
    private var dayPager: some View {
        let all = days
        let index = dayPage.flatMap { DayPager.dayIndex(for: $0, in: all.map(\.date)) } ?? 0
        return ScrollViewReader { proxy in
            List {
                ListPageTitle(title: fixedCard?.name ?? "Activity")
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
            .defaultScrollAnchor(.top)
            .task(id: dayPage) {
                guard Self.startScrolled, let last = all.indices.contains(index) ? all[index].items.last : nil else { return }
                try? await Task.sleep(for: .seconds(1))
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
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
                + Money.spoken(day.total, Money.home)).post()
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

    /// The day's header with a chevron either side, each a 44x44pt target.
    private func pagerHeader(_ day: ActivityDays.Day, position: DayPager.Position) -> some View {
        let newer = Button { stepDay(-1) } label: {
            Label("Newer Day", systemImage: "chevron.left")
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .disabled(position.index == 0)
        let older = Button { stepDay(1) } label: {
            Label("Older Day", systemImage: "chevron.right")
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .disabled(position.index + 1 >= position.count)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    dayHeader(day, position: (position.text, position.spoken))
                    HStack { newer; Spacer(); older }
                }
            } else {
                HStack(spacing: 0) { newer; dayHeader(day, position: (position.text, position.spoken)); older }
                    .padding(.horizontal, -14)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .textCase(nil)
    }
    #endif

    /// The chips as a list row, a section gap under the title. Its section
    /// has its margins zeroed, so the chips need their own inset (20pt, the
    /// title's) to still line up on the leading edge; the rest scroll out
    /// to the real screen edge instead of stopping at the card's margin.
    private var chipsRow: some View {
        chips(inset: 20)
            .scrollClipDisabled()
            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

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

    /// `introTarget`: the main list's first row, which the intro's
    /// `.swipe` step lights up.
    private func row(_ t: Transaction, introTarget: Bool = false) -> some View {
        ZStack {
            // Hidden link so the row has no chevron.
            NavigationLink {
                TransactionDetailView(transaction: t)
                    .navigationTransition(.zoom(sourceID: t.persistentModelID, in: zoom))
            } label: { EmptyView() }
                .opacity(0)
            TransactionRow(transaction: t)
        }
        // The intro's `.swipe` step needs this row's real frame for its
        // cutout, measured only while that step is on screen and read at
        // `RootView` via `.overlayPreferenceValue` (this sits inside a List
        // well below that level).
        .background {
            if introTarget, introWatchingFirstRow {
                GeometryReader { proxy in
                    Color.clear.preference(key: IntroFirstRowKey.self, value: proxy.frame(in: .global))
                }
            }
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

    /// The page draws its own title (`ListPageTitle`, as Home and Insights
    /// do); the large system title is kept as an option but off.
    private var largeTitle: Bool { false }

    /// "Today" on the left, the day's total on the right. The day reads in
    /// the primary colour and the total in secondary, both `.subheadline`,
    /// so the headers aren't faint (the old grey footnote was). `position`
    /// (the DEBUG pager only) adds "· 2 of 14" after the day.
    private func dayHeader(_ day: ActivityDays.Day,
                           position: (text: String, spoken: String)? = nil) -> some View {
        // At the largest text sizes the day gets its own line, so
        // "September" isn't broken in the middle.
        let big = typeSize.isAccessibilitySize
        let layout = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        let title = dayTitle(day.date)
        return layout {
            Text(position.map { "\(title) · \($0.text)" } ?? title)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(big ? nil : 1)
                .minimumScaleFactor(big ? 1 : 0.85)
            if !big { Spacer(minLength: 12) }
            Text(Money.format(day.total, Money.home))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .textCase(nil)
        // One stop for VoiceOver: "Today, 45 dollars 60", as a heading so
        // the rotor can move day by day.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position.map { "\(title), \($0.spoken)" } ?? title), \(Money.spoken(day.total, Money.home))")
        .accessibilityAddTraits(.isHeader)
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
            Divider()
            Button("Go to Date…", systemImage: "calendar") { goingToDate = true }
                .disabled(days.isEmpty)
        } label: {
            Label("Filter", systemImage: isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: Data

    private var isFiltering: Bool { cardFilter != nil || categoryFilter != nil }

    /// A card's own list always has search; the main list has it when
    /// there's no Search tab (nav option A).
    private var searchEnabled: Bool { fixedCard != nil || NavOption.current.searchInActivity }

    /// What the list shows: every day at once, through the search, the
    /// chips and the card filter, without rows waiting on Undo.
    private var days: [ActivityDays.Day] {
        ActivityDays.group(ActivityDays.visible(transactions, fixedCard: fixedCard, card: cardFilter,
                                                category: categoryFilter, search: search,
                                                hidden: Set(pending.items.map(\.persistentModelID))))
    }

    /// "Go to Date…" offers the days from the oldest purchase to today.
    private var pickableDates: ClosedRange<Date> {
        let all = days.map(\.date)
        let newest = max(Date.now, all.first ?? .now)
        return min(all.last ?? newest, newest)...newest
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


/// Activity's search. The magnifier in the bar (`TransactionsScreen`) sets
/// `open`; only then does the screen carry `.searchable`, as a field under
/// the bar with its own X, so the page title sits where Home's and
/// Insights' do the rest of the time.
///
/// Not the system's `.searchToolbarBehavior(.minimize)` button: in this bar
/// (filter on the left, gear beside it) its X folded the field away but
/// never ended the search, so the list stayed filtered by a query nobody
/// could see, and with the gear in the same glass group the X did nothing
/// at all (Raj on his phone, 3 Oct 2026; both reproduced in the simulator).
/// The standard field's X ends the search; closing clears the query.
private struct ActivitySearch: ViewModifier {
    let enabled: Bool
    @Binding var open: Bool
    @Binding var text: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Bool
    /// The system's own "search is active"; false again once the X is tapped.
    @State private var presented = false

    func body(content: Content) -> some View {
        Group {
            if enabled, open {
                content
                    // The long prompt has no room at accessibility sizes and
                    // the field showed as an empty pill (UI pass finding 8).
                    .searchable(text: $text, isPresented: $presented,
                                placement: .navigationBarDrawer(displayMode: .always),
                                prompt: typeSize.isAccessibilitySize ? "Search" : "Shop, category or note")
                    .searchFocused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // Straight into typing: the tap on the magnifier was the ask.
                    .task {
                        try? await Task.sleep(for: .milliseconds(50))
                        presented = true
                        focused = true
                    }
                    .onChange(of: presented) { was, now in
                        guard was, !now else { return }
                        text = ""
                        open = false
                    }
            } else {
                content
            }
        }
        .onChange(of: open) { _, now in
            if !now { presented = false; text = "" }
        }
        .task {
            #if DEBUG
            DebugSearchDriver.runIfAsked()
            // Screenshots: SPEND_SEARCH=1 opens the field; SPEND_SEARCH_TEXT=uber
            // also types a query.
            let env = ProcessInfo.processInfo.environment
            if enabled, env["SPEND_SEARCH"] == "1" || env["SPEND_SEARCH_TEXT"] != nil {
                try? await Task.sleep(for: .milliseconds(800))
                open = true
                try? await Task.sleep(for: .milliseconds(400))
                if let query = env["SPEND_SEARCH_TEXT"] { text = query }
            }
            #endif
        }
    }
}

/// "Go to Date…" from Activity's filter menu: a calendar. Tapping a day
/// picks it and closes at once (as Calendar's own Go to Date does); Go picks
/// the day already selected. The list then scrolls to that day, or the
/// nearest older one with purchases (`ActivityDays.target`).
struct GoToDateSheet: View {
    let range: ClosedRange<Date>
    let onPick: (Date) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(start: Date, range: ClosedRange<Date>, onPick: @escaping (Date) -> Void) {
        self.range = range
        self.onPick = onPick
        _date = State(initialValue: min(max(start, range.lowerBound), range.upperBound))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker("Date", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Color.brand)
                    .padding(.horizontal)
            }
            .navigationTitle("Go to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") { pick(date) }
                }
            }
            .onChange(of: date) { _, new in pick(new) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func pick(_ day: Date) {
        onPick(day)
        dismiss()
    }
}

/// The navigation title. The page draws its own title (`ListPageTitle`, as
/// Home and Insights do) and the bar keeps it for Back and VoiceOver only;
/// the system's large title stays here as an option (`largeTitle`, off).
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
