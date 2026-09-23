# 01 — Current UI audit (Sortd, branch `ux-refresh`)

Date: 22 Sep 2026. Read-only audit of the code as it is on `ux-refresh`. Every claim cites
`file:line`. Paths are relative to the repo root (`Sortd/…`). Nothing was run in the
simulator for this pass, so anything about how it *feels* is inferred from the code and
marked as such.

---

## 1. Onboarding

Presented as a `fullScreenCover` from `RootView` while `onboardingDone` is false
(`Sortd/App/SortdApp.swift:202-204`). Steps are an enum
(`Sortd/Views/OnboardingView.swift:26`):

`welcome → currency → cards → cardDetails → applePay → email → budget → reminders → pro → finish`

`cardDetails` is skipped when no cards were added, and `email` is skipped when
`Features.gmail` is false (`OnboardingView.swift:86-92`, `209-218`). `Features.gmail` is true in
DEBUG, SORTD_BETA and SORTD_GMAIL builds (`Sortd/App/Features.swift:8-14`), so today it is shown.

### Chrome (every step)
- Top bar: back chevron, a segmented progress bar (one capsule per step shown, coloured with
  `brandPalette`), and **"Skip setup"**. Skip goes straight to `finish`, not one step on
  (`OnboardingView.swift:94-136`, `122-126`). Skip is **hidden on `cardDetails`**
  (`:119`). The progress bar is `accessibilityHidden` and has no "step X of Y" text (`:118`).
- Bottom bar: one full-width primary pill. The Pro step has its own layout with a price line
  (`:138-190`).
- Page change: asymmetric slide + fade (`:58-60`), `.snappy` animation, selection haptic on each
  step (`:80`).

### Screens in order

| # | Step | What it asks | Primary button | Notes |
|---|------|-------------|----------------|-------|
| 0 | Welcome (`:254-288`) | Nothing. Icon, "sortd" wordmark, "Your spending, logged by itself.", 4 feature rows (Apple Pay taps, every card/currency, bills predicted, private) | "Get Started" (`:194`) | Two text links: **"I already have spending to bring in"** opens `ImportView` in a sheet (`:171-176`, `:69`); **"Explore with sample data"** loads `DemoData` and finishes setup (`:177-183`). |
| 1 | Currency (`:305-328`) | Pick home currency. Detected one first ("From your iPhone"), 8 more rows, "Other currencies" menu | "Continue" | Pre-filled from the phone (`:21`). |
| 2 | Cards (`:352-368`) | Pick a bank per card from a country chip row + 2-column bank grid; "Other bank" adds a generic card | "Continue" | Each tap adds one card (`:490-497`). List of added cards shows under the grid (`:358-362`). |
| 3 | Card details (`:532-541`, form `:1045-1196`) | For **every** card: nickname, Debit/Credit, last 4 of card number (required), Apple Pay device number (required when two cards share a bank) | "Continue" — **disabled** and relabelled "Add digits for N more cards" until every card is complete (`:164-168`, `:195`, `:509-520`) | No Skip on this step (`:119`). Only way out without typing digits is Back and removing cards. |
| 4 | Apple Pay (`:586-650`) | Set up a Shortcuts Wallet automation in Apple's Shortcuts app. iOS 27: 6-page drawn walkthrough (`WalletSetupGuide`, `Sortd/Views/WalletSetupGuide.swift:19-32`); older: 3 mini-steps (`:594-601`) | "I'll Do This Later" until a tap arrives, then "Continue" (`:196`) | "Open Shortcuts" deep-links `shortcuts://` (`:605-613`). "Detailed Steps" opens `SetupGuideView` sheet (`:614`, `:77-79`). A live status card flips from spinner "Waiting for your first tap" to green "Connected" with a success haptic (`:626-648`). Header says "takes about two minutes" (`:588`). |
| 5 | Email (`:702-733`) | "Connect Gmail" | "I'll Do This Later" / "Continue" (`:197`) | Tapping Connect opens `ConnectGmailSheet` **if Pro, otherwise the paywall** (`:67`). The button does not say it is Pro. |
| 6 | Budget (`:741-803`) | Monthly budget: big number field + 5 preset chips + "No budget for now" | "Continue" | Shows "About $X a day" live with `numericText` (`:762-767`). |
| 7 | Reminders (`:884-918`) | Bill reminders the day before, 9 am. Sample "Netflix tomorrow" card | "Not Now" / "Continue" (`:198`) | "Turn On Reminders" **opens the paywall if not Pro** (`:903`); only Pro users get the system notification prompt (`:904`). |
| 8 | Pro (`:816-858`, bottom bar `:143-162`) | Pro feature list, trial CTA, price line, "Maybe Later" | Trial pill ("Start 14 days free" or "See Plans") opens `PaywallView` (`:144`, `:870-872`) | Copy: "You'll skip this. Then on Thursday you'll try to scan a receipt, find it locked, and come back. We'll wait." (`:851`). Price line reads the real App Store price (`:874-882`). |
| 9 | Finish (`:920-957`) | Nothing. Checklist of what was set (currency, cards, Apple Pay, email, budget, reminders, Pro) + 3 tips (import, widget, backup) | "Start Using Sortd" (`:200`) | Finishing rebases FX to the chosen currency (`:220-224`). |

