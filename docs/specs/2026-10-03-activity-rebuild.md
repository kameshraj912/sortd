# Activity rebuild: bring back the list, done properly

Date: 3 Oct 2026. Author: architect. Status: **waiting for Raj** (hard gate: nothing is built until he says yes).
Worktree: `/Users/kameshraj/Developer/Sortd/.claude/worktrees/activity-rebuild` (branch `activity-rebuild`).
Git history comes from the router's message (I have no shell). Everything else I read in this worktree; the paths are at the end.

## Problem

Raj: "Rebuild Activity. I hate the current layout. The old was so much better."
The current Activity shows **one day per page**: you tap chevrons to move a day. The old Activity was **one scrolling list of every day**.
The pager came from a to-do app reference, not from a money app. No doc ever checked that it makes purchases easier to find.
Activity is where people check what they spent, so it is the screen that has to feel right. TestFlight is close.

## Part 1. What changed

### Old layout (to 24 Sep; what is left is `TransactionsScreen.list`, `ActivityView.swift:302-340`, DEBUG `SPEND_ACTIVITY_LIST=1`)

What the website and the 25 Sep baseline show (`docs/ux-research/baseline-2026-09-25/activity-default.png`):
- **Bar:** a filter button at top left (card picker and Clear Filters, `:623-643`) and the Settings gear at top right (`NavLayout.swift:72-81`).
- **Search:** a full system field, "Shop, category or note", **above** the title.
- **Title:** "Activity" with the four-colour bar, as the first List row (`ListPageTitle`, `HomeView.swift:1149`).
- **Chips:** All, then each category in use, with colour dots (`:513-525`). In the list they sit in an unnamed section, so the cell margin clips them short of the screen edge. You can see this in the baseline.
- **Tips:** the search tip sits under the chips (`:312-319`). The swipe tip points at the first row (`:305, :330`).
- **Days:** one `.insetGrouped` section per day. The header is small grey text: "Today" on the left, the day total on the right (`dayHeader`, `:583-604`). The total is `audTotal`, which leaves out transfers (`Components.swift:197`). Each day's rows sit in a white rounded card.
- **Row** (`TransactionRow`, `Components.swift:101-191`): a 36 pt category tile; the shop; "Category · Card" under it; the amount on the right with the time under it. Foreign purchases show "≈ A$…" under the amount. "Add amount" or "Needs a check" shows in orange. Refunds are struck through.
- **Actions:** tap opens the detail with a zoom. Swipe right for Category, swipe left for Delete. Long press gives a menu with a preview (`:547-576`). A delete gives 8 s of Undo; a category change asks "All N or just this one" (`:156-180`). Pull down refreshes exchange rates (`:200-206`).
- **Scrolling:** everything scrolls together. Nothing sticks except the nav bar and the tab bar (Liquid Glass, minimises on scroll down, `SpendApp.swift:311`).
- **Empty:** "No purchases yet" (`:79-86`). No matches: the system no-results view, or "Clear Filters" (`:529-545`).

### Current layout (since 25 Sep; `dayPager`, `ActivityView.swift:350-495`)

The bar, title, chips, rows, swipes, menu, undo and refresh are the same as the old list. The differences:
- **One day only.** The List shows `all[index]` and nothing else (`:367`).
- **Day header** (`pagerHeader`, `:431-495`): ‹ "Today · 1 of 14" $37.60 ›. The chevrons are 44 pt squares and they are the only way to change day. The sideways swipe was removed in PR #62 on 26 Sep (`docs/specs/2026-09-26-app-intro-v2.md:26`).
- **Search** is split by day too. A search for "uber" with matches on five days shows one day of them at a time, and you tap › to see the rest.
- **No tips.** The pager has no search tip and no swipe tip.
- **Extras:** a row slide on each day change (`:370`), a VoiceOver line for each day (`:406-412`), the haptic (`:396`), and `.defaultScrollAnchor(.top)` so the tab bar does not stay minimised after a detail pop (`:379-386`).
- **Coupled to it:** intro step 3, "Tap the arrows to move between days" (`IntroTour.swift:21-67`, `IntroOverlay.swift:194, 492`, `SpendApp.swift:426, 446`, `Router.pendingIntroDayTap`, `IntroDayHeaderKey`); the `day_stepped` event (`Analytics.swift:63`); `DayPager.swift`, `DayPagerTests`, `FullBudgetDayPagerTests`. `CardDetailView.swift:155` uses the same screen for one card's list.

