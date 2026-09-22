# 04 — Liquid Glass, navigation and "feel" for Sortd

Research date: 22 Sep 2026. Target: iOS 26.0+ deployment, built with Xcode 27 / iOS 27 SDK.

**How things were checked.** API signatures and availability below come from Apple's own
documentation JSON (developer.apple.com, fetched 22 Sep 2026) and the context7 copy of the
SwiftUI docs. Design rules come from the Human Interface Guidelines (HIG) pages and the
WWDC25/WWDC26 session pages. Anything I could not check against those is marked
**UNVERIFIED**. I did not build or run any of the snippets in Xcode, so treat them as
"signature-checked", not "compiled".

---

## 0. Where Sortd is today (from the code, `ux-refresh` worktree)

- `SpendApp.swift` uses a `TabView` with 4 tabs (Home, Activity, Insights, Settings), but
  **hides the system tab bar** (`.hideSystemTabBar()`) and draws its own `FlatTabBar`
  (white, hairline, no glass). The comment says this was done because iOS 27 always draws
  the system bar as floating Liquid Glass. So today Sortd has opted *out* of the look the
  founder now wants.
- "Add Purchase" (`plus`) is in three places: a `.primaryAction` toolbar item on Home
  (only when the nav bar is visible, i.e. the empty state), a `RoundIconButton` in the Home
  header, and a toolbar button on Activity. All open `AddTransactionView` as a plain sheet.
- There is no search anywhere (`.searchable` is not used).
- Good bits already there: `sensoryFeedback` on save/delete/selection, `swipeActions` on
  Activity and Recurring rows, `contextMenu` on Recurring, `.presentationDetents` on several
  sheets.

---

## 1. Recommended navigation model for Sortd

### 1.1 The short version

| Area | Recommendation |
|---|---|
| Tab bar | Go back to the **system** `TabView` tab bar (delete `FlatTabBar`). Three tabs: **Home, Activity, Insights**, plus a trailing **Search** tab (`Tab(role: .search)`). |
| Settings | **Out of the tab bar.** A gear/avatar button at the top of Home (`.topBarLeading` or `.topBarTrailing`) opening Settings as a sheet with its own `NavigationStack`. |
| Add (+) | A **floating, tinted glass button** at the bottom-trailing corner, above the tab bar, on Home and Activity. Tap = quick manual add. Long-press / menu = Scan receipt, Import statement, Add manually. It morphs into the add sheet with a zoom transition. |
| Search | Search tab using the "standard tab" style: a landing page with recent merchants, categories and cards, then a search field that searches all transactions. |
| Scroll | `.tabBarMinimizeBehavior(.onScrollDown)` so the bar shrinks while reading long lists. |
| Bottom accessory | **Not in v1.** Keep as a later experiment (a "this month: $X of $Y" pace strip). Stacking accessory + FAB + tab bar is the "glass sandwich" Apple warns about. |
| Prominent tab (iOS 27) | **Don't** use `Tab(role: .prominent)` for Add. It is for a destination, not an action (see 1.3). |

```
┌──────────────────────────────────┐
│ ⚙︎  Home                     ··· │  ← nav bar: settings button, title, overflow
│                                  │
│   content scrolls under glass    │
│                                  │
│                           ( + )  │  ← floating glassProminent button (Home, Activity)
│ [ Home  Activity  Insights ] (🔍)│  ← system Liquid Glass tab bar + search tab
└──────────────────────────────────┘
```

### 1.2 Why this shape

- **HIG, Tab bars:** "Use a tab bar to support navigation, not to provide actions." It also
  says a tab bar "can include a dedicated search tab at the trailing end." Settings is a place
  people visit rarely, so it is a weak use of one of only a few tab slots.
- **HIG, Search:** "If search is important, give it a primary position… In apps that use tab
  bars… search is a dedicated tab." A spending app lives on "where did I spend on X?", so search
  earns a tab. The HIG also says to aim for one place to search, so do not add separate search
  fields on Activity as well (a scoped filter on Activity is fine later).
- **HIG, Toolbars:** only one primary action, tinted, on the trailing side. "Add purchase" is
  Sortd's single most frequent action, so it gets the one tinted control in the app.
- **Reachability:** adding a purchase happens many times a day, often one-handed at a till. The
  bottom-trailing corner is the easiest reach. Apple's own Reminders puts a single tinted `+` at
  the bottom (MacRumors guide). Things keeps its draggable blue Magic Plus button, now glassy.
  Structured moved its add button to sit beside the floating tab bar. Foodnoms uses a floating
  button above the tab bar.
- **Removing the custom tab bar** gets the system behaviour for free: Liquid Glass, minimize on
  scroll, the search tab, Large Content Viewer, VoiceOver, the iOS 27 Liquid Glass tint slider,
  and iPad/resizable-iPhone layouts in iOS 27.

### 1.3 The add button: options compared