### Taps before value
- **Fastest real path:** Get Started → Skip setup → Start Using Sortd = **3 taps**, and the user
  lands on an **empty Home** (`Sortd/Views/HomeView.swift:31-32`, `:416-426`). No purchases, so
  no numbers, chart or cards.
- **Full path, no cards:** 9 taps across 9 screens (welcome + 7 steps + finish; card details skipped).
- **Full path, with N cards:** 10 screens, plus a bank tap per card, plus 4 digits per card
  (8 if two cards share a bank), all mandatory before Continue enables.
- **Sample data:** 1 tap from Welcome gives a populated Home with a "You're looking at sample
  data" banner (`HomeView.swift:37`, `:90-110`). "Clear" wipes it and **reopens onboarding
  from the start** (`HomeView.swift:100-103`, `SortdApp.swift:199-201`).

### Where permissions and the paywall appear
| Thing | Where | Gate |
|---|---|---|
| Shortcuts / Wallet automation | Onboarding step 4 (`OnboardingView.swift:586-650`); later Settings › Apple Pay Auto-Logging (`SettingsView.swift:43-56`) and Home empty state (`HomeView.swift:422`) | Free. External app, manual. |
| Gmail OAuth | Onboarding step 5 (`OnboardingView.swift:723`); Settings › Gmail section (`SettingsView.swift:63`) | Pro. Non-Pro gets paywall (`OnboardingView.swift:67`). |
| Notifications | Onboarding step 7 (`OnboardingView.swift:904`); Settings toggle (`SettingsView.swift:71-81`) | Pro. Non-Pro gets paywall first (`OnboardingView.swift:903`, `SettingsView.swift:75`). Request is `alert, sound, badge` (`Sortd/Services/Reminders.swift:16`). |
| Camera | **Not in onboarding.** Only Add Purchase › "Scan Receipt" (`Sortd/Views/AddTransactionView.swift:212`, `:148-150`), using `VNDocumentCameraViewController` (`Sortd/Views/ReceiptScanView.swift:153-154`) | Pro. Non-Pro gets paywall (`AddTransactionView.swift:149`). |
| Photos | Import › PhotosPicker (`Sortd/Views/ImportView.swift:98`) | Free. |
| Face ID | Settings › Security toggle (`SettingsView.swift:177-190`) | Free. |
| Paywall | Onboarding steps 5, 7, 8 (three entry points); Settings top row (`SettingsView.swift:26-41`); whole Insights tab (`SortdApp.swift:172`); Subscriptions & Bills (`SettingsView.swift:67`, `RecurringView.swift:236-237`); category limit (`InsightsView.swift:204`); scan receipt | See §6. |

### What feels rushed or asks for commitment before value
- **Cards + digits come before anything is shown.** Step 2–3 ask for bank, type and last-4
  digits for every card before the user has seen one number. Step 3 has no Skip
  (`OnboardingView.swift:119`) and blocks Continue (`:168`).
- **The Shortcuts automation is step 4 of 8** and needs leaving the app for ~2 minutes
  (`:588`). This is the core value of the app, but it is asked for as setup, not shown as a
  payoff. The live "Waiting for your first tap" check (`:626-648`) is a good moment, but it
  only resolves if the user leaves, sets up, and pays for something.