### Why the pager was added (quotes)
- Spec 5, line 56: "Day pages (TeuxDeux reference): Activity as one day per page".
- `docs/ux-research/07-app-references.md:20`, TeuxDeux: "day-based paper list, swipe between days". The take-away there: "no dashboard clutter".
- Two problems were found the same day (`docs/UIPass-2026-09-25.md:32-33`): a fast swipe jumped two days, and "nothing shows there are more days". The swipe was replaced by chevrons.
- No doc gives a reason about money, finding purchases, or totals.

### What changed after 24 Sep that both layouts share (commits from the router)
- The gear became a toolbar item (`ef0e49f`). This fixed UI pass 24 Sep #6, where the gear sat on top of search's Cancel.
- Search uses the system `.searchable` (`:97-100`: the hand-built field "lost the Cancel button and scroll-to-reveal").
- 27 Sep (`4b14c66`, `c38ccf4`): search became a bar button "so the page title sits where Home's and Insights' do" (`:819-826`, `.searchToolbarBehavior(.minimize)`). **Not verified** that this shows a button, not a field, inside this tab on a device. The baseline screenshot still has the field.
- Fixed only in the pager, not in the list: full-width chips (`chipsRow`, `:502-508`, and `.listSectionMargins(.horizontal, 0)` at `:363`), and the tab-bar anchor (`:386`).
- The comment at `:845-848` is out of date: it says the pager uses the large system title, but `largeTitle` is `false` (`:580`). `HANDOVER.md:55` still says "one swipe moves one day".

### What Raj most likely misses, and what is wrong (my reading)
1. **Seeing more than one day.** The list shows about 5 rows and 3 days at rest. The pager shows only one day's rows: 2 on the demo's "Today".
2. **Search over all days at once.** The pager splits the results by day.
3. **No tapping to go back in time.** With the list you just scroll.
4. **Problems in both layouts:** the search field sat above the title, unlike Home and Insights (possibly fixed on 27 Sep, not verified). The bar, search, title and chips take about 325 pt (37% of the screen) before the first row. Each day costs about 43 pt of gap, header and card edge. The grey footnote day headers are faint. The chips are clipped in the list. At rest the floating tab bar and + sit over the last row. That is normal for glass, but **not verified** for the end of the list. BugHunt U4 found the same on Home at AX5.
5. **Unsure:** "the old" could also mean the look before 22 Sep (custom white tab bar, search inside the list under the title; `docs/ux-research/01-current-ui-audit.md:202-214`). I assume the 24 Sep list. See Open question 1.

### Rows per screen (iPhone 17 Pro, 402×874 pt)
Measured from the 25 Sep baseline (1206×2622 px at 3×): row 74–75 pt, day gap 43 pt, first row at 325 pt, tab bar top at about 791 pt. The code alone does not give the List's own row padding, so I used the screenshot.

| Layout | At rest | Scrolled (title and chips gone) |
|---|---|---|
| Old list | **5 rows, 3 days** (466 pt ÷ rows and gaps) | about 6–7 (estimate) |
| Current pager | **that day's rows only**, at most 5 (the header is about 26 pt taller); demo Today = 2 | the same: there is nothing below the day |

## Part 2. How others do it

