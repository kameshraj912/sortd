# 03 — Retention research: keeping people using Sortd after setup

Date: 2026-09-22
Question: How do we keep people using Sortd every day/week after setup, with the least friction?
Scope: on-device iPhone spending tracker. Apple Pay taps logged by a Shortcuts Wallet automation, Gmail and camera receipts, multi-currency, budgets, subscriptions, widgets, Siri intents. No server, no bank login.

How to read this: every claim has a source number `[n]` (list at the end). Where I only saw a search snippet, a title, or a third-party summary, I say so. I did not invent numbers. Effort sizes are my own estimates, not sourced.

---

## 1. TL;DR

- Sortd's big advantage is that the most common spend (an Apple Pay tap) logs itself [21]. So the daily habit is not "log a purchase". It is "glance and confirm". Design the loop around a 2-second confirm, not around data entry.
- The strongest evidence in this pack is about **making the behaviour smaller**, not about motivating people. Fogg: ability beats motivation [4]. Duolingo: making a streak count for one lesson instead of a full daily goal lifted D14 retention by 3.3% and grew the share of learners on a streak [3]. For Sortd: "one tap to confirm one purchase" is the unit.
- Glanceable surfaces (widgets, Lock Screen, Watch) are the external trigger that does not annoy. Notifications are expensive: survey data suggests many people turn them off at 2–5 a week [18], and Duolingo found the same reminder copy wears out and must rotate [19].
- Money is emotionally loaded. People look away from their finances when news is bad (the "ostrich effect") [23]. Tone must make looking feel safe. Shaming copy has caused a real complaint to the UK Financial Ombudsman about Monzo's year recap [15].
- Finance app retention benchmarks disagree a lot (D30 anywhere from ~2% to ~12% depending on source and year). Treat them as rough context only (section 3).

**Top 5 for v1** (detail in section 8):
1. Instant "logged — tap to fix category" after each Apple Pay tap
2. "To review" inbox with swipe-to-categorise and undo
3. Interactive Home + Lock Screen widget: "left to spend" + quick add
4. Weekly recap (one notification, Sunday evening, kind tone)
5. First-week activation path: setup → first auto-logged tap (aha) → 4 of 14 days (habit)

---

## 2. Frameworks

### 2.1 Hook model (Nir Eyal)
Four steps: **Trigger → Action → Variable reward → Investment** [1][2]. Investment is effort or data the user puts in that makes the next loop more likely (e.g. rules, categories, budgets) [2].

Sortd mapping:
| Hook step | Sortd version |
|---|---|
| External trigger | Apple Pay tap → automation → "Logged $6.50 at Seven Seas · Food?" |
| Internal trigger (goal) | "Am I OK this week?" — the feeling of uncertainty after spending |
| Action | One tap to confirm or change category; glance at widget |
| Variable reward | What the week looks like now ("$42 left, better than last week"); recap surprises (top merchant, biggest drop) |
| Investment | Category rules learnt from corrections, budgets, subscription list, trip currency. Each correction makes the next auto-guess better (Copilot does the same after 30 reviews [7]) |

Caution: critics argue the Hook model builds compulsion rather than healthy habit [2 — Yu-kai Chou piece in the search results, seen as title/snippet only]. For a money app the goal is a short, calm check-in, not time-in-app.

### 2.2 Fogg Behavior Model and Tiny Habits
**B = MAP**: a behaviour happens when Motivation, Ability and a Prompt meet at the same moment. Raising ability (making it easier) is usually more reliable than raising motivation [4][5]. Tiny Habits recipe: "After [anchor], I will [tiny behaviour], then [celebrate]" [5].

Sortd recipe: *After I tap my phone to pay, I will tap one category, then see a small tick and haptic.* The anchor (paying) already exists and the prompt fires itself. This is unusually lucky for a finance app.