- **Paywall shown before any data.** Pro step (`:816-858`) and the two Pro-gated buttons on
  steps 5 and 7 hit a user who has 0 purchases. The reminders button says "Turn On Reminders"
  and opens a paywall instead (`:903`, `:906`).
- **Pro copy is snarky** (`:851`). It predicts the user will fail. Could read as pressure.
- **Value shown is all text.** Welcome is 4 icon rows (`:281-286`). No preview of Home, a card
  or a chart. Sample data is the third, smallest button (`:177-183`, `.font(.subheadline)`,
  secondary colour).
- **Import is on Welcome** as a text link, but after the sheet closes the user is back on
  Welcome and still has to do the whole flow.

---

## 2. Navigation

### Tabs
- `TabView(selection:)` with the iOS 18+ `Tab(value:)` API, 4 tabs (`SortdApp.swift:169-174`).
- **The system tab bar is hidden on every tab** (`hideSystemTabBar` → `toolbarVisibility(.hidden, for: .tabBar)`,
  `SortdApp.swift:270-274`) and replaced by a custom **`FlatTabBar`** in `safeAreaInset(edge: .bottom)`
  (`:175-177`, `:230-268`). Comment: "iOS 27 always draws the system bar as floating Liquid
  Glass" (`:167-168`).
- FlatTabBar: plain `Color.card` background + top `Divider`, selected = `Color.brand`, else
  secondary (`:251`, `:263-265`). Icon 20 pt fixed, label 10 pt fixed; labels hidden at
  accessibility sizes, large-content viewer on long press (`:241-260`). Selection haptic (`:266`).

| Tab | Label | SF Symbol (selected) | Root |
|---|---|---|---|
| home | Home | `house` (`house.fill`) | `HomeView` |
| activity | Activity | `list.bullet` (no fill variant) | `ActivityView` |
| insights | Insights | `chart.bar` (`chart.bar.fill`) | `ProGate(.insights) { InsightsView }` |
| settings | Settings | `gearshape` (`gearshape.fill`) | `SettingsView` |

(`SortdApp.swift:115-135`, `:241`)

### Where "add" lives
- Home, with data: round black "+" `RoundIconButton` in the page header (`HomeView.swift:179`).
  It scrolls away with the content.
- Home, empty: nav bar shows a toolbar "+" (`HomeView.swift:51-58`) plus "Add a Purchase" in the
  empty state (`:424`).
- Activity: toolbar `.primaryAction` "+" (`ActivityView.swift:46-49`).
- **Not on Insights or Settings.** No persistent add button across tabs.
- Outside the app: Quick Add widget (`SortdWidget/SortdWidget.swift:472-484`), Spending widget
  "+" link (`:415`), Siri "Log a purchase in Sortd" (`Sortd/Intents/LogPurchaseIntent.swift:127-132`),
  and `sortd://add` → Home + add sheet (`Sortd/Services/Router.swift:39-42`).
- Note: `sortd://scan` routes to the **add sheet, not the scanner** (`Router.swift:39-42`).

### Toolbars and titles
- Home, Insights and Settings **hide the navigation bar** when they have content
  (`HomeView.swift:51`, `InsightsView.swift:38`, `SettingsView.swift:296`) and draw their own
  title (`PageTitle` / `ListPageTitle` with the 4-colour `BrandBar`, `HomeView.swift:465-493`,
  `:860-872`).
- Activity and list pages use `brandedTitle(_:)`: inline title, then `.toolbar(removing: .title)`
  (`HomeView.swift:877-884`). **No large titles anywhere**, so no large→inline collapse on scroll.
- Activity toolbar: Filter menu leading, "+" trailing (`ActivityView.swift:43-50`).
- Sheets use Cancel (xmark) / confirm (checkmark) toolbar items (`AddTransactionView.swift:136-147`,
  `PaywallView.swift:47-51`).