| Option | Verdict for Sortd |
|---|---|
| **Floating glass button over content** (Things, Structured, Foodnoms) | **Pick this.** Reachable, clear, room for a menu of add types. It's a custom control, so you own accessibility and placement (see pitfalls). Apple gives no official slot for a button *beside* the tab bar (Ryan Ashcraft's "beef" post; FabBar exists only because of this gap). So put it **above** the bar at the trailing edge, not next to it. |
| **Toolbar `+` at top-trailing** (Wallet-style, Mail/Notes-style on iPad) | Good *secondary* location and what Sortd does now. Too far to reach for the main action on a big phone. Keep it only if user testing shows people miss the FAB. |
| **`tabViewBottomAccessory`** | Designed for *persistent, app-wide features* like Music's MiniPlayer. It shows on every tab (Donny Wals), and Apple says not to put screen-specific actions in it (WWDC25 "Get to know the new design system"). A full-width "Add" bar also wastes space. Not recommended for Add. |
| **Search-tab slot as "+"** (GitHub, Craft did this) | Don't. The search role expects a full-screen destination, and misusing it confuses VoiceOver and breaks expectations. |
| **`Tab(role: .prominent)` (iOS 27)** | Don't use for Add. Apple's doc: it "provides prominent visual treatment to one of the tabs." It is still a tab, so it navigates. Sagar Unagar's write-up shows the "+ tab that opens a sheet" as the wrong pattern. It is also iOS 27-only and Sortd targets 26. |

### 1.4 Settings placement detail

- Home nav bar, leading edge: a `gearshape` (or a round avatar/initials button if accounts ever
  arrive). Put it in its own group with `.sharedBackgroundVisibility(.hidden)` if it looks crowded.
- Present `SettingsView` in a `.sheet` with `NavigationStack` inside and a Close button. Use a
  zoom transition from the gear button (snippet C8).
- Deep links (`Router`) that open settings pages should set a `showingSettings` flag and push
  the right path, instead of switching tabs.

### 1.5 Search tab detail

- `Tab(value: .search, role: .search) { NavigationStack { SearchView() } }` plus
  `.searchable(text:)` on the `TabView`.
- Landing page before typing: recent merchants, top categories this month, cards. Then results
  grouped by month, reusing the Activity row view (with the same swipe actions and context menu).
- Use `.searchSuggestions` and search tokens for category/card filters later.
- `.tabViewSearchActivation(.searchTabSelection)` focuses the field as soon as the tab is chosen,
  in the "button appearance" style. The HIG says the **standard tab style** (landing page first)
  suits discovery and the **button style** suits quick look-ups. For Sortd, start with the
  standard style: the landing page shows off the data and helps people who don't know what to
  type.

### 1.6 Insights stays a tab even though it's Pro

HIG: "Don't disable or hide tab bar buttons… If a section is empty, explain why." Keep the tab and
keep the `ProGate` explainer/paywall in the content. Don't hide the tab for free users.

---

## 2. Fifteen micro-interactions and gestures to add

Ordered roughly by value/effort. API numbers refer to the cookbook in section 3.

1. **+ zooms into the add sheet.** `matchedTransitionSource` on the floating button and
   `.navigationTransition(.zoom)` on `AddTransactionView`. The sheet grows out of the button and
   shrinks back into it. (C8)
2. **+ grows into an add-type menu.** Long-press (or a `Menu` with `primaryAction`) shows
   Add manually / Scan receipt / Import statement. Optional fancier version: a
   `GlassEffectContainer` where the + splits into three glass buttons with `glassEffectID`
   morphing. (C4, C5)
3. **Add sheet starts small.** `.presentationDetents([.medium, .large])`: amount + keypad +
   category at medium (glass, content visible behind), drag up for notes/receipt/split. Remove
   any custom `presentationBackground` so the system glass shows. (C9)
4. **Satisfying save.** On save: `.sensoryFeedback(.success, trigger:)` (already there), the
   checkmark does `.symbolEffect(.bounce, value:)`, and the new row slides into Recent with a
   spring. (C12, C14)
5. **Numbers roll, not jump.** Month total, budget left and category totals use
   `.contentTransition(.numericText(value:))` inside `withAnimation`. (C15)
6. **Swipe both ways on a transaction.** Leading swipe: change category (tinted in the category
   colour). Trailing: Delete (destructive, full swipe) and Exclude from budget. Activity already
   has trailing; add leading. On iOS 27, the new `onPresentationChanged:` overload can dim the row
   while actions show. (C13)
7. **Long-press a transaction for a preview.** `contextMenu(menuItems:preview:)` showing a mini
   receipt card (merchant, amount, card, map/receipt image) with Edit, Change Category, Mark
   Recurring, Share, Delete. (C11)
8. **Card tiles zoom into card detail.** Home card tile → `CardDetailView` with a zoom
   navigation transition. Long-press gives a preview. (C8, C11)
9. **Tab bar gets out of the way.** `.tabBarMinimizeBehavior(.onScrollDown)` on the `TabView`.
   Activity (long list) benefits most. (C2)
10. **Swipe between months.** On Home and Insights, a horizontal paging month header
    (`.scrollTargetBehavior(.paging)`), with `.sensoryFeedback(.selection, trigger: month)` on
    each snap. Totals animate with numericText. (C12, C15)
11. **Scrub the chart.** Insights/Home charts use `chartXSelection(value:)` to show a value bubble
    under your finger, with a selection haptic each time the selected day changes. (C12)
12. **Budget alert haptic.** When a save pushes a category over its limit, play `.warning` once
    and pulse the category ring. When it brings you back under, play `.success`. (C12, C14)
13. **Live sync feedback.** Pull-to-refresh on Home/Activity runs Gmail sync (`.refreshable`).
    The mail icon pulses while syncing (`.symbolEffect(.pulse, isActive:)`) and bounces when new
    receipts land. (C14)