### 2.3 Duolingo streaks (primary sources)
- Changing the streak rule from "hit your daily XP goal" to "do one lesson" gave **+3.3% Day-14 retention, +1% daily active learners**, and the share of daily learners on a streak rose 10.5% (19% among new learners). A year later just over half of daily learners had a 7+ day streak, up from about a third [3].
- Users with higher daily goals were *less* likely to keep streaks — lower bars won [3].
- From the Lenny's podcast write-up with Jackson Shuttleworth (Group PM, retention): simplicity; copy change "continue" → "commit to my goal" raised retention; letting users choose their commitment raised retention; "retention is most fragile in the first seven days"; streaks amplify a good product but cannot rescue a weak one; 600+ streak experiments [6]. Streak Freeze exists so one missed day doesn't end the habit [6 — search summary].
- Widget: a widely repeated claim says Duolingo's iOS streak widget raised "user commitment by 60%" [search summary of secondary blogs]. **I could not find a primary Duolingo source for this number. Do not quote it.**
- Notifications: Duolingo's KDD 2020 paper shows reminder templates lose impact when repeated (novelty wears off) and recover when rested. Rotating templates with a "recovering" bandit gave **+0.5% DAU and +2% new-user retention** over a strong baseline [19] (read from the PDF).

Lesson for Sortd: a *daily* streak is the wrong unit for spending (you don't spend every day, and a no-spend day is good). Use a **weekly** check-in streak with a built-in freeze.

### 2.4 Activation: setup, aha, habit
Reforge-style framework: **Setup moment** (must-do steps), **Aha moment** (first time the core value is felt), **Habit moment** (core action repeated in an early window). Pinterest example: pick 5 topics on day 1 → pin in first 7 days → pin on 4 of first 28 days. Retention metric = frequency × core behaviour × who; match the product's *natural frequency* [9][10].

Proposed Sortd definitions (to validate with our own data):
- **Setup:** Wallet automation installed and one card selected (+ optional Gmail).
- **Aha:** first real Apple Pay tap appears in Sortd within seconds, correctly categorised or fixed with one tap.
- **Habit:** user confirms/reviews on ≥4 distinct days in first 14 days, *or* opens the weekly recap in 2 of the first 3 weeks.

### 2.5 Expense tracking and awareness (why the confirm step matters)
Zhang (Consumer Interests Annual, 2023): using real user data from a manual-entry finance app, expense tracking was associated with a lower share of discretionary spending, more budget slack, and budget adjustments; a US survey showed financial self-awareness mediates tracking → saving, and self-awareness can induce the "pain of paying" [22] (read from the PDF abstract). Chris Raroque's Luna budgeting app is deliberately "completely manual (for your own good)" with a great UX so manual doesn't hurt [13].

Implication: full automation can remove the moment of awareness. Sortd's one-tap confirm is a feature, not a chore — keep one tiny conscious step per purchase. (Several blogs claim "manual trackers spend 15–20% less" citing NBER; I could not trace this to a real paper. Not used.)

### 2.6 The ostrich effect
Karlsson, Loewenstein and Seppi found investors check accounts more when markets rise and less when they fall [23 — search summaries; CEPR page returned 403]. People avoid money info when it's likely bad. So: over-budget states must not feel like punishment, or users will stop opening the app exactly when it's useful.

---

## 3. Retention benchmarks for finance apps (with caveats)

| Source | D1 | D7 | D30 | Notes |
|---|---|---|---|---|
| UXCam 2026 (fintech, median) [11] | 28% | 12% | 7% | Says it uses AppsFlyer 2025, Adjust 2026, data.ai 2026, AppsFlyer as primary |
| UXCam 2026 (fintech, 75th percentile) [11] | 35–45% | 18–25% | 10–15% | Same |
| Plotline (fintech incl. banking) [12] | 30.3% | — | 11.6% | No source or year given; banking pulls it up |
| Adjust Mobile App Trends 2026 (finance) | — | — | 2% | **Only via a third-party search summary**; Adjust page blocked (429). Unverified |
| Business of Apps 2026 (finance) | — | — | 4.2% | **Search snippet only**; page returned 403. Unverified |

Take-aways:
- Numbers vary 2–12% at D30 depending on who counts what. Banking apps (where your salary lands) retain better than single-purpose tools [search summary of [11]/getstream]. Sortd is a single-purpose tool, so the lower end is the honest comparison.
- Don't chase a benchmark. Track our own D1/D7/D30 and, more usefully, the **habit rate** (section 2.4).
- App Store Connect App Analytics shows retention for users who opted in to share with developers — I believe this is still offered but did not re-check it in this session. It is the only retention view we get without a server.

---

## 4. What other finance apps do

| App | Retention mechanic | Source |
|---|---|---|
| **Copilot Money** | "To Review" section on the dashboard; new transactions since last open, grouped by day; "Mark as Reviewed". After 30 reviews it suggests type and category. Name Rules auto-categorise. Month in Review and Year in Review (shareable slides; a special app icon after year one). | [7][8] |
| **Monarch** | AI Weekly Recap: spending and drivers, cash flow, subscription changes, net worth shifts; removable widget; AI can be turned off. | [search summary of Monarch help/reviews, 2026] |
| **YNAB** | Method first: "give every dollar a job", "embrace true expenses", "roll with the punches", "age your money". Retention comes from a ritual (assign money when income lands) plus heavy education/community. | [search summary: ynab.com guides] |
| **Cleo** | Chat UI with a personality. Opt-in **Roast mode** and **Hype mode** (praise when on track). Roast was reportedly built because users kept asking. Reported 7M+ users. | [search summary; Cleo blog 403] |
| **Rocket Money** | Subscription detection, renewal and upcoming-charge alerts, category limits with alerts when approaching. | [search summary: rocketmoney.com] |
| **Emma** | Weekly reports, pay-cycle budgets with a daily limit, daily balance notifications. | [search summary: emma-app.com] |
| **Up (AU)** | Weekly Spend push with personal comparison to past weeks; merchant name + logo + exact time on every transaction; view balance without full login (privacy vs security split); celebration screens ("Up Yeah!"); gesture-based Pull-to-Save reportedly drove $1M+ in spontaneous saves in 18 months. | [14] + search summary |
| **Revolut** | Weekly spending summary push (search result says on paid plans — unverified). | [search summary] |
| **Luna** (Chris Raroque) | Manual by design; Lock Screen widget that opens straight to "log a transaction" — "the fastest way to log"; weekly/monthly Home widgets; reminder notifications. | [13] |
| **Monzo** | Year in Monzo: 2,000+ copy lines, 150 merchant quips, **opt-in "nice" vs "savage" tone** so harsh humour is consented. A customer still took a complaint about shaming language to the Financial Ombudsman. | [15][search summary] |

Patterns worth copying:
1. **A queue with an end** ("3 to review") — finishable, satisfying, Copilot's core loop.
2. **Weekly summary with a comparison to your own past** (Up, Monarch, Emma).
3. **Opt-in personality** — never default to roasting.
4. **Recap stories** — Spotify Wrapped works through curiosity gap, anticipation, variable reward, storytelling, delight, social sharing [16]. Money data is more sensitive than music, so keep it private-by-default and kind.

---

## 5. iOS surfaces (what each is good for)

| Surface | Best use for Sortd | Constraints | Source |
|---|---|---|---|
| **Interactive widgets** (iOS 17+) | "Left this week" + buttons that run an App Intent (confirm last tap, quick-add) without opening the app | Button/Toggle only, via App Intents | [17] |
| **Lock Screen widgets** | Circular/rectangular "left today"; tap → quick-add sheet (Luna pattern) | Small, monochrome-ish | [13][17] |
| **Control Center / Lock Screen controls, Action button** (iOS 18+) | "Log cash expense" button; "Scan receipt" button | ControlWidgetButton / Toggle; actions run through App Intents | [20] |
| **App Intents / Siri / Shortcuts** | "Log 12 dollars lunch", "How much on food this week?"; the Apple Pay automation itself calls our intent | Entities can be indexed in Spotlight; Apple Intelligence uses assistant schemas / domains | [21][24] |
| **Live Activities** | Only for bounded events under 8 hours (e.g. "Night out: $80 budget") | Apple: tasks with a clear start and end; don't run longer than 8 hours; end immediately when done | [25] |
| **Notifications** | Weekly recap, budget threshold crossed, subscription renews soon | Levels: passive (silent), active, time-sensitive (breaks Focus; users get prompted to keep/turn off), critical (entitlement). Relevance score orders the summary | [26] |
| **StandBy** | Free if we ship a systemSmall widget; full-colour mode | Only systemSmall on iPhone StandBy | [27] |
| **Apple Watch** | Smart Stack widget "left today"; accessoryRectangular doubles as complication | Smart Stack orders by relevance; different update budgets | [28] |

Notes:
- The Wallet "Transaction" trigger (iOS 17+) fires on contactless taps and passes amount, merchant and card to the shortcut [21]. Apple forums show timeout issues with this trigger [21 — forum thread titles only], so our intent must return fast and do heavy work later.
- Notification level guidance: use **passive** for "logged" confirmations (they pile up quietly), **active** for weekly recap and budget crossings, **time-sensitive** almost never. Apple frames time-sensitive as "requiring immediate attention" [26].

---

## 6. Friction: the 3-second rule

| Pattern | Why | Source |
|---|---|---|
| Log in under 3 s | Fogg: ability is the lever [4]. Luna and Up both put the fast path on the Lock Screen / without login [13][14] | [4][13][14] |
| Smart default category | "70 to 90% of users in most products never change the default values" (uxpeak video transcript) — so the guess must be good, and correction must be one tap | [29] |
| Swipe to categorise / mark reviewed | Copilot's review queue [7]; swipes are one gesture, no modal | [7] |
| **Undo, not "Are you sure?"** | NN/g: confirmation dialogs cause habituation ("cry wolf"); keep them for irreversible or big actions; undo lets people move fast safely | [30] |
| Haptics | Apple HIG: use consistently, don't overuse, pair with visual feedback, use system success/warning/error patterns. (HIG page may not have fully rendered for me; this is the fetched summary.) | [31] |
| Progress shown early | Goal-gradient: start onboarding progress above zero (uxpeak transcript) | [29] |

---

## 7. Creator advice ("addictive apps")

- **uxpeak — "The UX Psychology Behind Apps People Can't Stop Using"** (YouTube). I read a third-party transcript/summary, not the video. Six ideas: smart defaults, goal-gradient (show early progress), reciprocity (give value before asking), IKEA effect (let users build something before sign-up — Duolingo lessons before account), loss aversion framing, contrast effect in pricing [29]. Useful for Sortd: defaults, early progress, value before permissions. Loss aversion and contrast pricing are the ones that tip into manipulation — use carefully.
- **Chris Raroque** — I only saw his channel, the "Building Luna" playlist title, "How I Design Apps 10x Better" title, and the Luna product/guide pages [13]. I did not watch or read transcripts, so I can't summarise his spoken advice. What his product shows: manual-on-purpose, lock-screen quick-log, reminders, beautiful interactions to make the manual step enjoyable.
- **Growth.Design** (Spotify Wrapped case study) — six principles above [16].

---

## 8. Ranked retention features for Sortd

Effort: S = under ~3 days, M = 1–2 weeks, L = 3+ weeks (solo SwiftUI dev estimate).
All measurement is on-device: a small local `EngagementEvent` table (SwiftData) with type + timestamp, never uploaded. Show aggregates in a hidden debug screen; optionally let beta users export a CSV on request. App Store Connect retention covers the rest.

### ★ 1. Instant "Logged" confirm with one-tap category  — **v1**
- **What:** When the Wallet automation fires, our App Intent saves the spend with a guessed category and posts a **passive** local notification with 3–4 category action buttons + "Other…". Tapping one fixes it without opening the app. Rules learn from fixes.
- **Why:** Anchors to an existing behaviour (paying) — Tiny Habits [5]; ability beats motivation [4]; investment step of Hook [2]; keeps a moment of awareness that tracking research links to lower discretionary spend [22].
- **Effort:** M (App Intent already exists; add `UNNotificationCategory` actions, rule learner, make intent return fast to avoid Shortcut timeouts).
- **Measure:** % of auto-logged taps confirmed within 1 h; % where guess was right (no change); median seconds tap→confirm.

### ★ 2. "To review" inbox, swipe to categorise, undo  — **v1**
- **What:** Home tab top card: "4 to review". Swipe right = accept guess, swipe left = pick category. Toast with **Undo** instead of any confirm dialog. Empty state = small celebration.
- **Why:** Copilot's core loop [7]; finishable queue; NN/g undo > confirm [30]; celebration step of Tiny Habits [5].
- **Effort:** M.
- **Measure:** queue length at open; days with inbox-zero; median review session length (target < 20 s); undo rate (high = guesses or gestures are wrong).

### ★ 3. Interactive Home + Lock Screen widget ("left to spend" + quick add)  — **v1**
- **What:** Small/medium Home widget: "$84 left this week" + last unconfirmed tap with ✓ button (App Intent). Lock Screen rectangular/circular: amount left; tap → quick-add sheet. Same systemSmall gives StandBy for free [27].
- **Why:** A glanceable trigger that costs nothing and doesn't nag; Luna calls the lock-screen widget "the fastest way to log" [13]; interactive widgets run App Intents in place [17]. (Duolingo "+60%" widget stat is unverified — don't cite.)
- **Effort:** M (widget exists in `SortdWidget/`; add AppIntent buttons and timeline reloads on new spend).
- **Measure:** widget installed (`WidgetCenter.getCurrentConfigurations`), actions from widget per week, opens with widget as source (deep-link tag).