### Sheets vs pushes
- **Sheets:** Add Purchase (`HomeView.swift:62`, `ActivityView.swift:51`), Budget (`HomeView.swift:74`),
  Setup guide (`HomeView.swift:71-73`), Category picker (`ActivityView.swift:52-56`, medium/large
  detents `:293`), Paywall (many), Category limit (`InsightsView.swift:204`), Receipt scan
  (`AddTransactionView.swift:148`), Card editor and Import during onboarding
  (`OnboardingView.swift:66`, `:69`).
- **Pushes:** Card detail via `NavigationLink(value:)` (`HomeView.swift:59-61`, `:294`),
  Transaction detail (`HomeView.swift:395-397`, `ActivityView.swift:122`), Category detail
  (`InsightsView.swift:39-41`), Subscriptions & Bills from Home "Coming up"
  (`RecurringView.swift:236-238`), all Settings subpages (`SettingsView.swift:43-229`).
- **Tab jumps used as navigation:** "All cards" card → Activity tab (`HomeView.swift:287`),
  "Where it went › See all" → Insights tab (`:343`), over-limit line → Insights (`:203`),
  "Recent › See all" → Activity (`:384`). These switch tabs instead of pushing, and do not carry
  a filter.

### Search
- Only on Activity, as a **custom `TextField` in a capsule inside the List**
  (`ActivityView.swift:65-86`). Not `.searchable`, no search tab, no search suggestions or
  scopes. Matches merchant, category name and note (`:208-219`).

### iOS 26 API use
| API | Used? | Where |
|---|---|---|
| `Tab(value:)` | Yes | `SortdApp.swift:170-173` |
| `Tab(role: .search)` | No | — |
| `tabViewBottomAccessory` | No | — |
| `tabBarMinimizeBehavior` | No | (system tab bar hidden, so N/A) |
| `glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glass)` | No | Theme says "no shadows, gradients or glass" (`Components/Theme.swift:7`) |
| `sharedBackgroundVisibility(.hidden)` | Yes — to **remove** glass from toolbar items | `HomeView.swift:57`, `ActivityView.swift:45`, `:49`, `:289`, `AddTransactionView.swift:140` |
| `ToolbarSpacer` | No | — |
| `matchedTransitionSource` / `navigationTransition(.zoom)` | No | Card carousel → Card detail is a plain push (`HomeView.swift:294`) |
| `.searchable` | No | — |
| `scrollEdgeEffect*`, `backgroundExtensionEffect` | No | — |
| `#available(iOS 27.0, *)` | Yes, for the Wallet guide | `OnboardingView.swift:589`, `SetupGuideView.swift:62` |

---

## 3. Screens

### Home (`Sortd/Views/HomeView.swift`)
Vertical `ScrollView`, 28 pt between sections, 20 pt side padding (`:34-46`). Order:
1. **Header** (`:155-215`): month `Menu` with a `Picker` of the last 12 months (`:161-176`),
   `BrandBar`, round "+", then the **big month total** (ScaledMetric 52 pt, rounded, bold,
   `numericText` transition, `:23`, `:183-191`), then one budget line that opens the budget sheet
   ("$X left of $Y · $Z a day", subtracting bills still due, `:192-201`, `:230-241`), then an
   optional red over-limit line that jumps to Insights (`:202-213`).
2. **Demo banner** when sample data is loaded (`:37`, `:90-110`).
3. **Budget card** (`:246-272`): one `SegmentedBar` of category colours + top-3 legend. Whole card
   is a button → budget sheet.
4. **Your cards** carousel (`:278-321`): horizontal paging `ScrollView` with
   `.scrollTargetBehavior(.viewAligned)` and `.scrollPosition(id:)`; "All cards" first, then cards
   by spend. Card faces are drawn from category colours (`WalletCard`, `:519-597`;
   `SpendGradient`, `Components/CardGradient.swift:7-80`). Page dots (`:310-319`). Selection haptic
   on swipe (`:307`). The card in view **filters the Categories and Recent sections below**
   (`:141-144`, `:323-327`).
5. **Coming up** (`RecurringView.swift:225-266`): up to 3 bills due in 14 days; header pushes the
   Pro-gated Subscriptions screen.
6. **Where it went** (`HomeView.swift:331-374`): top 4 categories with icon, amount, bar, count.
   Rows are **not tappable**; only "See all" (→ Insights tab).