14. **Undo instead of "are you sure".** After a swipe-delete, show a small glass capsule
    "Deleted · Undo" above the tab bar for 4 s (`glassEffect` + `.glassEffectTransition(.materialize)`),
    with an impact haptic on delete. Faster than a confirmation and kinder. (C4, C5)
15. **Empty states that teach.** Use `ContentUnavailableView` with a friendly symbol, one line of
    copy and one `.glassProminent` button: "Log your first purchase", "Connect Gmail to catch
    receipts", "Set a budget". Chris Raroque's talks list empty states and onboarding among the
    polish points (see section 5). (C6)

Bonus, iOS 27 only: let people **drag to reorder** Home categories/cards with `.reorderable()` +
`.reorderContainer(for:)`, behind `if #available(iOS 27, *)`. (C17)

HIG guardrails for all of these: "Avoid overusing haptics", "Make haptics optional", "Add motion
purposefully", and "generally avoid adding motion to UI interactions that occur frequently." So
keep the fancy motion on rare moments (first save, over-budget, month change). Keep row taps and
typing plain.

---

## 3. Code cookbook (signature-checked against Apple docs, 22 Sep 2026)

Availability is the iOS "introduced" version from Apple's doc JSON. Sortd's floor is iOS 26.0,
so anything marked 26.1+ or 27.0 needs an `#available` check.

### C1. System TabView with a search tab — iOS 18+ (`TabRole.search`), `tabViewSearchActivation` iOS 26.0

```swift
enum AppTab: Hashable { case home, activity, insights, search }

@State private var tab: AppTab = .home
@State private var query = ""

TabView(selection: $tab) {
    Tab("Home", systemImage: "house", value: .home) { HomeView() }
    Tab("Activity", systemImage: "list.bullet", value: .activity) { ActivityView() }
    Tab("Insights", systemImage: "chart.bar", value: .insights) {
        ProGate(feature: .insights) { InsightsView() }
    }
    Tab(value: .search, role: .search) {
        NavigationStack { SearchView(query: query) }
    }
}
.searchable(text: $query)
// Optional: focus the field as soon as the search tab is picked (button-style search).
// .tabViewSearchActivation(.searchTabSelection)
```
Checked: `Tab` has `init(_:systemImage:value:role:content:)` and `init(value:role:content:)`.
`TabRole.search`: "Searchable tab views will prefer to have the first tab with this role
implement search."

### C2. Minimize the tab bar on scroll — iOS 26.0

```swift
TabView(selection: $tab) { /* tabs */ }
    .tabBarMinimizeBehavior(.onScrollDown)   // also .onScrollUp, .never, .automatic
```
Declaration: `func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View`.
Only minimizes on iPhone, and only when a scroll view sits under the bar.

### C3. Bottom accessory (for a later "month pace" strip) — `content:` iOS 26.0, `isEnabled:` iOS 26.1

```swift
TabView { /* tabs */ }
    .tabBarMinimizeBehavior(.onScrollDown)
    .modifier(PaceAccessory(show: hasBudget))

struct PaceAccessory: ViewModifier {
    let show: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: show) { PaceStrip() }
        } else {
            content   // 26.0: no clean way to hide it (see pitfalls), so skip it
        }
    }
}

struct PaceStrip: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var body: some View {
        switch placement {
        case .inline:  Text("$412 left")                 // tab bar minimized
        default:       Label("$412 left of $1,500 · 18 days", systemImage: "gauge.medium")
        }
    }
}
```
Apple doc: "when the tab bar is normal size, the accessory appears above it; when the tab bar is
collapsed, the accessory displays inline."

### C4. Glass on a custom view — iOS 26.0

```swift
// Declaration: func glassEffect(_ glass: Glass = .regular,
//                               in shape: some Shape = DefaultGlassEffectShape()) -> some View
Label("Deleted", systemImage: "trash")
    .padding(.horizontal, 16).padding(.vertical, 10)
    .glassEffect()                                   // regular glass, capsule

Text("Over budget").padding()
    .glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 16))
```
`Glass` variants: `.regular`, `.clear`, `.identity`; modifiers `.tint(_ color: Color?)`,
`.interactive(_ isEnabled: Bool = true)`. Apply `glassEffect` **after** other appearance modifiers.

### C5. The floating + button, with morphing options — iOS 26.0