### ★ 4. Weekly recap (one notification a week)  — **v1**
- **What:** Sunday ~6 pm local: "Your week: $312, $40 under plan. Tap for 4 cards." Cards: total vs your last 4 weeks, top category, biggest single spend, one subscription note. Kind default tone. Ends with one question ("Move $40 to next week?").
- **Why:** Up, Monarch, Emma, Revolut all do a weekly spend summary [14][search summaries]; Wrapped principles of curiosity + variable reward + story [16]; matches natural frequency for a budget check [9]; one push a week stays under the level where surveys show people switch notifications off [18].
- **Effort:** M.
- **Measure:** recap open rate from notification; % who finish all cards; next-7-day active days for openers vs non-openers.

### ★ 5. First-week activation path  — **v1**
- **What:** Onboarding checklist that starts partly filled (goal gradient): ✓ Sortd installed → Add Wallet automation (guided, with a "test tap" screen) → Set one weekly budget → Add widget. Day-1 goal = first real tap shows up (aha). Days 2–7: at most 2 gentle nudges if no tap logged, then stop.
- **Why:** Retention is most fragile in the first 7 days [6]; setup/aha/habit framework [9][10]; goal-gradient and smart defaults [29].
- **Effort:** S–M (much of setup UI exists; add checklist state + test screen).
- **Measure:** % reaching setup, aha within 24 h, habit (4 of first 14 days). This is the single most important funnel.