7. **Recent** (`:378-414`): last 10 purchases grouped by day, rows push `TransactionDetailView`.

Static vs interactive: totals, category rows, bars and legend are static. Interactive = month
menu, +, budget line/card, carousel (swipe + tap), See all links, recent rows.
Gestures: horizontal swipe on carousel only. **No swipe actions, context menus or
pull-to-refresh** on Home. Animations: `numericText` on totals (`:187`, `:559`), page-dot
width animation (`:318`), `CardPressStyle` = opacity 0.7 on press, no scale (`:599-604`).
Empty state: `ContentUnavailableView` "No Purchases Yet" with "Set Up Auto-Logging" and "Add a
Purchase" (`:416-426`). Category-level empty: "No purchases this month." (`:334-339`).

### Activity (`Sortd/Views/ActivityView.swift`)
`List(.insetGrouped)` with hidden background (`:62-154`):
- `ListPageTitle("Activity")`, custom search field (`:65-86`), horizontal category chips with
  colour dots (`:88-101`).
- "Nothing matches" block with Clear (`:103-116`).
- Day sections with a header showing the **day total** (`:117-149`).
- Rows: `TransactionRow` (`Components/Components.swift:70-149`) with a **hidden
  `NavigationLink` at opacity 0** to drop the chevron (`ActivityView.swift:120-125`).
- **Trailing swipe:** Delete (destructive, **no confirm, no undo**) and Category
  (`:128-136`). Medium impact haptic on delete (`:57`).
- Filter menu in toolbar: card picker, category picker, clear (`:176-202`). Category filter
  exists in **both** the chips and the menu.
- No context menu, no leading swipe, no month scoping (whole history in one list,
  `@Query` of everything, `:17`).
- Empty state: `ContentUnavailableView` with **no action button** (`:29-33`).
- Category picker sheet: grid, "Other purchases at this merchant will move too" (`:238-295`),
  selection haptic.

### Insights (`Sortd/Views/InsightsView.swift`) — Pro only
Whole tab wrapped in `ProGate` (`SortdApp.swift:172`); free users see `ProLockedView`
(`PaywallView.swift:294-314`): icon, title, detail, "Unlock with Sortd Pro".
For Pro:
1. `PageTitle("Insights", subtitle:)` (`:25`).
2. **`SpendChart`** (`HomeView.swift:611-856`): 1W / 1M / 3M chips, running total line, dashed
   previous period, budget `RuleMark` on 1M, **drag to scrub** (`chartXSelection`) with selection
   haptic per day (`:799`, `:831`), "$X more/less than last month by now" (`:736-742`).
   Empty: `PlaceholderBars` "Nothing spent yet" (`HomeInsights.swift:4-29`).
3. **Categories this month** (`InsightsView.swift:58-130`): rows with bar or limit progress, a
   dry one-liner from `SortdVoice.topCategory` (`:65-68`); rows push `CategoryDetailView`
   (monthly limit row + all purchases, `:142-210`).
4. **Highlights** carousel: Top Merchants, Biggest Purchases, Food (`HomeInsights.swift:33-118`).
- Always **current month** (`InsightsView.swift:11-14`) — ignores the month chosen on Home.
- Empty: `ContentUnavailableView` "No Insights Yet", no action (`:19-21`).

### Settings (`Sortd/Views/SettingsView.swift`)
One long `List`, 11 blocks (`:24-286`): Pro row → Sources (Apple Pay Auto-Logging with "Last tap
logged …") → Gmail → **Recurring (Subscriptions & Bills + reminder toggle)** → Cards (Cards,
Appearance, Card Style, Widgets) → Currency → Learning → Security (Face ID, widget amounts when
locked) → Backup (Save a Backup via `ShareLink`, Import) → Your Data (Privacy, CSV export,
Delete All with `confirmationDialog`, `:302-308`) → About. Swipe-to-delete on Learned
Categories (`:352-355`); move/delete on Cards (`CardsSettingsView.swift:34-35`). Card Style
picker with 8 finishes and selection haptic (`CardGradient.swift:303-327`).