```swift
struct AddFAB: View {
    @Binding var showingAdd: Bool
    @State private var expanded = false
    @Namespace private var glassNS
    let zoomNS: Namespace.ID   // shared with the sheet for the zoom transition

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .trailing, spacing: 12) {
                if expanded {
                    optionButton("Scan receipt", "doc.viewfinder", id: "scan") { /* Router.open(.scan) */ }
                    optionButton("Import statement", "tray.and.arrow.down", id: "import") { /* … */ }
                }
                Button {
                    if expanded { withAnimation(.spring) { expanded = false } }
                    else { showingAdd = true }
                } label: {
                    Image(systemName: expanded ? "xmark" : "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.brand)
                .glassEffectID("add", in: glassNS)
                .matchedTransitionSource(id: "add", in: zoomNS)
                .accessibilityLabel("Add purchase")
                .onLongPressGesture { withAnimation(.spring) { expanded.toggle() } }
                .sensoryFeedback(.impact(weight: .light), trigger: expanded)
            }
        }
    }

    private func optionButton(_ title: String, _ symbol: String, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .buttonStyle(.glass)
            .glassEffectID(id, in: glassNS)
            .glassEffectTransition(.matchedGeometry)
    }
}

// Place it per screen (Home, Activity), above the tab bar, inside the safe area:
.overlay(alignment: .bottomTrailing) {
    AddFAB(showingAdd: $showingAdd, zoomNS: zoomNS).padding(.trailing, 20).padding(.bottom, 8)
}
```
Checked: `GlassEffectContainer.init(spacing: CGFloat? = nil, content:)`;
`glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID)`;
`glassEffectTransition(_:)` with `.matchedGeometry` / `.materialize` / `.identity`;
`glassEffectUnion(id:namespace:)` also exists. `.buttonStyle(.glass)` and `.glassProminent`
are iOS 26.0. `.buttonStyle(.glass(.clear))` (the `glass(_:)` static func) shows iOS 26.0 in the
docs, but `GlassButtonStyle.init(_:)` is 26.1. **Test `.glass(_:)` on a 26.0 simulator before
relying on it.** The long-press + `Button` combination is a common pattern but I did not test it.
A plain `Menu { … } label: { … } primaryAction: { showingAdd = true }` is the safer built-in
alternative. (`Menu.init(content:label:primaryAction:)`, iOS 15.)

**UNVERIFIED:** exactly where the FAB should sit relative to the system tab bar's safe area
when the bar is minimized. `.overlay` inside the tab's content respects the tab bar inset in my
understanding, but check it on device in both states.

### C6. Glass button styles — iOS 26.0

```swift
Button("Log your first purchase") { showingAdd = true }
    .buttonStyle(.glassProminent)   // tinted, one per screen
Button("Connect Gmail") { … }
    .buttonStyle(.glass)            // secondary

ContentUnavailableView {
    Label("No purchases yet", systemImage: "creditcard")
} description: {
    Text("Tap + or pay with Apple Pay and Sortd will log it.")
} actions: {
    Button("Log your first purchase") { showingAdd = true }.buttonStyle(.glassProminent)
}
```

### C7. Toolbar grouping, spacers and placements — iOS 26.0 (+ iOS 27 extras)

