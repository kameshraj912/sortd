# 05 — Bottom bar and top buttons: layout options for Sortd

Researched 22 Sep 2026 (iOS 27 shipped 14 Sep). Builds on doc 04, not repeated here.
**V** = verified from a source this session. **U** = unverified (memory, or a single weak source).

## 1. How Apple's own apps are laid out

| App | Tabs (iPhone) | Search | Account / settings | Add / compose |
|---|---|---|---|---|
| App Store | Today, Games, Apps, Arcade, Search | iOS 26.0: separate circle. **iOS 26.4: moved back into the bar, search field at top** (V, 9to5Mac) | Avatar top-trailing (U) | None |
| Music | Home, New, Radio, Library + Search | Separate circle. (V, MacStories) | Avatar top-trailing (U) | None |
| Podcasts | Home, New, Library + Search | Separate circle (V) | U | None |
| TV | Home, Apple TV, MLS, Store + pinned Search (V, partial) | Separate circle (V) | U | None |
| News (26.2) | Today, News+, Following… + Search | Separate (V) | U | None |
| Photos | Library, Collections | Search in the bottom-right corner, separate (V, MacRumors) | U | None |
| Health | Summary, Sharing + Search | Separate search button at the bottom (V, Donny Wals) | **Profile picture top-trailing** on Summary (V, 9to5Mac, Apple Support) | Inside metric pages (U) |
| Fitness | Summary, Workout, Sharing (+ Fitness+) (V, Apple Support) | U | Avatar top-trailing (U) | "Start workout" is a tab, not a + |
| Phone (Unified) | Calls, Contacts, Keypad, Search (V, MacRumors/TapSmart) | Search is a tab | Menu top-trailing (V) | Keypad tab |
| Wallet | No tab bar | Top (V, HIG) | ••• top-trailing (V) | + top-trailing (U) |
| Mail | No tab bar | Bottom toolbar: filter leading, **search + compose trailing** (V, WWDC25 323) | — | Compose bottom-trailing |
| Notes / Reminders / Journal | No tab bar | Notes: bottom search (V) | — | **Prominent button at the bottom** (V, Ryan Wesley, MacRumors) |
| Files | Recents, Shared, Browse | Kept at the top (V, MacStories) | U | U |

**iOS 27:** Bloomberg (June 2026) reported that Music, TV, Podcasts, News and Health would put Search back inside the bar, like App Store/Games did in 26.4 (V that it was *reported*). **U whether it shipped in 27.0.** None of my sources said an Apple app uses `.prominent`.

**Pattern:** Apple puts the profile/account at **top-trailing** and never uses a tab for settings. Apps with a tab bar have no "add". Apps with a create action drop the tab bar and put create at the bottom-trailing.

## 2. When does the search tab become a separate circle?

- **iOS 26 (SDK 26):** any `Tab(role: .search)` is drawn detached at the trailing end. It goes through `.pinned` placement: "on the trailing edge of the tab bar" (V, Apple docs, nilcoalescing, Donny Wals). Tab count does not matter.
- **iOS 27 SDK:** the detached slot is now the **"prominent treatment"**. Apple docs (V):
  - `TabRole.prominent` (iOS 27): "Only one tab can receive the prominent treatment. When there are no tabs with an explicit .prominent role, then a .search role tab **may** receive the prominent visual treatment by default."
  - UIKit `prominentTabIdentifier` (iOS 27) is stricter. If it's nil **and** a `UISearchTab` has `automaticallyActivatesSearch = true`, only then does search get the prominent treatment.