### 6. Weekly check-in streak with built-in freeze
- **What:** "5 weeks checked in" (review inbox or open recap once per week). One free skip per month. No daily streak — a no-spend day must never break anything.
- **Why:** Duolingo: lower the bar, simplify, add freezes [3][6]; ostrich effect → no punishment [23].
- **Effort:** S.
- **Measure:** weekly active weeks; streak length distribution; churn after a streak break.

### 7. Budget pace nudges with a notification budget
- **What:** Only on threshold crossings (e.g. 80% and 100% of a category) and only if pace is off. Hard cap: 3 Sortd pushes a week total, excluding passive "logged" ones. Rotate copy from a pool; rest a line before reusing.
- **Why:** Rocket Money limit alerts [search summary]; Duolingo shows repeated copy wears out and rotating helps [19]; survey data on disable thresholds [18]; Apple levels [26].
- **Effort:** S–M.
- **Measure:** push → open rate; % users who turn off each notification type (read `UNUserNotificationCenter` settings on launch); budget kept after nudge.

### 8. Subscription renewal heads-up
- **What:** "Netflix renews in 2 days — $22.99. Keep / Remind me to cancel." Active level, not time-sensitive.
- **Why:** Rocket Money's core value [search summary]; clear, useful, not marketing.
- **Effort:** S (subscriptions already modelled).
- **Measure:** opens; "remind me to cancel" taps; subscriptions marked cancelled.