```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button("Settings", systemImage: "gearshape") { showingSettings = true }
    }
    .matchedTransitionSource(id: "settings", in: zoomNS)   // toolbar-content variant exists

    ToolbarItem(placement: .topBarTrailing) { MonthPicker() }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
        Menu("More", systemImage: "ellipsis") { /* Export, Budgets… */ }
    }
}
```
- `ToolbarSpacer(.fixed)` / `ToolbarSpacer(.flexible)` split items into separate glass groups.
- `.sharedBackgroundVisibility(.hidden)` on a `ToolbarItem` removes the shared glass and puts it in
  its own group (Sortd already uses this on Home's +).
- `DefaultToolbarItem(kind: .search, placement: .bottomBar)` positions the system search item
  (WWDC25 session 323 sample).
- `.searchToolbarBehavior(.minimize)` shows toolbar search as a button until tapped. (Apple's own
  doc example writes `.minimized`, but the symbol in the index is `.minimize`. Use `.minimize`.)
- **iOS 27 only:** `ToolbarItemPlacement.topBarPinnedTrailing` ("Pinned items only move to the
  overflow menu when search is active and there isn't enough room"), `.visibilityPriority(.high)`
  on `ToolbarContent`, and `ToolbarOverflowMenu { … }` for actions that always live in the
  overflow menu. Wrap them in `if #available(iOS 27, *)`. **UNVERIFIED:** whether
  `if #available` is accepted inside a `@ToolbarContentBuilder` in Xcode 27. If not, split the
  toolbar into two helper modifiers.

### C8. Zoom transitions (button → sheet, tile → detail) — iOS 18.0

```swift
@Namespace private var zoomNS

// Source: any view, or a ToolbarItem (CustomizableToolbarContent has its own variant)
CardTile(card).matchedTransitionSource(id: card.id, in: zoomNS)

// Push destination
.navigationDestination(for: Card.self) { card in
    CardDetailView(card: card)
        .navigationTransition(.zoom(sourceID: card.id, in: zoomNS))
}

// Sheet destination
.sheet(isPresented: $showingAdd) {
    AddTransactionView()
        .navigationTransition(.zoom(sourceID: "add", in: zoomNS))
}
```
Doc note: put `.navigationTransition` on the view that appears in the `NavigationStack` or sheet,
"outside of any containers such as VStack".

### C9. Sheets with detents and system glass — detents iOS 16

```swift
.sheet(isPresented: $showingAdd) {
    AddTransactionView()
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Do NOT add .presentationBackground(...) — WWDC25 323: remove custom
        // presentation backgrounds so the new Liquid Glass sheet material shows.
}
```
From WWDC25 "Get to know the new design system": partial-height sheets are glass and inset. As
you drag a sheet up it "recedes", becoming more opaque. HIG sheets: support swipe-to-dismiss.
If there are unsaved edits, confirm on swipe (`.interactiveDismissDisabled(hasChanges)` plus a
confirmation dialog).

### C10. Scroll edge effect and background extension — iOS 26.0

```swift
ScrollView { … }
    .scrollEdgeEffectStyle(.soft, for: .top)   // .automatic (default), .soft, .hard; nil resets
```
Rules (WWDC25 356): one edge effect per view, only where floating UI sits over content, soft on
iOS, hard mainly on macOS or for pinned headers/text controls. Don't stack them.

```swift
HeaderArtwork().backgroundExtensionEffect()   // mirrors + blurs the view into the safe area
```
Doc: "Apply this modifier with discretion… with only a single instance of background content."
For Sortd this suits one hero element at most (e.g. a card-gradient header in `CardDetailView`).
It clips the view.

### C11. Context menu with preview — iOS 16

```swift
TransactionRow(txn)
    .contextMenu {
        Button("Edit", systemImage: "pencil") { editing = txn }
        Button("Change Category", systemImage: "tag") { recategorising = txn }
        Button("Mark Recurring", systemImage: "repeat") { … }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete(txn) }
    } preview: {
        TransactionPreviewCard(txn).frame(width: 300)
    }
```
Declaration: `func contextMenu<M, P>(@ContentBuilder menuItems: () -> M, @ContentBuilder preview: () -> P) -> some View`.
Customise the lift shape with `.contentShape(.contextMenuPreview, .rect(cornerRadius: 16))`.

### C12. Haptics — iOS 17

```swift
.sensoryFeedback(.success, trigger: savedCount)
.sensoryFeedback(.selection, trigger: selectedMonth)
.sensoryFeedback(.warning, trigger: overBudgetCategory) { old, new in new != nil && old != new }
.sensoryFeedback(.impact(weight: .medium), trigger: deletedID)
```
Members checked in the docs: `success, warning, error, selection, increase, decrease, start, stop,
alignment, levelChange, pathComplete, impact, impact(weight:intensity:), impact(flexibility:intensity:)`.
Newer `press(_:)`, `release(_:)`, `selection(_:)` also exist (listed as iOS 26.0). Their use on
iPhone is unclear to me, so skip them.

### C13. Swipe actions — iOS 15; `onPresentationChanged` + `swipeActionsContainer` iOS 27

```swift
TransactionRow(txn)
    .swipeActions(edge: .leading) {
        Button("Category", systemImage: "tag") { recategorising = txn }
            .tint(txn.category.color)
    }
    .swipeActions(edge: .trailing) {
        Button("Delete", systemImage: "trash", role: .destructive) { delete(txn) }
        Button("Exclude", systemImage: "eye.slash") { exclude(txn) }.tint(.gray)
    }
```
iOS 27 additions (guard with `#available(iOS 27, *)`):
```swift
.swipeActions(edge: .trailing) { … } onPresentationChanged: { isSwiped = $0 }

ScrollView { LazyVStack { ForEach(txns) { TransactionRow($0).swipeActions { … } } } }
    .swipeActionsContainer()   // swipe actions outside List; no-op on List
```
Doc: adding swipe actions stops `onDelete` from making its own Delete action, so add Delete
yourself.

### C14. Symbol effects — iOS 17

```swift
Image(systemName: "checkmark.circle.fill").symbolEffect(.bounce, value: savedCount)   // discrete
Image(systemName: "envelope").symbolEffect(.pulse, isActive: isSyncing)             // indefinite
Image(systemName: expanded ? "xmark" : "plus").contentTransition(.symbolEffect(.replace))
```

### C15. Rolling numbers — iOS 17

```swift
Text(total, format: .currency(code: currency))
    .contentTransition(.numericText(value: total))
    .animation(.snappy, value: total)
```

### C16. Accessibility environment — iOS 13

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
@Environment(\.accessibilityReduceMotion) private var reduceMotion

.animation(reduceMotion ? nil : .spring, value: expanded)
```

### C17. Reorder (iOS 27 only)

```swift
if #available(iOS 27, *) {
    VStack {
        ForEach(categories) { CategoryTile($0) }.reorderable()
    }
    .reorderContainer(for: SpendCategoryItem.self) { difference in apply(difference) }
}
```
Declarations: `DynamicViewContent.reorderable()`; `reorderContainer(for:in:isEnabled:move:)`
(multi-collection); `reorderContainer(for:isEnabled:move:)` (single). Michael Tsai's round-up
quotes a developer report that `.reorderable()` crashes with some availability checks and popovers.
Test carefully.

### Not verified / removed

- **`toolbarMinimizeBehavior(_:for:)`** (shown in the WWDC26 "What's new in SwiftUI" page for
  auto-hiding the nav bar) is **not in Apple's current SwiftUI documentation index**. The doc URL
  returns 404, and Blake Crosley's write-up says it disappeared in later betas. **Don't build on it.**
- **iOS 27 "Liquid Glass slider".** The WWDC26 session page says glass "automatically responds to
  the new Liquid Glass slider to adjust its tint." I didn't find an API for it. It's a user
  setting, so system glass follows it and custom `glassEffect` probably does too. **UNVERIFIED for
  custom glass.**
- **Scroll-to-top / pop-to-root when re-tapping the selected tab** with the system `TabView`:
  expected system behaviour, **not verified** in this session. Test it.
- **Bottom `.bottomBar` toolbar items inside a tab that also shows a tab bar**: I did not verify
  how iOS 26/27 lays these out. That's one reason the plan uses an overlay FAB instead.

---

## 4. What other apps do with the primary "add" action (iOS 26)

| App | Where "add" lives | Source quality |
|---|---|---|
| **Reminders** (Apple) | Single blue `+` button at the bottom of the screen (no tab bar in this app). | MacRumors iOS 26 guide: verified |
| **Mail / Notes** (Apple) | Compose button in the **bottom toolbar**, trailing, next to search. WWDC25 session 323 shows this layout with `ToolbarSpacer` + `DefaultToolbarItem(kind: .search)`. | Session code: verified. Ryan Wesley post confirms Notes/Reminders/Journal use prominent bar buttons |
| **Music** (Apple) | No add. Uses the **bottom accessory** for the MiniPlayer, which merges inline when the bar minimizes. Search is a tab. | HIG tab bars + 9to5Mac: verified |
| **Wallet** (Apple) | `+` in the top-trailing nav bar (from memory). HIG search page says Wallet keeps search at the top so the pass stack at the bottom stays clear. | `+` position **UNVERIFIED** in this session. Search note verified (HIG) |
| **Health** (Apple) | iOS 27.2 beta redesign adds Insights and Longevity tabs. I couldn't confirm where "add data" or search now sit. | **UNVERIFIED** |
| **Fitness** (Apple) | iOS 26 added a Workout tab on iPhone (start a workout = a destination, not a +). | Search results summary, partly verified |
| **Things 3** | Blue-tinted, draggable **Magic Plus** floating button, now glassy and slightly "liquid" when dragged. | Cultured Code blog + MacStories: verified |
| **Structured** | Floating tab bar with the **add-task button centred beside it**. | Structured blog: verified |
| **Todoist** | Adopted the glass tab bar. Its search button expands with a bouncy animation. Add placement not described. | MacStories: partly verified |
| **Foodnoms** | Floating action button above a three-tab bar. The author admits it "sits awkwardly above empty space." | Ryan Wesley post: verified |
| **GitHub, Craft** | Put an action (Copilot, create) in the search-tab slot. Criticised as confusing. | Ryan Wesley post: verified |
| **Copilot Money, Flighty, Revolut** | No reliable source on their add/primary action placement. Flighty adopted glass and larger toolbar buttons. Revolut shipped Liquid Glass in TestFlight (Oct 2025) and is known for a collapsing tab bar. | **UNVERIFIED** for add placement |

**Takeaway:** apps with a tab bar *and* a frequent create action mostly use a floating button
(Things, Structured, Foodnoms). Apple's own create-heavy apps avoid tab bars and use a bottom
toolbar. Apple gives no official pattern for tab bar + add button, which is why these
workarounds exist.

### Apple Design Awards: what winners do well

- **2026:** Moonlitt (Interaction winner) was praised for "best-in-class Liquid Glass
  integration". Tide Guide (Visuals and Graphics winner) for "full-screen charts filled with
  custom animations" and Liquid Glass. Guitar Wiz (Inclusivity) for Dynamic Type, Increased
  Contrast and Differentiate Without Color. Structured was an Inclusivity finalist, and
  The Outsiders an Interaction finalist. *Lesson for Sortd:* data apps win with **charts as the
  hero plus glass only on controls**, and accessibility settings count.
- **2025:** CapWords (Delight and Fun), Play (Innovation, "thoughtfully crafted user interface"),
  Taobao (Interaction), Speechify (Inclusivity), Watch Duty (Social Impact), Feather (Visuals).
  Finalists included Denim, Lumy, iA Writer and Mela. None of these is a finance app. I only read
  the newsroom summaries, not the apps.

---

## 5. Creator advice on "premium feel"

- **Chris Raroque, "How I Make Apps FEEL Premium (5 examples)" (YouTube).** I could **only see
  the title, description and chapter list**, not the transcript. Chapters: app
  interactions/animations "levels 1–4", custom illustrations and animating them, illustrations
  that stand out, "invisible craft" (camera and dictation examples), building taste, and 3
  takeaways.
- **Raroque on The Startup Ideas Podcast, "Build Mobile Apps that Stand Out" (Nov 2025).** Episode
  page only, no transcript. Topics: animation and interactions, haptics, illustrations/mascots,
  iconography and typography, widgets, empty states and onboarding, design inspiration. His
  examples include **Luna, a manual budgeting app**, which is directly relevant: its pitch is
  that great UI makes manual logging bearable. That is the same bet Sortd makes for
  non-automatic entries.
- **What I take from it (my own synthesis, not quotes):** (1) make the most frequent action feel
  great: add-purchase speed, haptic, animation; (2) spend illustration/mascot effort on empty
  states and milestones, not everywhere; (3) "invisible craft" means the things people never
  notice consciously: the sheet opening at the right height, the keyboard already up, the
  category already guessed; (4) widgets and Live Activities as part of the product.
- **NN/G, "Liquid Glass Is Cracked, and Usability Suffers in iOS 26":** text over busy
  backgrounds loses contrast, tab bars get crowded by search, and "motion for motion's sake is not
  usability." A useful counterweight: polish must not cost legibility.

---

## 6. Pitfalls

1. **Glass on glass.** WWDC25 "Meet Liquid Glass": stacking glass "can quickly make the interface
   feel cluttered." For Sortd:
   - Don't put glass on content cards, list rows, charts or the category grid. HIG: "Don't use
     Liquid Glass in the content layer." Use standard materials or solid fills there.
   - Don't use FAB + bottom accessory + tab bar all at once.
   - Inside glass sheets, don't add glass buttons on glass panels. Use fills and vibrancy.
2. **Tint only the primary action.** "Use tinting selectively" (Meet Liquid Glass). Only the +
   (and a sheet's Done/Save) gets `glassProminent` or a brand tint. Tab bar and toolbar stay
   monochrome. HIG also says don't tint bar items with a colour close to the content background.
3. **Regular vs clear.** Use `.regular` everywhere. `.clear` only over photos/media, with a dimming
   layer (HIG suggests about 35% dark over bright content). Sortd has no media backgrounds, so
   don't use clear. Don't mix variants.
4. **Legibility of money.** Amounts under a glass tab bar or toolbar must stay readable. Use the
   system scroll edge effect (default soft). Don't add custom bar backgrounds. Test with bright,
   colourful category colours scrolling underneath.
5. **Reduce Transparency / Increase Contrast / Reduce Motion.** System glass adapts automatically
   (frostier, higher contrast, less elastic). Your *custom* motion does not: gate springs, morphs
   and zooms on `accessibilityReduceMotion`. Check custom material backgrounds with
   `accessibilityReduceTransparency`. Test all three settings plus the largest Dynamic Type on the
   FAB and the add sheet.
6. **Custom FAB accessibility.** Give it `accessibilityLabel("Add purchase")`, a 44pt+ target, and
   support Large Content Viewer (`.accessibilityShowsLargeContentViewer`). Make sure VoiceOver
   order reaches it (FabBar's README lists focus-jump and Large Content Viewer issues with custom
   tab-bar buttons). Keep a keyboard/Shortcut path (the existing `LogPurchaseIntent` is good).
7. **Performance.** Apple: "Creating too many Liquid Glass effect containers and applying too
   many effects to views outside of containers can degrade performance." Group nearby glass in
   one `GlassEffectContainer`. Never put `glassEffect` in every list row. Use
   `backgroundExtensionEffect` once per screen at most.
8. **Availability traps (floor is iOS 26.0):**
   - `tabViewBottomAccessory(isEnabled:)` is **26.1+**. On 26.0/26.1 a conditionally empty
     accessory leaves an **empty glass slot** (Apple DTS: intended). Developers report that
     `isEnabled` is only smooth from **26.2**.
   - `Tab(role: .prominent)`, `topBarPinnedTrailing`, `visibilityPriority`, `ToolbarOverflowMenu`,
     `swipeActionsContainer`, `swipeActions(…onPresentationChanged:)`, `reorderable` are
     **iOS 27.0**.
   - Don't apply modifiers conditionally on `TabView` (e.g. `if x { view.tabViewBottomAccessory… }`).
     It recreates the TabView and resets tab state (DTS reply in the same thread).
9. **iOS 27 makes iPhone apps resizable** (WWDC26 "What's new in SwiftUI"). Lay out the FAB and
   headers from size classes and safe areas, not screen width or idiom.
10. **Privacy cover and lock window.** `CoverWindow` sits above everything. Check that system glass
    bars and the FAB don't flash above it during scene changes.
11. **Don't over-animate frequent actions.** HIG motion: "generally avoid adding motion to UI
    interactions that occur frequently." Typing an amount should be instant. Save the flourish for
    the confirmation.

---

## 7. Suggested order of work (one stage at a time)

1. Swap `FlatTabBar` for the system tab bar. Move Settings to a toolbar button + sheet. Add
   `tabBarMinimizeBehavior`. Check legibility and the privacy cover.
2. Add the floating + with zoom into the add sheet (medium/large detents, no custom background).
3. Add the Search tab with a landing page.
4. Add the micro-interactions list, cheapest first: numericText, haptics, swipe/context menus,
   empty states.
5. Later: bottom-accessory "pace" strip experiment; iOS 27-only extras behind `#available`.

---

## Sources

Apple documentation and HIG (fetched 22 Sep 2026)
- HIG Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- HIG Tab bars: https://developer.apple.com/design/human-interface-guidelines/tab-bars
- HIG Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- HIG Searching: https://developer.apple.com/design/human-interface-guidelines/searching
- HIG Search fields: https://developer.apple.com/design/human-interface-guidelines/search-fields
- HIG Sheets: https://developer.apple.com/design/human-interface-guidelines/sheets
- HIG Playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- HIG Motion: https://developer.apple.com/design/human-interface-guidelines/motion
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- glassEffect(_:in:): https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- GlassEffectContainer: https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- glassEffectID(_:in:): https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
- glassEffectTransition(_:): https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)
- glassEffectUnion(id:namespace:): https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)
- Glass.clear: https://developer.apple.com/documentation/swiftui/glass/clear
- PrimitiveButtonStyle.glass / glassProminent / glass(_:): https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass , https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent , https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass(_:)
- GlassButtonStyle init(_:) (26.1): https://developer.apple.com/documentation/swiftui/glassbuttonstyle/init(_:)
- TabRole.search: https://developer.apple.com/documentation/swiftui/tabrole/search
- TabRole.prominent (iOS 27): https://developer.apple.com/documentation/swiftui/tabrole/prominent
- tabViewSearchActivation(_:): https://developer.apple.com/documentation/swiftui/view/tabviewsearchactivation(_:)
- tabBarMinimizeBehavior(_:): https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)
- tabViewBottomAccessory(content:) / (isEnabled:content:): https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:) , https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)
- tabViewBottomAccessoryPlacement: https://developer.apple.com/documentation/swiftui/environmentvalues/tabviewbottomaccessoryplacement
- ToolbarSpacer: https://developer.apple.com/documentation/swiftui/toolbarspacer
- sharedBackgroundVisibility(_:): https://developer.apple.com/documentation/swiftui/customizabletoolbarcontent/sharedbackgroundvisibility(_:)
- Landmarks toolbar glass sample: https://developer.apple.com/documentation/swiftui/landmarks-refining-the-system-provided-glass-effect-in-toolbars
- topBarPinnedTrailing (iOS 27): https://developer.apple.com/documentation/swiftui/toolbaritemplacement/topbarpinnedtrailing
- visibilityPriority(_:) (iOS 27): https://developer.apple.com/documentation/swiftui/toolbarcontent/visibilitypriority(_:)
- ToolbarOverflowMenu (iOS 27): https://developer.apple.com/documentation/swiftui/toolbaroverflowmenu
- searchToolbarBehavior(_:): https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)
- DefaultToolbarItem: https://developer.apple.com/documentation/swiftui/defaulttoolbaritem
- matchedTransitionSource(id:in:): https://developer.apple.com/documentation/swiftui/view/matchedtransitionsource(id:in:)
- navigationTransition(_:): https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)
- presentationDetents(_:selection:): https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:selection:)
- presentationBackground(_:): https://developer.apple.com/documentation/swiftui/view/presentationbackground(_:)
- scrollEdgeEffectStyle(_:for:): https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)
- backgroundExtensionEffect(): https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()
- sensoryFeedback(_:trigger:): https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)
- swipeActions(edge:allowsFullSwipe:content:): https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:)
- swipeActions(…onPresentationChanged:) (iOS 27): https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:onpresentationchanged:)
- swipeActionsContainer() (iOS 27): https://developer.apple.com/documentation/swiftui/view/swipeactionscontainer()
- contextMenu(menuItems:preview:): https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:preview:)
- symbolEffect(_:options:value:): https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:)
- reorderable() (iOS 27): https://developer.apple.com/documentation/swiftui/dynamicviewcontent/reorderable()
- reorderContainer(for:in:isEnabled:move:) (iOS 27): https://developer.apple.com/documentation/swiftui/view/reordercontainer(for:in:isenabled:move:)