| App | Grouping | Row | Search and filters | Day totals | Source (read 3 Oct 2026) |
|---|---|---|---|---|---|
| Apple Wallet (Apple Card) | "Latest Card Transactions", older ones by month and year, one scroll | shop and amount | "Tap the Search button at the bottom of the screen". Search by category, shop, place, date, amount | none in the list; a Monthly Activity summary instead | support.apple.com/en-us/HT209489 |
| Monzo | the feed splits by day | shop and amount | search icon on Home, with date ranges | **left out on purpose**: "We don't want to show any numbers in the feed if they don't correspond with a transaction amount" (Head of Design, 2016) | community.monzo.com/t/total-spent-per-day-3/5852 |
| Up (AU) | rolls up "consecutive transactions from the same merchant" with a count badge | shop, logo, time | not verified | not verified | up.com.au/blog/up-version-1-4-3-release-notes (2019) |
| Revolut | not verified | not verified | magnifier "in the top left hand corner"; shop, name, notes | not verified | revolut.com blog (403; search snippet only) |
| Emma | "grouped by date", newest first | not verified | magnifier "in the top left" of Feed; 8 filters (category, shop, amount, date, account) | not verified | emma-app.com/blog/new-emma-search-feature |
| YNAB | one register per account | payee, category, amount | "Tap the magnifying glass at the top of the screen"; typed filters | none | support.ynab.com, searching-transactions guide |
| Monarch | not verified | "Category and account details are now included" in the list | filters and sort by date or amount | not verified | monarch.com/blog/quicker-and-easier-transaction-review-and-more (Jun 2024) |
| Wise | one history list | not verified | "Filter" and a search bar; filter by date, card, category, currency | not verified | wise.com/help/articles/A7iMgrOPodEJHE6FfMLdo |
| Copilot Money | not verified | not verified | filter by account, category, month (search summary); "To Review" is on its Dashboard | not verified | help.copilot.money quick-start guide |
| MoneyCoach | **not verified** (no source found) | | | | |
| Apple, WWDC25 session 323 | — | — | toolbar search "at the bottom of the screen, within easy reach". It can minimise into a button. The tab bar can "minimize on scroll". Scroll edge: "a subtle blur and fade" under bars | — | developer.apple.com/videos/play/wwdc2025/323 |
| Apple HIG (search, tab bars) | — | — | "If search is important, give it a primary position"; one place to search | — | quoted in `docs/ux-research/04` (read 22 Sep). The HIG pages did not render for me today. |

**What I take from this:** every app is one scrolling list, newest first, split by date. None pages one day at a time. Search is a magnifier button (top or bottom), not a field that is always open. Filters sit with search. Day totals are optional: Monzo leaves them out on purpose, while Sortd's job is totals, so keeping them makes sense.

## Part 3. Three options

Every option keeps: search by shop, category, note and "$amount" (`SearchView.swift:163-189`), category chips, the card filter, day totals, swipe actions, tap to open, long-press preview, 8 s Undo, the "All N / Just This One" question, "Add amount" and "Needs a check" rows, pull to refresh, and the card's own list. None changes a model: no migration, no privacy-label change.

### A. "The old one, finished": the 24 Sep list, made the default
```
 (≡)                               (⚙)
 [⌕ Shop, category or note          ]
 Activity
 ▬ ▬ ▬ ▬
 (All) (• Food Delivery) (• Eating
 Today                         $37.60
 ╭──────────────────────────────────╮
 │ ▣ Uber Eats             -$31.40  │
 │   Food Delivery · Rew… 12:54 PM  │
 │ ▣ Starbucks              -$6.20  │
 ╰──────────────────────────────────╯
 Yesterday                    $100.45
 ╭ ▣ DoorDash / ▣ Woolworths ───────╮
 Wednesday, 23 September       $22.90
 ╭ ▣ Grill'd               -$22.90 ─╮
 ( Home  Activity  Insights )    (+)
```
- **Rows:** as today. **Search:** the full field above the title, as on the website. **Scroll:** everything scrolls; the field folds into the bar.
- **Fixes only:** remove the pager; full-width chips; `.defaultScrollAnchor(.top)`; rewrite intro step 3.
- **Rows per screen:** 5 at rest, about 6–7 scrolled.
- **Cost:** `ActivityView.swift` (about −200 lines); delete `DayPager.swift` and its two test files; `IntroTour.swift`, `IntroOverlay.swift`, `SpendApp.swift`, `Router.swift`, `Analytics.swift`, `IntroTourTests.swift`. Search placement: the builder takes it from the commit before `ef0e49f` (the router reads it with git). About 1 day.
- **Gives up:** the title still sits under the search field, which Raj asked to fix on 27 Sep.