### 9. Control Center / Action button "Log cash" + "Scan receipt"
- **What:** Two `ControlWidgetButton`s: quick-add sheet, camera receipt scan.
- **Why:** Covers non-Apple-Pay spend (cash, card swipe) in one press; controls run App Intents from Control Center, Lock Screen, Action button [20].
- **Effort:** S.
- **Measure:** logs by source (control / widget / app / automation / Gmail / camera).

### 10. Siri and Spotlight: ask and log by voice
- **What:** App Intents: "Log [amount] [note]", "How much did I spend on [category] this week?", "What's left?"; expose transactions/categories as indexed entities. Later: Apple Intelligence assistant schemas.
- **Why:** Lower ability cost in hands-busy moments [4]; App Intents + entity indexing is Apple's path to Siri/Apple Intelligence [24].
- **Effort:** M (basic intents exist); L for schema/Apple Intelligence work.
- **Measure:** intent invocations by type (log in `perform()`).

### 11. Celebrations and haptics, small and honest
- **What:** Success haptic + tick on confirm; confetti-lite on inbox zero and on finishing a week under plan. Never celebrate spending.
- **Why:** Tiny Habits "celebrate" step [5]; Up's brand moments [14]; HIG: use haptics consistently and sparingly [31].
- **Effort:** S.
- **Measure:** indirect — review session completion; A/B via local flag if needed.