- Evidence (V): an app rebuilt on the 27 SDK saw its `.search` tab "drawn inline with everything else". Fix: `.prominent` on 27, `.search` on 26 (Monaka PR #12, simulator-tested). Expo and react-native-screens report the same, tied to the SDK. So **apps built with the 26 SDK keep the old look on iOS 27**.
- **SwiftUI trigger on 27 (U):** `automaticallyActivatesSearch` probably maps to `.tabViewSearchActivation(.searchTabSelection)` (iOS 26). Likely setup to keep search detached:

```swift
TabView(selection: $tab) {
    Tab("Home", systemImage: "house", value: .home) { HomeView() }
    Tab("Activity", systemImage: "list.bullet", value: .activity) { ActivityView() }
    Tab("Insights", systemImage: "chart.bar", value: .insights) { InsightsView() }
    Tab(value: .search, role: .search) { NavigationStack { SearchView() } }
}
.searchable(text: $query)
.tabViewSearchActivation(.searchTabSelection)   // U: needed for detached look on 27 SDK?
```
**Test this on an iOS 27 simulator with Xcode 27, with and without the last line.**

## 3. Third-party apps

| App | Add | Search | Settings/profile | Quality |
|---|---|---|---|---|
| Things | Floating draggable Magic Plus | — | — | V (doc 04) |
| Structured (Editor's Choice) | Primary action **in the trailing search slot** | — | — | V (Ryan Wesley) |
| Craft, GitHub | Rebuilt bar / reused search slot for an action (criticised) | — | — | V |
| Foodnoms | FAB above the bar ("awkward") | — | — | V |
| Jones (journal) | **iOS 27 `.prominent` tab for "New entry"**. The tap opens the picker and the selection snaps back. Long-press opens the camera | — | — | V (PR #435) |
| Revolut / Instagram | Tab bar shrinks but keeps all icons | — | — | V (partial) |
| Copilot Money, Monzo, Flighty, Todoist, Crouton | Glass adopted. **No source for where add/search/settings sit** | | | U |

One finding (V, Jones PR): the `.prominent` tab "renders **icon-only, untinted** — no API exists for a title or tint." So Sortd's black + would become a plain glass icon.

## 4. iOS 27 additions: what's verifiable

- `TabRole.prominent`: iOS 27.0 (V). It is still a tab. Apple's UIKit example uses the id `"compose"` (V, Swiftjectivec). Sagar Unagar argues it is "not a FAB". The HIG tab-bar page does not mention prominent yet (V, fetched today).
- `tabViewBottomAccessory`: iOS 26 (V). No iOS 27 change found.
- Toolbar items *beside* the tab bar: **no API found** (U). iOS 27 toolbar additions (`topBarPinnedTrailing`, `ToolbarOverflowMenu`) are in doc 04 §C7.
- iOS 27 changed the bottom scroll-edge effect to a harder blur. Check tab-bar legibility over charts (V, designfornative).
- `.tabBarMinimizeBehavior(.onScrollDown)` restores the bar only at the scroll edge (V, Twinskaraoke PR, 26.5 and 27 RC).

## 5. Three layouts to try, ranked

**1. Prominent Add tab (iOS 27), search inside the bar.**
`[Home Activity Insights Search] (+)`. Top bar: title, with the settings avatar/gear at **top-trailing**, Apple-style.
Add at thumb reach, native, no custom FAB. Search inline matches where Apple apps are heading. The selection setter catches `.add` and opens the sheet (Jones pattern):
```swift
TabView(selection: Binding(get: { tab },
                           set: { if $0 == .add { showingAdd = true } else { tab = $0 } })) {
    …
    Tab("Add", systemImage: "plus", value: .add, role: .prominent) { Color.clear }
}
```
Costs: iOS 27 only, the + is untinted, and it bends the HIG "tabs aren't actions" rule. On iOS 26, fall back to layout 2. **U:** whether `if #available` works inside the `TabView` builder (Monaka switched the role behind `#available`).

**2. Clean top bar (lowest risk, works on 26 and 27).**
`[Home Activity Insights] (🔍)`. Top: gear/avatar **leading**, black + **trailing** (the one tinted item).
Today's layout with the buttons split so they don't crowd top-right. Matches HIG (one tinted primary action, trailing). Weak point: reach on big phones for the most frequent action. Add `.tabViewSearchActivation(.searchTabSelection)` if you want search to stay a circle on the 27 SDK (test).

**3. Floating + above the bar (doc 04's pick).**
Best reach, keeps the black +. But it's custom (you own accessibility and bar-minimise collisions). With a native slot in iOS 27, it drops to third.

**Suggested test:** build 1 and 2 behind a debug toggle. Time "open app → saved purchase" with 5 users, one-handed.

## Sources
Apple docs: TabRole.prominent, TabRole.search, prominentTabIdentifier, UISearchTab.automaticallyActivatesSearch, tabViewSearchActivation, TabPlacement.pinned; HIG Tab bars · 9to5Mac (2026-02-23 iOS 26.4; 2026-06-05 iOS 27 designs; 2026-08-06 Health) · MacRumors iOS 26 Photos guide, Phone how-to, iOS 27 roundup · MacStories iOS 26 review p.3 · ryanwesley.com/ios-26-tab-bar-beef · donnywals.com tab bars iOS 26 · nilcoalescing.com search iOS 26 · swiftwithmajid.com WWDC26 · swiftjectivec.com iOS 27 UIKit · sagarunagar.com prominent tab · github: Shakshi3104/Monaka#12, rogernolan/JonesBlog#435, Evil-Project/Twinskaraoke#133, software-mansion/react-native-screens#4671, expo/expo#50249 · designfornative.com iOS 27 · Apple forums 793249.