### B. "Old list, today's polish": A, plus the good parts added since 24 Sep
```
 (≡)                          (⌕) (⚙)
 Activity
 ▬ ▬ ▬ ▬
 (All) (• Food Delivery) (• Eating Ou›
 Today                         $37.60
 ╭──────────────────────────────────╮
 │ ▣ Uber Eats             -$31.40  │
 │   Food Delivery · Rew… 12:54 PM  │
 │ ▣ Starbucks              -$6.20  │
 ╰──────────────────────────────────╯
 Yesterday                    $100.45
 ╭ ▣ DoorDash / ▣ Woolworths ───────╮
 Wednesday, 23 September       $22.90
 ╭ ▣ Grill'd               -$22.90 ─╮
 Tuesday, 22 September         $36.59
 ( Home  Activity  Insights )    (+)
```
- **Kept from since 24 Sep:** title first, lined up with Home and Insights (27 Sep); search as a bar button; the gear as a toolbar item; full-width chips (`:502-508`); the tab-bar anchor (`:386`); the system search with Cancel; 8 s Undo and the category question.
- **New and small:** day headers in `.subheadline`, with the day name in `.primary` and the total in `.secondary` monospaced digits, so they are not faint. "Go to Date…" at the bottom of the filter menu: pick a date and the list scrolls to that day, or to the nearest older day with purchases. It is never the default view.
- **Dropped:** chevrons, "x of n", the per-day slide and VoiceOver line, `day_stepped`.
- **Search:** if `.minimize` does not give a button here (not verified), the builder uses a toolbar magnifier bound to `.searchable(text:isPresented:)`. That is iOS 17 API, **not verified** in this tab with `brandedTitle`.
- **Rows per screen:** about 5–6 at rest (the field row is gone; estimate), about 6–7 scrolled.
- **Cost:** A's files, plus about 60 lines in `ActivityView.swift`, plus a small pure helper for "nearest day" (new `Spend/Views/ActivityDays.swift`). About 1.5 days.