### 12. Monthly review + Year in Sortd (private, opt-in tone)
- **What:** Month-end story cards; year-end recap. Tone switch: "kind" (default) or "honest/savage" (opt-in, Monzo-style). Share = image with amounts hidden by default.
- **Why:** Copilot Month/Year in Review [8]; Wrapped psychology [16]; Monzo's opt-in tone and the ombudsman complaint as the warning [15].
- **Effort:** L (copy volume is the real cost — Monzo wrote 2,000+ lines [15]).
- **Measure:** view rate; share rate; tone chosen.

### 13. Apple Watch Smart Stack widget
- **What:** `accessoryRectangular` "left today / last tap ✓". Works as complication too.
- **Why:** Glanceable, relevance-ranked [28]; the Watch is where Apple Pay taps often happen.
- **Effort:** M (watch target needed).
- **Measure:** widget-driven actions (via intent logging).

### 14. Trip mode Live Activity (bounded)
- **What:** For a day out or travel day: "Tokyo day 3 · ¥8,200 left · last: ¥1,100 Lawson". Auto-ends at 8 h or when user stops.
- **Why:** Live Activities are for events with a clear start/end, max 8 h [25]; multi-currency is a Sortd strength.
- **Effort:** M (ActivityKit, local updates from the intent).
- **Measure:** starts, completion, spends logged during an activity.

### 15. Opt-in personality (Hype / Honest)
- **What:** Setting for copy tone across nudges and recap. Default neutral-kind. No chatbot in v1.
- **Why:** Cleo's Roast/Hype modes are popular but opt-in [search summaries]; Monzo shows consented tone matters [15].
- **Effort:** S once copy system exists (copy writing is the real work).
- **Measure:** % choosing each tone; notification disable rate per tone.

---

## 9. Ethics and App Review

Do:
- Treat money data as private by default. No server is a trust story — say it in the recap and widgets settings.
- Default kind, factual tone. Make harsh humour opt-in [15].
- Keep one clear off switch per notification type in-app, plus respect system settings.
- Ask for notification permission *after* the aha (first tap logged), with a plain reason. Ask once; don't re-nag.