### Add Purchase (`Sortd/Views/AddTransactionView.swift`)
`Form` in a sheet: big centred amount (auto-focused, `:157-160`, `:169-207`) + currency capsule
menu; "Scan Receipt" (Pro); **quick entry** "coffee 5.50" field in its own section (`:83-87`,
`:36-72`); merchant (auto-suggests category, `:90-99`); category row → picker sheet; card
picker + date; note. Add is disabled until amount is valid (`:141-146`, `:249-252`). Success
haptic on save (`:161`).

### Haptics (`sensoryFeedback`) — complete list
Tab change (`SortdApp.swift:266`), onboarding step (`OnboardingView.swift:80`), first tap
connected (`:648`), card carousel (`HomeView.swift:307`), chart scrub (`:831`), add saved
(`AddTransactionView.swift:161`), delete (`ActivityView.swift:57`), category picked (`:291`),
budget saved (`BudgetSheet.swift:117`), category limit saved (`CategoryLimitSheet.swift:113`),
card style (`CardGradient.swift:327`).

### Hidden gestures
Long-press on any `BrandBar` shows a joke alert (`Theme.swift:98-106`). DEBUG-only 5-tap on
Version (`SettingsView.swift:260-264`).

---

## 4. Retention hooks already present

| Hook | Status | Where |
|---|---|---|
| Home Screen widgets | 3: **Spending** (small/medium, configurable period + look), **Quick Add** (small/medium), **Bills** (small/medium) | `SortdWidget/SortdWidget.swift:385-398`, `:472-484`, `:521-534` |
| Lock Screen widget | Circular / rectangular / inline, today's spend; amounts hidden when locked unless turned on | `SortdWidget.swift:613-623`; `SettingsView.swift:191-194` |
| Widget deep links | `sortd://add, scan, budget, activity, insights, bills, import` | `Router.swift:33-57` |
| Bill reminders | 9 am the day before, local, up to 40 pending, **Pro only** | `Reminders.swift:19-42` (`guard enabled, ProStore.shared.isPro`, `:25`) |
| Category limit alerts | At 80% and 100%, once a month, **Pro only and only if reminders are on** | `Reminders.swift:47-76` |
| Siri / App Shortcuts | 6: Log Purchase, Log Wallet Tap, How much have I spent, Budget left, Upcoming bills, Last purchase | `LogPurchaseIntent.swift:125-181`, `Intents/SpendQuestionIntents.swift:62-150` |
| Apple Pay auto-log | Shortcuts Wallet automation → `LogWalletTapIntent` | `SetupGuideView.swift`, `WalletSetupGuide.swift` |
| Monthly budget | Free; Home line + daily allowance after bills | `HomeView.swift:230-241` |
| Category budgets | Pro | `InsightsView.swift:204`, `Services/CategoryBudgets.swift` |
| Gmail background sync | Runs on every app foreground only | `SortdApp.swift:205-218` |
| Milestone copy | **Written but unused**: `SortdVoice.hundredPurchases`, `SortdVoice.firstImport` | `Services/SortdVoice.swift:188-190` (no call sites) |
| Weekly summary | **None** | — |
| Streaks | **None** | — |
| Live Activities | **None** (no ActivityKit) | — |
| Control Center / Action button control | **None** (no `ControlWidget`) | — |
| TipKit / review prompt | **None** | — |
| Backup nudge | Settings row shows "You haven't saved one yet" / last saved; finish-screen tip | `SettingsView.swift:314-319`; `OnboardingView.swift:951-952` |

---

## 5. Design system

**Stance:** "Simple and neutral, colourful only where it matters… Black and grey for UI; colour
is reserved for spending categories. Flat: white cards with a hairline border, no shadows,
gradients or glass. Colour always means 'where money went'." (`Components/Theme.swift:3-8`)

### Colours (`Theme.swift`)
| Token | Light | Dark | Line |
|---|---|---|---|
| `brand` / `ink` | #16161A | #E8E8EA | `:19-25` |
| `onBrand` | white | black | `:22` |
| `page` | #F7F7FA | #121214 (elevated #1C1C1F) | `:32-37` |
| `card` | white | #1E1E21 (elevated #29292D) | `:42-47` |
| `hairline` | #EAEAF1 | white 0.22 (high-contrast variants) | `:50-55` |
| `track` | white 0.906 | white 0.22 | `:58-63` |
| `creditFill` | #16161A | white 0.30 | `:67-69` |
| `brandPalette` | #F0643D, #F5A623, #7B6BF0, #2BB07A | same | `:73-78` |
| `up` / `down` | (0.13,0.63,0.42) / (0.90,0.28,0.30) | same | `:80-81` |

