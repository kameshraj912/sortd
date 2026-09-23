# 06 — Copy audit (Sortd, branch `ux-refresh`)

Date: 23 Sep 2026. Read-only. No Swift file was changed.

**What was checked:** every user-facing string in `Sortd/Views/**/*.swift` (except onboarding),
plus `Sortd/Services/SortdVoice.swift`. For each: is it needed, can it be shorter, plainer,
kinder, and does it say what the code really does.

**Skipped:** `Sortd/Views/OnboardingView.swift` and `Sortd/Views/Onboarding/` (already done),
code comments, and anything inside `#if DEBUG` (`SecretCodeSheet.swift`, the DEBUG card-style
gallery in `CardGradient.swift`, the About-page knock hints). Plain system words (OK, Cancel,
Done, Save, Delete, Close, Undo) are only listed when there is a problem with them.

**Line numbers** are from the working tree on 23 Sep 2026. Some files have other sessions'
uncommitted edits (`ActivityView`, `HomeView`, `InsightsView`, `RecurringView`, `CardsSettingsView`,
`CardDetailView`, `SearchView`, `WalletSetupGuide`, `Settings/BillsReminders…`,
`Settings/HelpFeedback…`, `Settings/LearnedRules…`), so numbers can move.

`{curly}` = a value the code fills in.

---

## Counts

| Action | All rows | SortdVoice.swift | Everything else |
|---|---|---|---|
| Cut | 59 | 31 | 28 |
| Shorten | 23 | 0 | 23 |
| Rewrite | 97 | 4 | 93 |
| Keep | 211 | 28 | 183 |
| **Total** | **390** | **63** | **327** |

Some rows group two or three short strings from the same spot (e.g. a title and its detail line).
20 of the rewrites only fix capitalisation.

---

## The 10 most important changes

1. **Delete the dead joke lines in SortdVoice, including "Either you're broke or you're lying to
   yourself."** `noPurchases`, `noInsights`, `noRecurring`, `hundredPurchases` and `firstImport`
   are not used anywhere (`SortdVoice.swift:37-57`, `:188-190`). They still ship in the app and
   one line of code would bring them back. Cut all 9.
2. **Take the joke line off Insights** (`InsightsView.swift:65-77`, lines from
   `SortdVoice.swift:91-183`). It shows when one category is 40% or more of the month. People
   open that screen when they're worried, and the row right under it already shows the same %.
   Best fix: remove it. If you keep it, cut 22 of its 47 lines and rewrite 3 (list below).
   Most of the cuts tease the person ("Your kitchen is right there", "You needed all of it,
   obviously"). The two "Transfers" lines can never show, and one is false ("It still counts".
   Transfers are left out of totals, `Components.swift:155`).
3. **Cut 14 subtitles that repeat the page title.** Insights, Recurring, About, Backup & Data,
   Bills & Reminders, Cards & Appearance, Currency, Help & Feedback, Learned Categories,
   Privacy & Security, Purchase Sources, Privacy, Import, Widgets, plus the Card Style intro.
   Also cut the section headers that repeat the page title (About › "About", Currency ›
   "Currency", Cards & Appearance › "Cards").
4. **Use one name for the subscriptions feature.** Today it's "Recurring" (page title and a
   header), "Subscriptions & Bills" (Settings row), "Subscriptions & bills" (Pro),
   "No repeat payments yet" (empty state). Use **Subscriptions & Bills** everywhere
   (`RecurringView.swift:21,76,82`, `BillsRemindersSettingsView.swift:56`).
5. **Fix the Delete All Data warning** (`BackupDataSettingsView.swift:72`). It says "Export first
   if you want a copy". But an export is a spreadsheet, and only a backup can be put back.
   It also doesn't say it disconnects Gmail and restarts setup (`DataControlsView.swift:93-112`).
   New: "Every purchase, card, budget and setting on this iPhone will be deleted, and Gmail
   disconnected. You can't undo this. Save a backup first if you want a copy."
6. **Fix the Check-in footer** (`BillsRemindersSettingsView.swift:36`). With Off picked it reads
   "No regular check-ins. A short nudge to take a look. Free." That contradicts itself.
   New: Off → "Get a short reminder to check your spending." On → just the time
   ("8 am, a look at yesterday.").
7. **Fix "Last tap" in Settings** (`SettingsView.swift:112-114`). It shows only a time
   ("Last tap 3:42 pm"). So a tap from last week looks like today. Use the relative time the
   Purchase Sources page already uses ("Last tap 2 hours ago"). Also "Not set up yet" shows
   when setup is done but nobody has tapped yet. Say "No taps yet".
8. **Fix the Paywall's free list and main button** (`PaywallView.swift:206`, `:253`).
   "Free forever: … export and delete" lists deleting as a feature. It also leaves out the
   monthly budget, statement import, widgets and backups, which are all free. And the button
   "Start 14-day free trial" should be Title Case: "Start Free Trial" (the length is already in
   the line under it).
9. **Make capitalisation consistent.** Buttons: "See all" → "See All" (`HomeView.swift:499`,
   `RecurringView.swift:239`, `CardDetailView.swift:145`). Headings: about 40 list headings already
   use Title Case, so fix the 8 that don't: "Your cards", "Where it went", "Coming up",
   "Categories this month", "Finish setup", "Last 4 digits", "Check-in", "Coloured by spending".
   Row labels: "Monthly limit", "Original name", "Totals shown in", "Purchase currency",
   "Card number", "Apple Pay number", "Paid with". Alert titles: "Not saved", "Import".
   Lowercase starts: "this month · 3 purchases", "next 7 Oct", "converting…".
10. **Use plain words.** "Merchant" (7 places) → "shop" / "Paid to". "(ECB rate)" → "the rate
    that day". "Keys in the Keychain" → "Google sign-in kept safe". "on your iPhone" → "on this
    iPhone" (`ReceiptScanView.swift:33`, `DataControlsView.swift:13,15`). "Export Purchases (CSV)"
    → "Export as Spreadsheet". Shorten the "Good to Know" legal block
    (`DataControlsView.swift:24`) from 50 words to 30.

**Bugs found while reading (on-screen text that is wrong, not just wordy):**
- `CategoryLimitSheet.swift:39` always shows "$", even for £, RM or ¥ users. `BudgetSheet.swift:43`
  already does this right with `Money.symbol(Money.home)`.
- `BudgetSheet.swift:51` tells VoiceOver "Monthly budget in Australian dollars" for everyone.
- `LearnedRulesView.swift:21` shows the internal key, for example "sevenseedscoffee"
  (lowercase, no spaces, from `MerchantName.key`, `Parsing.swift:119-121`), not the shop's name.