WWDC sessions
- WWDC25 Meet Liquid Glass (219): https://developer.apple.com/videos/play/wwdc2025/219/
- WWDC25 Get to know the new design system (356): https://developer.apple.com/videos/play/wwdc2025/356/
- WWDC25 Build a SwiftUI app with the new design (323): https://developer.apple.com/videos/play/wwdc2025/323/
- WWDC26 What's new in SwiftUI (269): https://developer.apple.com/videos/play/wwdc2026/269/

Apple Design Awards
- 2026 winners (Newsroom): https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/
- 2026 winners and finalists: https://developer.apple.com/design/awards/
- 2025 winners and finalists (Newsroom): https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/
- MacStories 2025 list: https://www.macstories.net/news/2025-apple-design-awards-winners-and-finalists-announced/

Third-party write-ups
- Blake Crosley, What's New in SwiftUI for iOS 27: https://blakecrosley.com/blog/whats-new-swiftui-ios-27
- Michael Tsai, SwiftUI in appleOS 27: https://mjtsai.com/blog/2026/06/19/swiftui-in-appleos-27/
- Sagar Unagar, .prominent tab is not a FAB: https://www.sagarunagar.com/blog/swiftui-prominent-tab-is-not-a-floating-action-button/
- Donny Wals, Exploring tab bars on iOS 26: https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/
- Ryan Wesley, My Beef with the iOS 26 Tab Bar: https://ryanwesley.com/ios-26-tab-bar-beef/
- FabBar (Ryan Ashcraft): https://github.com/ryanashcraft/FabBar
- Apple Developer Forums, empty bottom accessory: https://developer.apple.com/forums/thread/803428
- NN/G, Liquid Glass Is Cracked: https://www.nngroup.com/articles/liquid-glass/
- MacStories OS 26 app roundup: https://www.macstories.net/stories/jump-into-the-liquid-glass-pool-a-macstories-os-26-app-roundup/
- Things for OS 26: https://culturedcode.com/things/blog/2025/09/things-for-os-26/
- Structured, what's new with iOS 26: https://structured.app/blog/ios26
- MacRumors, iOS 26 Notes and Reminders: https://www.macrumors.com/guide/ios-26-notes-app-reminders-app/
- MacRumors, Liquid Glass design gallery update: https://www.macrumors.com/2026/04/06/apple-liquid-glass-design-gallery-update/
- MacRumors, iOS 27.2 Health app beta: https://www.macrumors.com/2026/09/16/ios-27-2-health-app-beta/
- 9to5Mac, Music MiniPlayer iOS 26.1: https://9to5mac.com/2025/11/04/ios-26-1-gave-apple-music-convenient-new-trick/
- Thrifty Traveler, Flighty iOS 26 update: https://thriftytraveler.com/news/flighty-pro-app-ios26-update/
- Threads, Revolut Liquid Glass TestFlight: https://www.threads.com/@cidercircuit/post/DP9vvxwkcKd/revolut-adds-liquid-glass-throughout-its-app-in-the-latest-testflight-build

Creator content (title/description/chapters only, no transcript)
- Chris Raroque, How I Make Apps FEEL Premium (5 examples): https://www.youtube.com/watch?v=MXLF8b15GhQ
- The Startup Ideas Podcast with Chris Raroque: https://podcasts.apple.com/za/podcast/build-mobile-apps-that-stand-out-heres-the-playbook/id1593424985?i=1000738170249
- Luna budgeting: https://lunabudgeting.com/about