Don't (dark patterns — NN/g and deceptive.design) [32][33]:
- Confirmshaming ("No thanks, I like wasting money").
- Nagging for permissions, reviews or upgrades after a "no".
- Fake urgency or time-sensitive level for non-urgent things.
- Streak-loss fear as the main hook; guilt copy when over budget (ostrich effect makes it backfire [23]).
- Roach-motel subscriptions (hard to cancel).

What App Review rejects (from the App Review Guidelines) [34]:
- **4.5.4** Push notifications must not be used for promotions or direct marketing unless the user explicitly opted in via consent language in the UI, with a way to opt out.
- **2.5.16** Widgets, extensions and notifications should relate to the app's content and functionality.
- **4.4** Extensions may not include marketing, advertising or in-app purchases.
- **3.1.2(a)** Subscriptions must be clear; tricking users into subscribing gets apps removed.
- **3.2.2(x)** Can't force ratings/reviews to unlock features.
- **5.1.1(ix)** Apps in highly regulated fields such as banking/financial services should be submitted by a legal entity. Sortd is a tracker, not a financial service, but check this against our listing wording (see `docs/AppReviewNotes.md`).

---

## 10. Suggested order

1. Instrument first: local `EngagementEvent` log + debug screen (S). Without it we can't tell if anything works.
2. v1: features 1–5.
3. Then 6, 7, 8, 9 (all S-ish).
4. Later: 10, 11, 13, 14; 12 before December if we want a year recap.

Open questions / unsure:
- Real Shortcut automation timeout limits for the Wallet trigger — forum threads exist but I didn't read them.
- Whether notification action buttons work well enough from the passive level (they should, but test on device).
- Whether App Store Connect still shows D1/D7/D28 retention for opted-in users — check in ASC.

---

## Sources