- `SetupGuideView.swift:31` says "On iOS 17 and 18 it's called Transaction". The app needs
  iOS 26 (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`), so this can never apply.
- `RecurringView.swift:205` can never show. Only cancelled and price-rise rows reach `alertRow`
  (`:32`). Currency rows go to `awayRow`.

---

## House rules used

- Plain English, short sentences. No jokes about money habits. "On this iPhone", never
  "on-device" (none found in scope) or "on your iPhone".
- **Title Case:** buttons, nav titles, menu items, toggles, form row labels, list section
  headings (most of the app already does this).
- **Sentence case:** body text, footers, subtitles, empty-state lines, captions.
- One name per thing. Proposed names:
  - **Subscriptions & Bills**: the page now called "Recurring".
  - **Apple Pay Logging**: the page now called "Auto-Logging". The rows that open it are
    "Apple Pay Auto-Logging" and "Apple Pay Setup Guide".
  - **shop** in body text and **Paid to** as the field name, not "merchant".
    ("Paid to" pairs with the "Paid With" section right under it.)

---

## SortdVoice.swift — every line, where it's used, and what to do

### Where each group is used

| Group | Lines | Used at | Shown when |
|---|---|---|---|
| `noPurchases` | 37-43 | **Nowhere** | Never |
| `noInsights` | 45-50 | **Nowhere** | Never |
| `noRecurring` | 52-57 | **Nowhere** | Never |
| `importFoundNothing` | 61-63 | `ImportView.swift:265` | Error alert (title "Import", `ImportView.swift:71`) when a file or screenshot has no purchases |
| `topCategory` / `categoryLines` | 76-183 | `InsightsView.swift:67`, shown at `:72-77` | Insights › "Categories this month", when the top category is ≥ 40% of this month. One line, picked by the day |
| `hundredPurchases` | 188 | **Nowhere** | Never |
| `firstImport` | 190 | **Nowhere** | Never |
| `proUnlocked` | 198-207 | `SecretCodeSheet.swift:74, 89` | DEBUG only (whole file is `#if DEBUG`) |
| `codeAlreadyUsed` | 209-217 | `SecretCodeSheet.swift:75, 90` | DEBUG only |
| `notACode` | 219-226 | `SecretCodeSheet.swift:76, 91` | DEBUG only |
| `brandMarkPress` | 231-237 | `Components/Theme.swift:99` (alert at `:101-106`) | Long-press (0.8 s) on the four-colour bar. The bar is on: `HomeView.swift:190` (month header), `:450` (empty Home), `:522` (`PageTitle`, so every page with a branded title: Activity, Insights, Recurring, Settings and all its sub-pages, Import, Widgets, Auto-Logging, Card Style, Card detail), `InsightsView.swift:160` (category detail), `TransactionDetailView.swift:109`, `PaywallView.swift:68`, `LockView.swift:59`, `Onboarding/SetupPages.swift:125` |

### Line by line

**Main advice for `topCategory`: remove it from Insights.** The row under it already shows the %
(`InsightsView.swift:113`). The verdicts below are for if you keep it. The "keep" lines talk about
the category, not the person. Any category you keep must still have at least one line, or the
screen shows an empty line.

| file:line | current text | action | proposed text |
|---|---|---|---|
| SortdVoice.swift:39 | Nothing logged. Either you're broke or you're lying to yourself. | cut | *(unused, and shames the person)* |
| SortdVoice.swift:40 | Empty. Bold move, installing a spending tracker and then not spending. | cut | *(unused)* |
| SortdVoice.swift:41 | No purchases. Give it a Friday. | cut | *(unused)* |
| SortdVoice.swift:47 | Nothing to chart. Charts need spending. You know what to do, unfortunately. | cut | *(unused)* |
| SortdVoice.swift:48 | No patterns yet. There will be. There always are. | cut | *(unused)* |
| SortdVoice.swift:54 | None found yet. They're out there. Waiting. Charging quietly. | cut | *(unused)* |
| SortdVoice.swift:55 | Nothing repeating yet. Give it a month and prepare to be disappointed. | cut | *(unused)* |
| SortdVoice.swift:62 | Sortd read the file and found no purchases in it. If it's a statement, the CSV export from your bank usually works best. | rewrite | Alert title "No Purchases Found", message: "If this is a bank statement, try your bank's CSV export." *(also covers screenshots, which aren't "files")* |
| SortdVoice.swift:95 | Eating out took {n}% of the month. Your kitchen is right there. It has always been right there. | cut | *(teases the person)* |
| SortdVoice.swift:96 | {n}% on eating out. Someone else did the washing up, at least. | cut | *("at least" is a dig)* |
| SortdVoice.swift:97 | Eating out: {n}%. A strong month for restaurants. | keep | |
| SortdVoice.swift:98 | {n}% of the month was somebody else's cooking. Worth it, probably. | cut | *("probably" doubts them)* |
| SortdVoice.swift:102 | {n}% of your month arrived at the door. You didn't even have to stand up. | cut | *(calls them lazy)* |
| SortdVoice.swift:103 | Food delivery took {n}%. The rider knows. The rider has always known. | cut | *(shame joke)* |
| SortdVoice.swift:104 | {n}% on delivery. Convenience has a price, and this is it. | cut | *(lecture)* |
| SortdVoice.swift:105 | Delivery: {n}%. Your front door is doing a lot of work. | keep | |
| SortdVoice.swift:109 | Groceries at {n}%. Annoyingly responsible of you. | cut | *(backhanded)* |
| SortdVoice.swift:110 | {n}% on groceries. The boring answer, and the right one. | cut | *("the right one" judges the rest)* |
| SortdVoice.swift:111 | Groceries took {n}%. Nothing to see here. Genuinely. | keep | |
| SortdVoice.swift:112 | {n}% on actual food from an actual shop. Look at you. | cut | *(talks down)* |
| SortdVoice.swift:116 | Shopping took {n}%. You needed all of it, obviously. | rewrite | Shopping took {n}% this month. *(sarcasm; this category needs one survivor)* |
| SortdVoice.swift:117 | {n}% on shopping. Every single item was essential. | cut | *(sarcasm at the person)* |
| SortdVoice.swift:118 | Shopping: {n}%. The parcels are a coincidence. | cut | *(sarcasm)* |
| SortdVoice.swift:119 | {n}% shopping. It was on sale, so really you saved money. | cut | *(mocks the person)* |
| SortdVoice.swift:123 | {n}% on getting places. At least you left the house. | cut | *(dig)* |
| SortdVoice.swift:124 | Transport took {n}%. Movement isn't free, it turns out. | keep | |
| SortdVoice.swift:125 | {n}% on transport. You went somewhere. That's something. | cut | *(dig)* |
| SortdVoice.swift:126 | Transport: {n}%. The city is charging you rent to move around it. | keep | |
| SortdVoice.swift:130 | Subscriptions took {n}% without asking once. Admirable, really. | keep | |
| SortdVoice.swift:131 | {n}% on subscriptions. They renewed while you slept. | keep | |
| SortdVoice.swift:132 | Subscriptions: {n}%. Quietly, monthly, forever. | keep | |
| SortdVoice.swift:133 | {n}% went to things that bill themselves. Efficient. | keep | |
| SortdVoice.swift:137 | Entertainment took {n}%. Money well spent, allegedly. | cut | *("allegedly" doubts them)* |
| SortdVoice.swift:138 | {n}% on having a good time. Hard to argue with. | keep | |
| SortdVoice.swift:139 | Entertainment: {n}%. You were entertained, so it worked. | keep | |
| SortdVoice.swift:140 | {n}% on fun. The system works. | keep | |
| SortdVoice.swift:144 | Housing at {n}%. Nothing funny about that one. | cut | *(points at the jokes; the other two are enough)* |
| SortdVoice.swift:145 | {n}% on having somewhere to live. Non-negotiable. | keep | |
| SortdVoice.swift:146 | Housing took {n}%. That's just the number. | keep | |
| SortdVoice.swift:150 | Health took {n}%. Worth every cent. | keep | |
| SortdVoice.swift:151 | {n}% on health. Good. | cut | *("Good." reads badly after a big medical bill)* |
| SortdVoice.swift:155 | Bills took {n}%. They're very consistent, bills. | keep | |
| SortdVoice.swift:156 | {n}% on bills. Nobody has ever enjoyed this number. | keep | |
| SortdVoice.swift:157 | Bills: {n}%. The least fun money you'll spend. | keep | |
| SortdVoice.swift:161 | Travel took {n}%. You'll remember this one, at least. | cut | *("at least" is a dig)* |
| SortdVoice.swift:162 | {n}% on travel. Expensive, and completely worth it. | rewrite | {n}% on travel. Hope it was a good trip. |
| SortdVoice.swift:163 | Travel: {n}%. The photos had better be good. | cut | *(dig)* |
| SortdVoice.swift:167 | Education took {n}%. An investment, genuinely this time. | cut | *("this time" knocks their other spending)* |
| SortdVoice.swift:168 | {n}% on learning things. Hard to complain about. | keep | |
| SortdVoice.swift:169 | Education: {n}%. Future you says thanks. | keep | |
| SortdVoice.swift:173 | Transfers took {n}%. Money moving sideways. | cut | *(can't show: transfers are left out of totals, `Components.swift:155`, so the row is filtered out at `InsightsView.swift:54`)* |
| SortdVoice.swift:174 | {n}% moved somewhere else. It still counts. | cut | *(can't show, and it's false: transfers don't count)* |
| SortdVoice.swift:178 | {name} took {n}% of the month. Make of that what you will. | rewrite | {name} took {n}% of the month. |
| SortdVoice.swift:179 | {n}% went to {name}. Now you know. | keep | |
| SortdVoice.swift:180 | {name}: {n}%. Filed under 'worth knowing'. | keep | |
| SortdVoice.swift:188 | 100 purchases logged. That's 100 things you'd have sworn you didn't buy. | cut | *(unused, and teases the person)* |
| SortdVoice.swift:190 | Imported. Your past is now searchable. Sorry about that. | cut | *(unused)* |
| SortdVoice.swift:200-205 | Six "Pro unlocked. …" lines | keep | DEBUG-only screen, out of scope. Wrap `proUnlocked`, `codeAlreadyUsed` and `notACode` in `#if DEBUG` so they stop shipping in the App Store build. |
| SortdVoice.swift:211-215 | Five "Already unlocked…" lines | keep | Same: DEBUG only, wrap in `#if DEBUG`. |
| SortdVoice.swift:221-224 | Four "Not a code" lines | keep | Same: DEBUG only, wrap in `#if DEBUG`. |
| SortdVoice.swift:233 | Four colours. We agonised over them. You held them down. | keep | *(hidden, no stakes, jokes at Sortd's expense)* |
| SortdVoice.swift:234 | You long-pressed a logo. On a budgeting app. On purpose. | keep | |
| SortdVoice.swift:235 | It doesn't do anything. You checked anyway. Respect. | keep | |

---

## Per-file tables

### HomeView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| HomeView.swift:110 | You're looking at sample data | keep | |
| HomeView.swift:111 | Clear it when you're ready to use your own. | rewrite | Clear it to set up Sortd with your own. *(Clear also reopens setup, `:114-116`)* |
| HomeView.swift:252 | {Category} is {amount} over its limit | keep | |
| HomeView.swift:254 | {Category} and {n} more are over their limits | keep | |
| HomeView.swift:258 | Set a monthly budget | keep | *(reads as the budget line, so sentence case is fine here)* |
| HomeView.swift:261 | {amount} over your {budget} budget | keep | |
| HomeView.swift:267 | {left} left of {budget} · {perDay} a day | keep | |
| HomeView.swift:311 | Your cards | rewrite | Your Cards *(heading case)* |
| HomeView.swift:362 | No purchases this month. / Nothing on this card this month. | keep | |
| HomeView.swift:370 | Where it went | rewrite | Where It Went *(heading case)* |
| HomeView.swift:394 | {n} purchases *(VoiceOver)* | rewrite | Use "1 purchase" when n is 1 *(it reads "1 purchases" now)* |
| HomeView.swift:449 | Welcome to Sortd | keep | |
| HomeView.swift:451 | Your purchases show up here. | keep | |
| HomeView.swift:457 | Add a purchase by hand | rewrite | Add a Purchase *(it's a button; Title Case, and matches "Add Purchase" in the toolbar)* |
| HomeView.swift:499 | See all | rewrite | See All *(button; used on every Home section)* |
| HomeView.swift:632 | Not used this month | keep | |
| HomeView.swift:676 | 3 months before | rewrite | Previous 3 months *(chart legend; "before" what isn't clear)* |
| HomeView.swift:783 | {amount} more/less than last month by now | keep | |
| HomeView.swift:829 | Budget {amount} | keep | |

### Home/FinishSetupCard.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| FinishSetupCard.swift:34 | Finish setup | rewrite | Finish Setup *(heading case)* |
| FinishSetupCard.swift:35 | {n} of {m} done | keep | |
| FinishSetupCard.swift:39 | Hide | keep | |

### HomeInsights.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| HomeInsights.swift:18 | Nothing spent yet | keep | |
| HomeInsights.swift:48 | 1 visit / {n} visits | rewrite | 1 purchase / {n} purchases *(online orders aren't visits; matches the rest of the app)* |
| HomeInsights.swift:68 | None yet | keep | |
| HomeInsights.swift:68 | {n}× · avg {amount} | rewrite | {n} times · about {amount} each |
| HomeInsights.swift:76 | Highlights | keep | |
| HomeInsights.swift:79 | Top Merchants | rewrite | Top Shops |
| HomeInsights.swift:79 | Where most of it went | cut | *(repeats the title and Home's "Where it went")* |
| HomeInsights.swift:80 | Biggest Purchases | keep | |
| HomeInsights.swift:80 | Your largest single spends | cut | *(repeats the title)* |
| HomeInsights.swift:81 | Food / Delivery vs eating out | keep | |

### InsightsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| InsightsView.swift:20-21 | No insights yet / After a few purchases, you'll see where your money goes. | keep | |
| InsightsView.swift:25 | Where your money goes, and how this month compares. | cut | *(subtitle repeats the title; the chart shows the comparison)* |
| InsightsView.swift:71 | Categories this month | rewrite | Categories This Month *(heading case)* |
| InsightsView.swift:72-77 | *(SortdVoice top-category line)* | cut | See SortdVoice section |
| InsightsView.swift:113 | {% or limit note} · {n} purchases | keep | |
| InsightsView.swift:124 | …{n} purchases *(VoiceOver)* | rewrite | Singular for 1 |
| InsightsView.swift:135 | {amount} over limit | keep | |
| InsightsView.swift:137 | {amount} left | keep | |
| InsightsView.swift:161 | this month · {n} purchases | rewrite | This month · {n} purchases |
| InsightsView.swift:171 | Monthly limit | rewrite | Monthly Limit *(row label)* |
| InsightsView.swift:179 | None | keep | |
| InsightsView.swift:190 | All Purchases | keep | |

### ActivityView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| ActivityView.swift:32 | No purchases yet | keep | |
| ActivityView.swift:33 | Purchases you log, or that come in from Apple Pay, show up here. | shorten | Your purchases will show up here. |
| ActivityView.swift:64 | Deleted {shop} | keep | |
| ActivityView.swift:112 | Merchant, category or note | rewrite | Shop, category or note |
| ActivityView.swift:151 | No purchases fit these filters. | rewrite | No purchases match these filters. |
| ActivityView.swift:151 | No results for "{search}". | keep | |
| ActivityView.swift:153 | Clear | keep | |
| ActivityView.swift:173 / :181 | Category / Change Category | keep | |
| ActivityView.swift:229 / :235 | All Cards / Clear Filters | keep | |
| ActivityView.swift:321 | Other purchases at this merchant will move too, and new ones will use this category. | rewrite | Other purchases from this shop move too. New ones will use this category. |
| ActivityView.swift:327 | Category | keep | |
| ActivityView.swift:376 | Amount missing | keep | |

### AddTransactionView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| AddTransactionView.swift:46 | lunch at nandos 18 yesterday | rewrite | Coffee 5.50 yesterday *(one example everywhere, no brand, matches the VoiceOver hint at `:61`)* |
| AddTransactionView.swift:54 | Fill | keep | |
| AddTransactionView.swift:126 | Type it the way you'd say it. Apple Intelligence fills in the rest, on this iPhone. | shorten | Type it how you'd say it. Apple Intelligence fills in the rest on this iPhone. |
| AddTransactionView.swift:127 | Type it the way you'd say it: "seven seeds coffee 5.50". | rewrite | Type it how you'd say it, then tap Fill. *(the placeholder already gives the example)* |
| AddTransactionView.swift:131 | Merchant | rewrite | Paid to |
| AddTransactionView.swift:147 | Suggested | keep | |
| AddTransactionView.swift:162 | Paid With | keep | |
| AddTransactionView.swift:170 | Optional | keep | |
| AddTransactionView.swift:176 | New Purchase | keep | |
| AddTransactionView.swift:204 | Not saved *(alert title)* | rewrite | Couldn't Save Purchase |
| AddTransactionView.swift:327 | Couldn't save this purchase. Please try again. | shorten | Please try again. *(the title now says it)* |
| AddTransactionView.swift:255 | Scan Again / Scan Receipt | keep | |
| AddTransactionView.swift:265 | Filled from your receipt — check it | rewrite | Filled in from your receipt. Check it before you add. |
| AddTransactionView.swift:300 | Scanned receipt *(saved note)* | keep | |

### TransactionDetailView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| TransactionDetailView.swift:22 | Details | keep | |
| TransactionDetailView.swift:23 | Merchant | rewrite | Paid to |
| TransactionDetailView.swift:36 | Waiting for rate | keep | |
| TransactionDetailView.swift:56 | Add a note | keep | |
| TransactionDetailView.swift:64 | Original name | rewrite | Original Name *(row label)* |
| TransactionDetailView.swift:68 | Updates | rewrite | History *(it's a list of what happened, oldest first)* |
| TransactionDetailView.swift:70 | When two sources report the same purchase, Sortd keeps one copy. | shorten | If a purchase comes in twice, Sortd keeps one. |
| TransactionDetailView.swift:74 | Delete Purchase | keep | |
| TransactionDetailView.swift:91 / :98 | Delete this purchase? / {amount} at {shop} | keep | |
| TransactionDetailView.swift:131 | Paid at {shop} | keep | |
| TransactionDetailView.swift:138 | Amount missing / Apple Pay didn't send one. Type it in above. | keep | |
| TransactionDetailView.swift:141 | Converting to {home} / Waiting for that day's exchange rate | keep | |
| TransactionDetailView.swift:145 | 1 {cur} = {rate} {home} (ECB rate) | rewrite | 1 {cur} = {rate} {home}, the rate that day *("ECB" is jargon; `FXService` uses the day's rate, or the nearest earlier one)* |
| TransactionDetailView.swift:148 | Change it above; Sortd learns for next time | rewrite | Change it above and Sortd will remember. |
| TransactionDetailView.swift:154-156 | Logged the moment you paid / Matched from your email receipt / Matched from your statement | keep | |
| TransactionDetailView.swift:157 | Confirmed by your bank feed | keep | *(can't show today: nothing creates a bank-feed purchase. Revisit if bank feeds ship)* |
| TransactionDetailView.swift:158 | You added this yourself | keep | |

### RecurringView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| RecurringView.swift:21 / :76 | Recurring *(page title)* | rewrite | Subscriptions & Bills |
| RecurringView.swift:21 | Subscriptions and bills, predicted from your payments. | cut | *(repeats the new title; `:47` already says "predicted")* |
| RecurringView.swift:35 | Needs a Look | keep | |
| RecurringView.swift:45 | Next 30 Days | keep | |
| RecurringView.swift:47 | Predicted from your past payments. Amounts are the last charge. | keep | |
| RecurringView.swift:54 / :59 | Subscriptions / Bills & Rent | keep | |
| RecurringView.swift:68 | Stopped | keep | |
| RecurringView.swift:70 | Cancelled by you, or no payment when one was due. | keep | |
| RecurringView.swift:82 | No repeat payments yet | rewrite | No subscriptions or bills yet |
| RecurringView.swift:83 | Subscriptions and bills show up here once they've charged twice. | rewrite | They show up here once they've charged a couple of times. *(2 charges for bills and subscriptions, 3 or 4 for others, `Recurring.swift:150,171`)* |
| RecurringView.swift:100 | a month on subscriptions · {amount} a year | keep | |
| RecurringView.swift:106 | Bills & rent | rewrite | Bills & Rent *(match the header at `:59`)* |
| RecurringView.swift:136 | next {date} | rewrite | Next {date} |
| RecurringView.swift:144 | Undo *(swipe, on a cancelled row)* | rewrite | Not Cancelled *("Undo" days later doesn't say what it undoes)* |
| RecurringView.swift:146 | Cancelled *(swipe)* | rewrite | Mark Cancelled *(swipe buttons are actions)* |
| RecurringView.swift:148 / :154 | Not Recurring / Not a Recurring Payment | keep | |
| RecurringView.swift:153 | I Cancelled This | keep | |
| RecurringView.swift:178 | {n} still billing in {currencies} | rewrite | {n} still charging in {currencies} *(same word as the rest of the screen)* |
| RecurringView.swift:179 | {names}. About {amount} a month. Still need them where you are now? | keep | |
| RecurringView.swift:200 | Charged {amount} on {date} after you marked it cancelled. | keep | |
| RecurringView.swift:203 | Went up from {old} to {new}. | keep | |
| RecurringView.swift:205 | Still charging in {cur} while you're using {local}. Still need it? | cut | *(can't show: only cancelled and price-rise rows reach `alertRow`, `:32`)* |
| RecurringView.swift:220 | In {n} days · {date} | keep | |
| RecurringView.swift:237 | Coming up | rewrite | Coming Up *(heading case)* |
| RecurringView.swift:239 | See all | rewrite | See All |

### SettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| SettingsView.swift:28-29 | Sortd Pro / Active. Thank you. / Gmail, receipt camera, insights and more | keep | |
| SettingsView.swift:45 | Purchase Sources | keep | |
| SettingsView.swift:112 | Not set up yet | rewrite | No taps yet *(it only means no tap has arrived)* |
| SettingsView.swift:114 | Last tap {time} | rewrite | Last tap {relative time}, e.g. "Last tap 2 hours ago" *(now shows a time with no day; use the same format as `PurchaseSourcesSettingsView.swift:44`)* |
| SettingsView.swift:50 | Bills & Reminders / Reminders on | keep | |
| SettingsView.swift:55 / :119 | Cards & Appearance / {n} cards | keep | |
| SettingsView.swift:65 | Categories | rewrite | Learned Categories *(match the page it opens, `LearnedRulesView.swift:33`)* |
| SettingsView.swift:123 | {n} learned | keep | |
| SettingsView.swift:70 | Privacy & Security / {Face ID} on / Off | keep | |
| SettingsView.swift:75 / :80 / :85 | Backup & Data / Help & Feedback / About · Version {x} | keep | |

### Settings/AboutSettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| AboutSettingsView.swift:15 | Sortd, and what's stored where. | cut | *(subtitle; the rows say it)* |
| AboutSettingsView.swift:17-19 | Purchases / Stored · On this iPhone only / Version | keep | |
| AboutSettingsView.swift:33 | About *(section header)* | cut | *(repeats the page title)* |

### Settings/BackupDataSettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| BackupDataSettingsView.swift:13 | Move your purchases, or clear them. | cut | *(subtitle)* |
| BackupDataSettingsView.swift:18 | Save a Backup | keep | |
| BackupDataSettingsView.swift:80 | You haven't saved one yet | shorten | Not saved yet |
| BackupDataSettingsView.swift:82 | Last saved {relative} | keep | |
| BackupDataSettingsView.swift:34-35 | Import / A statement, a screenshot, or a backup | keep | |
| BackupDataSettingsView.swift:43 | Backup | keep | |
| BackupDataSettingsView.swift:45 | Everything stays on this iPhone. A backup is the only way to move phones, or to get your purchases back if you lose this one. | shorten | Everything stays on this iPhone. Save a backup to move to a new phone, or in case you lose this one. |
| BackupDataSettingsView.swift:51 | Export Purchases (CSV) | rewrite | Export as Spreadsheet |
| BackupDataSettingsView.swift:55 | Delete All Data | keep | |
| BackupDataSettingsView.swift:59 | Your Data | keep | |
| BackupDataSettingsView.swift:61 | Export gives you every purchase as a spreadsheet file. Delete removes everything Sortd has stored on this iPhone. | shorten | Export saves every purchase as a CSV spreadsheet. *(the delete dialog explains delete)* |
| BackupDataSettingsView.swift:67-68 | Delete all data? / Delete Everything | keep | |
| BackupDataSettingsView.swift:72 | This removes every purchase, card, budget and setting from this iPhone. It can't be undone. Export first if you want a copy. | rewrite | Every purchase, card, budget and setting on this iPhone will be deleted, and Gmail disconnected. You can't undo this. Save a backup first if you want a copy. *(an export can't be put back; a backup can. Show the Gmail part only when an account is connected)* |

### Settings/BillsRemindersSettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| BillsRemindersSettingsView.swift:14 | Subscriptions, bills, and your check-in. | cut | *(subtitle)* |
| BillsRemindersSettingsView.swift:18 | Off | keep | |
| BillsRemindersSettingsView.swift:21 | Check-in | rewrite | Check-In *(row label)* |
| BillsRemindersSettingsView.swift:34 | Check-in *(header)* | cut | *(the row right under it says the same)* |
| BillsRemindersSettingsView.swift:36 | {detail}. A short nudge to take a look. Free. | rewrite | Off: "Get a short reminder to check your spending." On: "{detail}." e.g. "8 am, a look at yesterday." *(when Off it reads "No regular check-ins. A short nudge…")* |
| BillsRemindersSettingsView.swift:42 | Subscriptions & Bills | keep | |
| BillsRemindersSettingsView.swift:45 | Remind Me the Day Before | keep | |
| BillsRemindersSettingsView.swift:56 | Recurring *(header)* | rewrite | Bills |
| BillsRemindersSettingsView.swift:58 | A notification at 9 am the day before a subscription or bill is due. | rewrite | Part of Sortd Pro. A notification at 9 am the day before each subscription or bill. *(the toggle opens the paywall with no warning, `:48`)* |

### Settings/CardsAppearanceSettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| CardsAppearanceSettingsView.swift:11 | Your cards, how they look, and where they show up. | cut | *(subtitle)* |
| CardsAppearanceSettingsView.swift:19 / :27 / :36 | Cards / Appearance / Card Style | keep | |
| CardsAppearanceSettingsView.swift:23-25 | System / Light / Dark | keep | |
| CardsAppearanceSettingsView.swift:44-45 | Widgets / Home and Lock Screen · light or dark | keep | |
| CardsAppearanceSettingsView.swift:53 | Cards *(header)* | cut | *(repeats the first row and the page title)* |
| CardsAppearanceSettingsView.swift:55 | Cards are coloured by what you spend on them. Appearance follows your iPhone unless you pick Light or Dark. | shorten | Cards are coloured by what you spend on them. |

### Settings/CurrencySettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| CurrencySettingsView.swift:13 | What Sortd totals in, and how it converts. | cut | *(subtitle)* |
| CurrencySettingsView.swift:15 | Totals shown in | rewrite | Show Totals In |
| CurrencySettingsView.swift:27 | Purchase currency · {cur} (from your time zone) | rewrite | Local Currency · {cur}, from your time zone *(it's `LocalCurrency.current()`, set by time zone)* |
| CurrencySettingsView.swift:36 | Update Exchange Rates | keep | |
| CurrencySettingsView.swift:43 | Currency *(header)* | cut | *(repeats the page title)* |
| CurrencySettingsView.swift:45 | Purchases in other currencies are converted to {home} at that day's European Central Bank rate. | keep | |

### Settings/HelpFeedbackSettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| HelpFeedbackSettingsView.swift:9 | Get set up, get help, or tell us what's wrong. | cut | *(subtitle)* |
| HelpFeedbackSettingsView.swift:14 | Apple Pay Setup Guide | rewrite | Set Up Apple Pay Logging |
| HelpFeedbackSettingsView.swift:17 / :27 | Send Feedback / Run Setup Again | keep | |
| HelpFeedbackSettingsView.swift:30 | Get Help | keep | |
| HelpFeedbackSettingsView.swift:32 | Feedback opens Mail with your app version, iOS version and device model already filled in. Nothing else — no purchases, no account. Running setup again keeps all your purchases and cards. | shorten | Feedback opens Mail with your app version, iOS version and iPhone model. Nothing else is added. Running setup again keeps your purchases and cards. |
| HelpFeedbackSettingsView.swift:37 / :40 | Privacy Policy / Support | keep | |
| HelpFeedbackSettingsView.swift:43 | Online | rewrite | Website |

### Settings/LearnedRulesView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| LearnedRulesView.swift:12 | Learned Categories | keep | |
| LearnedRulesView.swift:12 | Categories you've set for a merchant are used next time. | rewrite | Cut the subtitle. Add a footer under the list: "Swipe left to forget one." *(nothing tells people they can delete, `:26`)* |
| LearnedRulesView.swift:14-15 | Nothing learned yet / Change a purchase's category and Sortd remembers it for that shop. | keep | |
| LearnedRulesView.swift:21 | {rule.key}, e.g. "sevenseedscoffee" | rewrite | Show the shop's name, e.g. "Seven Seeds Coffee" *(the key is lowercase with no spaces. Needs a small code change)* |

### Settings/PrivacySecuritySettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| PrivacySecuritySettingsView.swift:13 | Lock the app, and see what Sortd stores. | cut | *(subtitle)* |
| PrivacySecuritySettingsView.swift:21 | Turn on the lock for Sortd. *(Face ID prompt)* | keep | |
| PrivacySecuritySettingsView.swift:27 / :30 | Require {Face ID} / Show Amounts When Locked | keep | |
| PrivacySecuritySettingsView.swift:34 | Security | keep | |
| PrivacySecuritySettingsView.swift:36 | Sortd locks when you open it, and when you come back after more than a minute. Widgets hide amounts on the Lock Screen and in StandBy unless you turn that on. | rewrite | With the lock on, Sortd locks when you open it or come back after a minute. Widgets hide amounts on the Lock Screen and in StandBy unless Show Amounts When Locked is on. *(it read as if Sortd always locks)* |
| PrivacySecuritySettingsView.swift:43 | Privacy *(row)* | rewrite | What Sortd Stores |
| PrivacySecuritySettingsView.swift:46 | Privacy *(header)* | cut | |
| PrivacySecuritySettingsView.swift:48 | What Sortd stores, and where. | cut | *(the new row name says it)* |

### Settings/PurchaseSourcesSettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| PurchaseSourcesSettingsView.swift:11 | Where Sortd finds what you spend. | cut | *(subtitle)* |
| PurchaseSourcesSettingsView.swift:18 | Apple Pay Auto-Logging | rewrite | Apple Pay Logging |
| PurchaseSourcesSettingsView.swift:28 | Sources | rewrite | Apple Pay *(the page is already "Purchase Sources"; Gmail has its own header)* |
| PurchaseSourcesSettingsView.swift:30 | Logs in-store Apple Pay taps the moment you pay. | keep | |
| PurchaseSourcesSettingsView.swift:42 | Not set up yet | rewrite | No taps yet |
| PurchaseSourcesSettingsView.swift:44 | Last tap logged {relative} | shorten | Last tap {relative} |

### DataControlsView.swift (the Privacy page)

| file:line | current text | action | proposed text |
|---|---|---|---|
| DataControlsView.swift:11 | What Sortd stores, and where. | cut | *(subtitle)* |
| DataControlsView.swift:13 | Stored on this iPhone / Purchases, cards and settings live only in Sortd's storage on your iPhone. There's no Sortd server or account. | rewrite | Stored on this iPhone / Purchases, cards and settings are stored only on this iPhone. There's no Sortd server or account. |
| DataControlsView.swift:15 | Gmail, read on your iPhone | rewrite | Gmail, read on this iPhone |
| DataControlsView.swift:15 | Sortd searches only for receipts and bank alerts, and reads them on this iPhone. Nothing is copied to a server or shared. Disconnect any time. | shorten | Sortd only looks for receipts and bank alerts. Nothing is copied to a server or shared. Disconnect any time. |
| DataControlsView.swift:16 | Keys in the Keychain / The key that lets Sortd read your receipts is kept in the iPhone Keychain, not in the app's files. | rewrite | Google sign-in kept safe / Your Gmail sign-in is kept in the iPhone Keychain, Apple's secure storage. |
| DataControlsView.swift:18 | No bank logins / Sortd never asks for your bank username or password. | keep | |
| DataControlsView.swift:19 | Only the last 4 digits / … | keep | |
| DataControlsView.swift:20 | Daily rates come from frankfurter.dev. Only a currency code and dates are sent. | rewrite | Daily rates come from frankfurter.dev. Only currency codes and dates are sent. *(two codes go, `FXService.swift:78`)* |
| DataControlsView.swift:21 | No ads, no tracking / No advertising, no analytics, and nothing is sold or shared. | keep | *(true today: crash reporting is off, `CrashReporting.swift:17`)* |
| DataControlsView.swift:24 | Sortd helps you track your own spending. It isn't a bank and doesn't move money, and nothing in it is financial advice. Amounts come from Apple Pay, your receipts and what you type in, and converted amounts use published exchange rates, so always check your bank statement for exact figures. | shorten | Sortd isn't a bank, can't move money and doesn't give financial advice. Amounts come from Apple Pay, receipts and what you type, so check your bank statement for exact figures. |
| DataControlsView.swift:28 | Good to Know | keep | |
| DataControlsView.swift:32 / :35 | Privacy Policy / Terms of Use | keep | |

### LockView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| LockView.swift:17 | Unlock | keep | |
| LockView.swift:55 | Sortd is locked | keep | |

### PaywallView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| PaywallView.swift:69 | {Feature} is part of Sortd Pro. | keep | |
| PaywallView.swift:102 / :104 | Everything Sortd can do. / Everything Sortd can do, from {perMonth} a month on the yearly plan. | keep | |
| PaywallView.swift:126 | Loading plans… | keep | |
| PaywallView.swift:129 | Retry | rewrite | Try Again |
| PaywallView.swift:151 | Best value | keep | |
| PaywallView.swift:183 | Pay once. Yours for good. | keep | |
| PaywallView.swift:187 | Cancel any time | keep | |
| PaywallView.swift:197 | You have Sortd Pro. Thank you. | keep | |
| PaywallView.swift:206 | Free forever: Apple Pay logging, adding by hand, cards, export and delete. | rewrite | Always free: Apple Pay logging, adding by hand, your monthly budget, statement import, widgets and backups. *(none of these check Pro; "delete" isn't a feature)* |
| PaywallView.swift:219 | Plans are still loading from the App Store. | keep | |
| PaywallView.swift:235-237 | Restore Purchases / Terms / Privacy | keep | |
| PaywallView.swift:248 / :255 | Buy for {price} / Subscribe for {price} | keep | |
| PaywallView.swift:253 | Start {14-day} free trial | rewrite | Start Free Trial *(Title Case; the trial length is in the line below, `:263`)* |
| PaywallView.swift:261 | One payment of {price}. No subscription. | keep | |
| PaywallView.swift:264 | {trial}, then {price} a {period}. Renews automatically until you cancel in Settings › Apple Account › Subscriptions, at least 24 hours before it renews. | shorten | {trial}, then {price} a {period}. Renews until you cancel. Cancel at least 24 hours before it renews, in Settings › Apple Account › Subscriptions. *(Apple requires these facts, so keep all of them)* |
| PaywallView.swift:273 | Waiting for approval (for example Ask to Buy). Pro unlocks as soon as it's approved. | shorten | Waiting for approval, like Ask to Buy. Pro unlocks once it's approved. |
| PaywallView.swift:286 / :288 | No purchases found for this Apple Account. / Couldn't restore right now. Please try again. | keep | |
| PaywallView.swift:304 | Unlock with Sortd Pro | keep | |

### ImportView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| ImportView.swift:41 | A bank statement, a screenshot, or a Sortd backup. | cut | *(subtitle; the two rows say it)* |
| ImportView.swift:71 | Import *(error alert title)* | rewrite | Couldn't Import *(and "No Purchases Found" for the empty case, see SortdVoice:62)* |
| ImportView.swift:76 | Done | keep | |
| ImportView.swift:90-91 | Choose a File / A CSV or PDF statement, or a Sortd backup | keep | |
| ImportView.swift:101-102 | Choose a Screenshot / A picture of your bank app's list | keep | |
| ImportView.swift:110 | Add From | cut | *(header adds nothing)* |
| ImportView.swift:112 | Read on this iPhone. Nothing uploads, and nothing saves until you tap Add. | keep | |
| ImportView.swift:119 | Reading… | keep | |
| ImportView.swift:125 / :128 | How / Export a statement from your bank as CSV or PDF, then pick it here. A screenshot of your bank app works too. | cut | *(whole section repeats the two rows above)* |
| ImportView.swift:138 | Card not known | keep | |
| ImportView.swift:140 | Paid with | rewrite | Paid With *(row label; matches Add Purchase)* |
| ImportView.swift:143 | Which Card | cut | *(the row says "Paid With")* |
| ImportView.swift:145 | Statements don't always say which card. | keep | |
| ImportView.swift:150 | Read from a picture, so check the amounts. | shorten | Read from a picture. Check the amounts. |
| ImportView.swift:160 | No purchases found. | keep | |
| ImportView.swift:166 | Purchases ({n} of {m}) | keep | |
| ImportView.swift:181 / :183 | Money In — Not Added / Money in isn't spending, so it's left out of your totals. | keep | |
| ImportView.swift:192 / :199 | Add {n} Purchases / Start Again | keep | |
| ImportView.swift:202 | Anything Sortd already has from a tap or a receipt is matched and counted once. | shorten | Purchases Sortd already has won't be added twice. |
| ImportView.swift:234 / :236 | That's a Sortd backup, not a statement. / Restore | keep | |
| ImportView.swift:239-240 | Add What's Missing / Replace Everything | keep | |
| ImportView.swift:244 | Add keeps what's here and fills the gaps. Replace wipes it first — for a new phone. | rewrite | Add What's Missing keeps what's on this iPhone. Replace Everything clears it first. Use that on a new phone. |
| ImportView.swift:265 | *(SortdVoice.importFoundNothing)* | rewrite | See SortdVoice:62 |
| ImportView.swift:312 | {n} added. {m} matched a purchase Sortd already had. | rewrite | {n} added. {m} were already in Sortd. |

### GmailViews.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| GmailViews.swift:23 / :29 / :41 | Disconnect / Connect Gmail · Connect Another Gmail / Sync Now | keep | |
| GmailViews.swift:49 | Email Receipts | keep | |
| GmailViews.swift:51 | Finds bank alerts and receipts (food delivery, rides, app stores, online shops) in your Gmail and reads them on this iPhone. | shorten | Finds receipts and bank alerts in your Gmail and reads them on this iPhone. |
| GmailViews.swift:56 / :58 | Disconnect {email}? / Disconnect | keep | |
| GmailViews.swift:59 | Disconnect and Delete Its Purchases | shorten | Disconnect and Delete Purchases |
| GmailViews.swift:61 | Sortd stops reading this Gmail and Google cancels its access. Purchases also logged by Apple Pay are kept either way. | keep | |
| GmailViews.swift:75-76 | Not synced yet / Synced {relative} · {result} | keep | |
| GmailViews.swift:97 | Add purchases from your email | keep | |
| GmailViews.swift:99 | Sortd finds receipts and bank alerts in your Gmail — food delivery, rides, app stores, online shops — and adds them as purchases. | shorten | Sortd finds receipts and bank alerts in your Gmail and adds them as purchases. |
| GmailViews.swift:102-105 | Only receipts · Read on this iPhone · Read-only · Stop any time *(+ details)* | keep | *(checked: scope is `gmail.readonly`, `GoogleAuth.swift:15`)* |
| GmailViews.swift:115 | Google will show a warning that the app isn't verified yet while Sortd is being reviewed by Google. | rewrite | Google may say Sortd isn't verified yet. That's expected while Google reviews it. *(remove once verification clears)* |
| GmailViews.swift:162 | Connected · {summary} | keep | |
| GmailViews.swift:190 | Connecting… / Continue with Google | keep | *(Google branding rules)* |

### SetupGuideView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| SetupGuideView.swift:46 / :130 | Auto-Logging | rewrite | Apple Pay Logging |
| SetupGuideView.swift:53 | Log every Apple Pay tap automatically | keep | |
| SetupGuideView.swift:55 | A one-time, two-minute setup in the Shortcuts app. After that, every Apple Pay tap is logged, even with Sortd closed. | keep | |
| SetupGuideView.swift:28-41 | iOS 26 steps 1–7 *(titles and details)* | keep | except the next row |
| SetupGuideView.swift:31 | Scroll down to find it. On iOS 17 and 18 it's called "Transaction". | shorten | Scroll down to find it. *(app needs iOS 26)* |
| SetupGuideView.swift:63 / :67 | Steps | keep | |
| SetupGuideView.swift:96 | Open Shortcuts | keep | |
| SetupGuideView.swift:110 | Last Tap Received | keep | |
| SetupGuideView.swift:112 | Exactly what Apple Pay sent Sortd. Useful if a tap shows the wrong shop, amount or card. | shorten | What Apple Pay sent. Helps if a tap shows the wrong shop, amount or card. |
| SetupGuideView.swift:116 | Good to Know | keep | |
| SetupGuideView.swift:118 | Only tapping your phone or watch in a shop triggers this. Apple Pay in apps and online (Uber, DoorDash) comes from your email receipts instead. | rewrite | This only works when you tap your phone or watch in a shop. Apple Pay in apps and online (like Uber) comes from your email receipts. |
| SetupGuideView.swift:119 | Only tapping your phone or watch in a shop triggers this. Add Apple Pay in apps and online (Uber, DoorDash) by hand. | rewrite | This only works when you tap your phone or watch in a shop. Add Apple Pay in apps and online (like Uber) by hand. |
| SetupGuideView.swift:121 | If Apple Pay ever sends a purchase without an amount, Sortd still saves it and marks it "Add amount". | keep | |
| SetupGuideView.swift:123 | The purchase currency follows your time zone, so travel spending is converted automatically. | keep | |

### WalletSetupGuide.swift

The drawn Shortcuts screens (`:132-260`) copy Apple's own labels, so they stay as they are.
I couldn't check the iOS 27 Shortcuts screens myself.

| file:line | current text | action | proposed text |
|---|---|---|---|
| WalletSetupGuide.swift:20-29 | Steps 1–5 titles and details | keep | |
| WalletSetupGuide.swift:30 | Tap back. Done. | rewrite | Go back. You're done. |
| WalletSetupGuide.swift:31 | It saves by itself. Now pay with Apple Pay in a shop. The ▶ button only runs a test. | keep | |
| WalletSetupGuide.swift:229 | Ready. Pay with Apple Pay to log. | keep | |

### WidgetsGuideView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| WidgetsGuideView.swift:14 | Your spending on the Home and Lock Screen. | cut | *(subtitle; the Settings row already says it)* |
| WidgetsGuideView.swift:18 | What you've spent today against what a day is worth, with the month in your category colours. | rewrite | What you've spent against what you have to spend, in your category colours. *(the widget does today, week or month, `SortdWidget.swift:397`)* |
| WidgetsGuideView.swift:20 | Add a purchase, scan a receipt or open Import — one tap, without finding the app first. | shorten | Add a purchase, scan a receipt or import a statement in one tap. |
| WidgetsGuideView.swift:22 | Subscriptions and bills about to charge, with a countdown. | keep | |
| WidgetsGuideView.swift:24 | Today's total as a small dial, a line under the clock, or plain text. | keep | |
| WidgetsGuideView.swift:26 | What There Is | cut | *(first section doesn't need a header)* |
| WidgetsGuideView.swift:31 | Tap the button at the top left, then Add Widget. | rewrite | Tap Edit at the top left, then Add Widget. *(check the label on iOS 26 and 27. These steps only cover the Home Screen)* |
| WidgetsGuideView.swift:34 | Adding One | rewrite | How to Add |
| WidgetsGuideView.swift:39 / :41 | Touch and hold a widget, tap Edit Widget, then pick a Look… / The Spending widget can show any of the three… | keep | *(matches the widget's "Look" and "Show" settings)* |
| WidgetsGuideView.swift:43 | Changing It | rewrite | Options |
| WidgetsGuideView.swift:47 | Widgets read a small summary on this iPhone — today's total, what's left, the next few bills. Nothing is uploaded. | keep | |

### BudgetSheet.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| BudgetSheet.swift:22 | {start} – {end} · all cards | keep | |
| BudgetSheet.swift:29 | Monthly Budget | keep | |
| BudgetSheet.swift:51 | Monthly budget in Australian dollars *(VoiceOver)* | rewrite | Monthly budget in {home currency} *(wrong for anyone not using AUD)* |
| BudgetSheet.swift:93 / :103 | Save / Remove Budget | keep | |

### CategoryLimitSheet.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| CategoryLimitSheet.swift:24 | {Category} Limit | keep | |
| CategoryLimitSheet.swift:39 | $ | rewrite | {home currency symbol} *(always "$" now; use `Money.symbol(Money.home)` like BudgetSheet)* |
| CategoryLimitSheet.swift:54 | Each month · all cards | keep | |
| CategoryLimitSheet.swift:88 / :98 | Save / Remove Limit | keep | |

### CardsSettingsView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| CardsSettingsView.swift:39 | Cards are matched by their last 4 digits, or by their Wallet name for taps. | keep | |
| CardsSettingsView.swift:49 / :57 / :59 | Restore / Removed / Removed cards keep their past purchases. | keep | |
| CardsSettingsView.swift:68-69 | No cards yet / Add the cards you pay with. Apple Pay adds new ones by itself. | keep | *(checked: `Banks.swift:143-155` adds a card from an unknown tap)* |
| CardsSettingsView.swift:70 / :77 | Add Card | keep | |
| CardsSettingsView.swift:142 | Name, e.g. Everyday Debit | rewrite | Name, like Everyday Debit |
| CardsSettingsView.swift:143 | Bank (optional) | keep | |
| CardsSettingsView.swift:165 | The currency the card is billed in. Purchases abroad are still converted at that day's rate. | keep | |
| CardsSettingsView.swift:169 | Card number | rewrite | Card Number |
| CardsSettingsView.swift:174 | Apple Pay number | rewrite | Apple Pay Number |
| CardsSettingsView.swift:180 | Last 4 digits | rewrite | Last 4 Digits *(heading case)* |
| CardsSettingsView.swift:182 | Bank emails show the card number. Apple Pay receipts often show Wallet's own number instead — Wallet › this card › ••• › Card Details. Add both so every receipt finds this card. | shorten | Bank emails show the card number. Apple Pay receipts often show a different one (Wallet › this card › ••• › Card Details). Add both. |
| CardsSettingsView.swift:186 | e.g. Everyday Visa Debit | rewrite | Like Everyday Visa Debit |
| CardsSettingsView.swift:190 / :192 | Name in Apple Wallet / Words from this card's name in Wallet, so Apple Pay taps land here. Separate with commas. | keep | |
| CardsSettingsView.swift:195 | New Card / Edit Card | keep | |

### CardDetailView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| CardDetailView.swift:43 / :53 / :72 / :75 | Spent This Month / Top Category / 6-Month Activity / Biggest Purchase | keep | |
| CardDetailView.swift:142 | Recent | keep | |
| CardDetailView.swift:145 | See all | rewrite | See All |
| CardDetailView.swift:154-155 | No purchases yet / Pay with {card} and it shows up here. | keep | |

### SearchView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| SearchView.swift:36-37 | Nothing to search yet / Purchases you log show up here. | keep | |
| SearchView.swift:40 | Top merchants this month | rewrite | Top shops this month |
| SearchView.swift:54 | Categories | keep | |
| SearchView.swift:74-75 | No results / Nothing matches "{query}". | keep | |
| SearchView.swift:85 | {n} result(s) | keep | |
| SearchView.swift:130 | Merchant, category or note | rewrite | Shop, category or note *(also `App/SortdApp.swift:302`)* |

### ReceiptScanView.swift

| file:line | current text | action | proposed text |
|---|---|---|---|
| ReceiptScanView.swift:30 | Scan a receipt | keep | |
| ReceiptScanView.swift:33 | Sortd reads the shop, total, date and card on your iPhone. The photo isn't saved or sent. | rewrite | Sortd reads the shop, total, date and card on this iPhone. The photo isn't saved or sent. |
| ReceiptScanView.swift:40 | Reading your receipt… | keep | |
| ReceiptScanView.swift:46 / :52 | Use Camera / Choose Photo | keep | |
| ReceiptScanView.swift:102 | Couldn't open that photo. Try another one. | keep | |
| ReceiptScanView.swift:116 | Couldn't read any text. Try again in better light, or type it in. | rewrite | Couldn't read this receipt. Try again in better light, or type it in. *(also shows when text was found but no details, `:115`)* |

### Components

| file:line | current text | action | proposed text |
|---|---|---|---|
| Components.swift:100 / :123 | Add amount / Refunded | keep | |
| Components.swift:125 | converting… | rewrite | Converting… |
| CardGradient.swift:316 / :326 | Card Style | keep | |
| CardGradient.swift:317 | Coloured styles follow what you spend by category. Plain styles stay the same. | cut | *(the two group headings say it)* |
| CardGradient.swift:320 | Coloured by spending | rewrite | Coloured by Spending *(heading case)* |
| CardGradient.swift:321 / :30-37 / :348 | Plain / style names / Everyday | keep | |
| Theme.swift:101 | Sortd *(alert title for the hidden joke)* | keep | |

---

## Spotted outside scope (not in the counts)

- `Services/ProStore.swift:34`: "Subscriptions & bills" is also the big title on the locked screen
  (`PaywallView.swift:302`). Make it "Subscriptions & Bills" to match the page.
- `Models/Kinds.swift:28`: "Card not known" is the name for purchases with no card. It's fine,
  but "Unknown card" is shorter if you want it.
- `App/NavLayout.swift:43`: "Add Manually" vs "Add Purchase" / "New Purchase" elsewhere. Consider
  "Add by Hand" or "Add Purchase".
- `Services/StatementReader.swift:25-28` error messages are clear. Keep.