14 category colours in `Models/Kinds.swift:335-355`. Asset catalog also has `AccentColor`,
used by `Timeline` (`Components/Timeline.swift:52`) and `.tint` in `SetupGuideView.swift:51`.

### Typography
Mostly system text styles (Dynamic Type): `.title2.bold` page titles, `.title3.bold` section
headers (`HomeView.swift:448`), `.body` rows, `.subheadline`/`.footnote`/`.caption` secondary.
Fixed sizes that do **not** scale: wordmark 40 heavy (`OnboardingView.swift:268`), budget entry
52/30 rounded (`:749`, `:752`), tab bar icon 20 / label 10 (`SortdApp.swift:242`, `:248`),
card badge 9 heavy (`HomeView.swift:545`), guide icon 44 (`SetupGuideView.swift:50`).
Money: `.monospacedDigit()` throughout; Home total and card totals use `.rounded` design
(`HomeView.swift:184`, `:555`), but the Insights chart total (`:732`) and Add amount
(`AddTransactionView.swift:176`) use the default design.

### Spacing / shape
No spacing or radius tokens. Literals: page padding 20 (Home/Insights) vs 24 (onboarding);
section gap 28; card padding 14–18. `Surface` default radius is 24 (`Theme.swift:113`) but most
calls pass 16. Corner radii used across `Views/`: 5, 6, 7, 9, 10, 11, 12, 14, 15, 16, 18, 20,
22, 24, 26 (15 distinct values).

### Custom vs system components
Custom: `FlatTabBar`, `PageTitle`/`ListPageTitle`/`brandedTitle`, `BrandBar`, `Surface`,
`ChipStyle`, `PrimaryPill`, `SegmentedBar`, `RoundIconButton`, `SectionHeader`, `BoldHeader`,
`CategoryIcon`, `TransactionRow`, `WalletCard`, `SpendGradient` (8 finishes), `SpendChart`,
`InsightCarousel`, `Timeline`, `FlowLayout`, `ShortcutsMock`, custom search field.
System: `TabView`/`Tab`, `NavigationStack`, `List`/`Form`, `Menu`/`Picker`, `ContentUnavailableView`,
Swift Charts, `ShareLink`, `PhotosPicker`, `fileImporter`, `confirmationDialog`,
`VNDocumentCameraViewController`.

---

## 6. Top 10 weaknesses (ranked)

1. **Onboarding asks for work before it shows anything.** Up to 10 screens
   (`OnboardingView.swift:26`). Cards and last-4 digits come before any value, the card-details
   step has no Skip and blocks Continue until every card has digits (`:119`, `:164-168`,
   `:509-520`). The one thing that makes Sortd special — the Apple Pay automation — is step 4 and
   needs leaving the app (`:586-650`). The fastest path lands on an empty Home
   (`HomeView.swift:416-426`), and sample data is the smallest, greyest button (`:177-183`).

2. **Three paywalls in first-run, before any data.** Gmail connect (`:67`), "Turn On Reminders"
   (`:903`), then the Pro step (`:143-162`, `:816-858`). Buttons don't say they're Pro. The
   notification permission is only reachable after paying (`:903-904`). Pro copy predicts the
   user will fail ("We'll wait", `:851`).

3. **A whole tab is locked for free users.** Insights is `ProGate`'d at the tab level
   (`SortdApp.swift:172`, `PaywallView.swift:317-324`). Home's "See all" and over-limit links
   send free users there (`HomeView.swift:203`, `:343`). The only chart in the app lives there
   (`InsightsView.swift:26`), so free users never see a trend line.