1. Dovetail — What is the Hook Model: https://dovetail.com/product-development/what-is-the-hook-model/
2. Amplitude — The Hook Model: https://amplitude.com/blog/the-hook-model (also seen in results: Yu-kai Chou critique https://yukaichou.com/gamification-analysis/hook-model-octalysis-habit-addiction/ — title/snippet only)
3. Duolingo blog — Improving the streak: https://blog.duolingo.com/improving-the-streak
4. BJ Fogg — Fogg Behavior Model: https://www.behaviormodel.org/
5. Tiny Habits explained (B=MAP, recipe): https://goalsandprogress.com/tiny-habits-fogg-behavior-model-explained/
6. Lenny's Newsletter — Behind the product: Duolingo streaks (Jackson Shuttleworth): https://www.lennysnewsletter.com/p/behind-the-product-duolingo-streaks
7. Copilot Help — Quick Start Guide: https://help.copilot.money/en/articles/11157550-quick-start-guide
8. Copilot Help — Month and Year in Review: https://help.copilot.money/en/articles/10310024-month-and-year-in-review
9. Conor Dewey — Reforge Recap: Engagement + Retention: https://www.conordewey.com/blog/reforge-engagement-retention/
10. Reforge — Defining your Aha moment: https://www.reforge.com/c/retention-series-eg/activation/aha-moment (page body didn't load; framework taken from [9])
11. UXCam — Mobile App Retention Benchmarks by Industry (2026): https://uxcam.com/blog/mobile-app-retention-benchmarks/
12. Plotline — Retention rates for mobile apps by industry: https://www.plotline.so/blog/retention-rates-mobile-apps-by-industry
13. Luna Budgeting — iOS Widgets guide: https://guide.lunabudgeting.com/features/ios-widgets ; Luna site https://lunabudgeting.com/ ; Chris Raroque YouTube https://www.youtube.com/@raroque (titles only) ; Building Luna playlist https://www.youtube.com/playlist?list=PLuT8P8ZASFFUa90gi5AieihpwnfJDsIBY (title only)
14. Up — The Evolutionary Design of Up: https://up.com.au/blog/the-evolutionary-design-of-up/
15. Monzo — Writing Year in Monzo 2024: https://monzo.com/blog/writing-year-in-monzo-2024 ; ombudsman complaint via https://benjykusi.substack.com/p/why-its-unsurprising-that-a-monzo (search snippet only)
16. Growth.Design — Spotify Wrapped psychology: https://growth.design/case-studies/spotify-wrapped-psychology
17. WWDC23 — Bring widgets to life: https://developer.apple.com/videos/play/wwdc2023/10028 (notes: https://wwdcnotes.com/documentation/wwdcnotes/wwdc23-10028-bring-widgets-to-life/)
18. Business of Apps — Push notification statistics: https://www.businessofapps.com/marketplace/push-notifications/research/push-notifications-statistics/ (survey figures seen via search summary; original survey source not verified)
19. Yancey & Settles (2020), A Sleeping, Recovering Bandit Algorithm for Optimizing Recurring Notifications, KDD '20: https://research.duolingo.com/papers/yancey.kdd20.pdf
20. WWDC24 — Extend your app's controls across the system: https://developer.apple.com/videos/play/wwdc2024/10157/ ; Apple docs — Controls: https://developer.apple.com/documentation/widgetkit/controls-collection
21. Apple Support — Transaction triggers in Shortcuts: https://support.apple.com/guide/shortcuts/transaction-trigger-apd65c67538a/ios ; forum threads (titles only): https://developer.apple.com/forums/thread/765516
22. Zhang, Y. (2023). Financial Self-regulation: How Does Expense-Tracking Inform Financial Behaviors? Consumer Interests Annual 69: https://www.consumerinterests.org/assets/docs/CIA/CIA2023/ZhangYilingCIA2023.pdf
23. The Decision Lab — Ostrich effect: https://thedecisionlab.com/biases/ostrich-effect ; CEPR/VoxEU — The ostrich in us: https://cepr.org/voxeu/columns/ostrich-us-selective-attention-personal-finances (403; search summary only)
24. WWDC24 — Bring your app to Siri: https://developer.apple.com/videos/play/wwdc2024/10133/ ; Apple docs — Integrating actions with Siri and Apple Intelligence: https://developer.apple.com/documentation/AppIntents/Integrating-actions-with-siri-and-apple-intelligence
25. Apple HIG — Live Activities: https://developer.apple.com/design/human-interface-guidelines/live-activities
26. WWDC21 — Send communication and Time Sensitive notifications: https://developer.apple.com/videos/play/wwdc2021/10091/ (notes: https://wwdcnotes.com/documentation/wwdc21-10091-send-communication-and-time-sensitive-notifications/) ; HIG Notifications: https://developer.apple.com/design/human-interface-guidelines/notifications
27. WWDC23 — Bring widgets to new places (StandBy): https://developer.apple.com/videos/play/wwdc2023/10027/ ; https://nemecek.be/blog/201/how-to-update-widgets-for-standby-mode
28. WWDC23 — Build widgets for the Smart Stack on Apple Watch: https://developer.apple.com/videos/play/wwdc2023/10029/
29. uxpeak — The UX Psychology Behind Apps People Can't Stop Using (video): https://www.youtube.com/watch?v=2TlIg3VokY8 ; transcript/summary read at https://sozai.app/transcript/ux-psychology-behind-addictive-apps/
30. NN/g — Confirmation dialogs can prevent user errors: https://www.nngroup.com/articles/confirmation-dialog/
31. Apple HIG — Playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
32. NN/g — Deceptive patterns in UX: https://www.nngroup.com/articles/deceptive-patterns/
33. Deceptive Patterns (Harry Brignull): https://deceptive.design/
34. Apple — App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

Other pages seen only as search results (used for "search summary" lines): Monarch help https://help.monarch.com/hc/en-us/articles/16116906962452-About-Monarch-s-AI-Features ; YNAB method https://www.ynab.com/guide/foundations-the-ynab-method ; Cleo roast mode https://web.meetcleo.com/blog/the-money-app-that-roasts-you ; Rocket Money https://www.rocketmoney.com/feature/manage-subscriptions ; Emma https://emma-app.com/features/tracking ; Business of Apps finance benchmarks https://www.businessofapps.com/data/finance-app-benchmarks/ ; Adjust retention 2023 https://www.adjust.com/blog/get-the-mobile-app-retention-benchmarks-for-2023/