### C. "Best of the web": a plain list, sticky day headers, no cards
```
 (≡)                          (⌕) (⚙)
 Activity
 ▬ ▬ ▬ ▬
 (All) (! Needs a check 2) (• Food…
 TODAY · $37.60 ─────────────── sticks
 ▣ Uber Eats                  -$31.40
   Food Delivery · Rewards   12:54 PM
 ─────────────────────────────────────
 ▣ Starbucks                   -$6.20
 YESTERDAY · $100.45 ───────── sticks
 ▣ DoorDash                   -$42.15
 ▣ Woolworths                 -$58.30
 WED 23 SEP · $22.90 ───────── sticks
 ▣ Grill'd                    -$22.90
 ( Home  Activity  Insights )    (+)
```
- **Idea:** a full-width `.plain` List, the way Wallet and the bank feeds do it. The day header pins to the top while you scroll, so you always know the day and its total. Pinned headers in `.plain` are **not verified** on iOS 26.
- **Also:** a "Needs a check · N" chip first, shown only when N > 0. It filters to `needsReview || needsCheck` (Copilot's "To Review" idea). Optional: a month row ("August · $1,240") where the month changes, as Wallet does.
- **Rows per screen:** about 6 at rest, about 7–8 scrolled (estimate: no card edges, a header about 28 pt). Not measured.
- **Cost:** B's work, plus list style, header, background, separators and the chip in `ActivityView.swift`. This changes the card's own list too. It is a new look, so it needs a full feel check and AX5 and dark passes. About 2.5 days.
- **Gives up:** the rounded day cards that match Home's Recent.

### Recommendation
**B.** It gives Raj back the list he liked, with the title-first top he asked for on 27 Sep and the fixes that only the pager got. The new parts are small and use system components. Build it first behind DEBUG `SPEND_ACTIVITY_PAGER=1` (the pager kept for one comparison build), and remove that flag after Raj's phone check. C can follow later as a look-only change if he wants plainer rows.

## Risks
- **Intro:** step 3 must change, or the tour points at chevrons that no longer exist. Check: `IntroTourTests` and a ui-driver run of the tour.
- **Search button:** `.minimize` may still show a full field in this tab. Check: ui-driver screenshot at the top of the tab. If so, use the fallback in B.
- **Long history:** one List of all purchases. `days` is regrouped on every body, as it is today. Check: scroll with 5,000 purchases (`FullBudgetDayPagerTests` sizes) on a device.
- **Tab bar:** the stuck-minimised bug (`fa06d9a`) came back once on a short list. Keep the anchor and re-test: a short filtered list, then a detail push and pop.
- **Analytics:** `day_stepped` stops. A dashboard that charts it goes flat. Not verified whether any doc lists it.
- **Data loss:** none. Delete and Undo code is unchanged (`PendingDeletes`). No model, App Review or privacy-label impact.

## Test plan
Pure logic for `test-writer` (new `ActivityDays` helper; Swift Testing; in-memory store):
- 5 purchases over 3 days → 3 groups, newest day first, newest row first in each day.
- Purchases at 23:59 and 00:01 → two groups.
- Day total = sum of `audValue`, transfers left out (same as `audTotal`).
- A SGD purchase counts by its `audValue` in the day total.
- Search "uber" with matches on 3 days → all 3 days come back together.
- Search "$31.40" → only purchases with that amount or that AUD value.
- Category filter plus search → only rows that match both.
- Card filter → only that card's rows.
- A row staged for delete is hidden; Undo puts it back in its day.
- No matches → no groups.
- Go to Date: a date with purchases → that day. A date with none → the nearest older day. A date before the oldest → the oldest. A date after today → the newest.
- `IntroStep.move` no longer says "arrows" (wording is Raj's call).

`ui-driver` (SE, Pro, Pro Max; default, AX5, dark):
- Title first; search shows as a button; the gear and the search button do not overlap.
- Chips run to the screen edge.
- Scroll to the end: the last row clears the tab bar and the +.
- Pull down: refresh works.
- Swipe both ways, long press, Undo inside 8 s, Go to Date.
- Detail push and pop on a short filtered list: the tab bar comes back full size.
- The card's own list (from Home) looks the same.
- VoiceOver reads the day header with its total.

**Device only:** scroll feel at real speed, haptics, how the tab bar minimises, and Raj's hands-on feel check.

## Open questions for Raj
1. Is "the old" the 24 Sep list (the website screenshot), or the pre-22 Sep look with the white tab bar?
2. Search: always-open field above the title (A), or a button with the title first (B and C)?
3. Rounded cards per day (A, B) or plain full-width rows with sticky day headers (C)?
4. Keep "Go to Date…" in the filter menu, or no day jumping at all?
5. Intro step 3: "Swipe a purchase to change or delete it", or drop the step?

## Sources (all read 3 Oct 2026 unless noted)
- Apple Support, Apple Card spending history: https://support.apple.com/en-us/HT209489
- WWDC25 323, Build a SwiftUI app with the new design: https://developer.apple.com/videos/play/wwdc2025/323/
- HIG Searching and Tab bars: https://developer.apple.com/design/human-interface-guidelines/search-fields (did not render; quotes from `docs/ux-research/04`, read 22 Sep)
- Monzo Community, Total Spent Per Day: https://community.monzo.com/t/total-spent-per-day-3/5852
- Up 1.4.3 release notes: https://up.com.au/blog/up-version-1-4-3-release-notes/
- Revolut, search for transactions: https://www.revolut.com/en-US/blog/post/you-can-now-search-for-your-transactions/ (403; search snippet only)
- Emma search: https://emma-app.com/blog/new-emma-search-feature
- YNAB search guide: https://support.ynab.com/en_us/searching-transactions-a-guide-r1gxyQryj.md
- Monarch, transaction review: https://www.monarch.com/blog/quicker-and-easier-transaction-review-and-more
- Wise, manage activities: https://wise.com/help/articles/A7iMgrOPodEJHE6FfMLdo/how-to-manage-your-activities (search snippet only)
- Copilot quick start: https://help.copilot.money/en/articles/11157550-quick-start-guide

**Paths read (this worktree):** `CLAUDE.md`, `HANDOVER.md`, `docs/AgentPipeline.md`, `Spend/Views/ActivityView.swift` (all), `Spend/Views/DayPager.swift`, `Spend/Views/Components/Components.swift`, `Components/Theme.swift`, `Spend/App/NavLayout.swift`, `Spend/App/SpendApp.swift:240-470`, `Spend/Views/HomeView.swift:700-760, 1140-1175`, `Spend/Views/SearchView.swift:149-190`, `docs/specs/2026-09-25-free-app-overhaul-5-motion.md`, `docs/specs/2026-09-26-app-intro-v2.md`, `docs/ux-research/01`, `04`, `05`, `07`, `docs/ux-research/baseline-2026-09-25/` (README and both Activity PNGs), `docs/UIPass-2026-09-24.md`, `docs/UIPass-2026-09-25.md`, `docs/BugHunt-2026-09-26.md`. Grep only: `IntroTour.swift`, `IntroOverlay.swift`, `Router.swift`, `Analytics.swift`, `CardDetailView.swift`, `SpendTests/DayPagerTests.swift`, `FullBudgetDayPagerTests.swift`, `IntroTourTests.swift`.