4. **Opts out of the iOS 26 system look.** System tab bar hidden and replaced by `FlatTabBar`
   (`SortdApp.swift:167-177`, `:230-268`); glass stripped from toolbar items
   (`sharedBackgroundVisibility(.hidden)`, e.g. `HomeView.swift:57`); Theme bans glass
   (`Theme.swift:7`). Nav bars hidden on 3 of 4 tabs (`HomeView.swift:51`,
   `InsightsView.swift:38`, `SettingsView.swift:296`). Loses tab-bar minimise, the search tab
   role, `tabViewBottomAccessory`, large-title collapse, scroll-edge effects, and Dynamic Type
   on tab labels (10 pt fixed, `SortdApp.swift:248`). Tab bar also needed a spacer hack so it
   doesn't cover the last Settings row (`SettingsView.swift:265-271`).

5. **"Add" is not always one tap away.** The Home "+" scrolls off with the header
   (`HomeView.swift:179`); the toolbar "+" only shows when Home is empty (`:51-58`); Activity has
   its own (`ActivityView.swift:46`); Insights and Settings have none. Quick entry — the fastest
   way to add — is the second section of the form, below a focused amount field
   (`AddTransactionView.swift:83-87`, `:159`). `sortd://scan` opens Add, not the scanner
   (`Router.swift:39-42`).

6. **Activity list is thin on gestures and safety.** Delete on swipe with no confirm and no undo
   (`ActivityView.swift:129-133`); no context menu or leading swipe; custom search field instead
   of `.searchable` (`:65-86`); category filter duplicated in chips and menu (`:88-101`,
   `:184-189`); hidden `NavigationLink` at opacity 0 to kill the chevron (`:120-125`); empty
   state has no action (`:29-33`); whole history in one list with no month scope (`:17`).

7. **Colour tokens collide with category colours.** `Color.down` is the exact Health colour
   (`Theme.swift:81` vs `Kinds.swift:351`); `Color.up` is the exact Groceries colour
   (`Theme.swift:80` vs `Kinds.swift:344`); `brandPalette[0]`/`[1]` are Food delivery / Eating
   out (`Theme.swift:74-75` vs `Kinds.swift:342-343`). Onboarding progress, feature icons and
   paywall icons use `brandPalette` (`OnboardingView.swift:113`, `:282-285`;
   `PaywallView.swift:82`). This breaks the stated rule "Colour always means where money went"
   (`Theme.swift:8`): over-budget red reads as "Health".

8. **Home repeats itself and mixes navigation models.** Category split appears twice (budget
   card bar `HomeView.swift:246-272` and "Where it went" `:331-374`); the budget line and budget
   card both open the same sheet (`:192`, `:253`). Category rows aren't tappable (`:345-368`).
   "All cards" switches tabs (`:287`) while other cards push (`:294`), and the jump to Activity
   drops the card/month context. No swipe/context actions on Home rows, no pull-to-refresh
   anywhere (Gmail only syncs on foreground, `SortdApp.swift:205-218`).

9. **Retention is Pro-only and thin.** All notifications need Pro (`Reminders.swift:25`, `:50`).
   No weekly summary, streak, Live Activity, Control widget, TipKit or review prompt (none in
   codebase). Milestone lines are written but never shown (`SortdVoice.swift:188-190`).
   Subscriptions & Bills — sold on Welcome (`OnboardingView.swift:284`) — lives in Settings
   (`SettingsView.swift:66-70`). Backup is manual and only nudged in Settings
   (`SettingsView.swift:201-215`) despite "No backup" being the biggest known risk.

10. **No real design tokens; small inconsistencies add up.** 15 corner radii, spacing literals,
    `Surface` default 24 but mostly overridden to 16 (`Theme.swift:113`). Fixed font sizes that
    ignore Dynamic Type (`SortdApp.swift:242`, `:248`; `HomeView.swift:545`). Money is rounded
    on Home (`HomeView.swift:184`) but default on Insights and Add (`:732`,
    `AddTransactionView.swift:176`). Insights is locked to the current month
    (`InsightsView.swift:11-14`) while Home has a 12-month picker (`HomeView.swift:12`, `:161`),
    so the two tabs can show different months side by side.

---

### Notes and uncertainty
- `SORTD_BETA` gives every TestFlight tester Pro (repo `CLAUDE.md`), so testers will not hit
  weaknesses 2, 3 and 9 as a free user would. Test free-tier flows with a non-beta build.
- Feel/timing claims (e.g. "rushed") are inferred from code structure, not from running the app.
