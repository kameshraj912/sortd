# 02 — Onboarding research: get to know the user first

*Written 22 Sep 2026. Web research only. No user testing yet.*

## TL;DR

- **The problem is the order, not the length.** Sortd's current flow (`Spend/Views/OnboardingView.swift`) goes welcome → currency → cards → card details → Apple Pay → Gmail → budget → reminders → Pro → finish. The second screen already asks for data. Nothing asks what the person wants, so nothing after it can be tailored.
- **A short quiz first works, even when the questions change little.** In a 5-arm Headspace test, a short quiz followed by a recommendation raised course starts from 31% to about 63%. The "perceived fit" arm, where everyone got the *same* course after the quiz, did almost as well. The questions made people feel the result was made for them. ([Purchasely](https://www.purchasely.com/blog/headspace-behavioral-science-onboarding-experiment), [Kristen Berman](https://kristenberman.substack.com/p/lessons-on-habit-formation-from-an))
- **Show the paywall during onboarding, after a personal plan and a first win.** About half of paid conversions happen on Day 0, and most trials start that day ([RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps)). So the paywall should sit inside onboarding, after the user has seen their plan and logged a first Apple Pay tap. Split it over 2 pages: Superwall saw 12.41% conversion for multi-page onboarding paywalls vs 9.07% for single-page ([Superwall](https://superwall.com/blog/new-postmulti-page-onboarding-paywalls-convert-37-better-than-single-page-heres-why)).
- **Be honest about the trial and it pays back.** Blinkist's "how your trial works" timeline raised trial starts by 23%, cut complaints by 55%, and lifted push opt-in from 6% to 74% ([growth.design](https://growth.design/case-studies/trial-paywall-challenge)).
- **Proposed flow: 12 screens, about 2 minutes.** 5 questions → a "building your setup" screen that explains the product → a personal plan → cards → a live first Apple Pay tap → a 2-page Pro offer → home, laid out from the answers. Each answer changes something later. The full spec is in §5.

---

## 1. What Sortd does today (for context)

From `OnboardingView.swift` (`enum Step`): `welcome, currency, cards, cardDetails, applePay, email, budget, reminders, pro, finish`.

What's already good, and worth keeping:
- The welcome screen has "Explore with sample data" and "I already have spending to bring in". These are try-before-you-commit exits.
- A "Skip setup" button on every step, and skipped steps get sensible defaults.
- The Apple Pay step shows a live "Waiting for your first tap" state. This is the real aha moment and the strongest screen in the flow.
- The progress bar counts only the steps that will be shown.

What makes it feel rushed:
- Currency and card numbers come before the app knows anything about the person, so every user gets the same 10 steps.
- Six of the 10 steps are setup chores (currency, cards, card details, Shortcut, Gmail, budget). None of them is framed around what the person said they wanted, because the person was never asked.
- The Pro pitch is generic. It can't say "you told us you shop online a lot, so Gmail receipts will catch those."
- The notification ask ("Heads-up before bills") isn't tied to a choice the user made about how often they want to hear from Sortd.

---

## 2. Teardowns

### Finance apps

| App | What they do in onboarding | What Sortd can take |
|---|---|---|
| **Copilot Money** | Connect accounts first, then choose a plan to start the trial, then budget, review transactions, recurrings and goals ([Copilot help](https://help.copilot.money/en/articles/11157550-quick-start-guide)). About 10 onboarding screens with the paywall after them ([Appllama](https://appllama.io/apps/1447330651/copilot-track-budget-money), full screens gated). Kristen Berman praises how they frame the notification opt-in, but says they "missed making hard things fun" ([Berman](https://kristenberman.substack.com/p/copilot-we-can-do-hard-things)). | Treat setup chores as the hard part and make them feel like progress. Frame the notification ask around a benefit. |
| **Monarch** | Value carousel → email verification → **questions about goals and how you found them** → personal details → **visual free-trial timeline** → connect accounts, with a small celebration on success. The teardown praises the trial timeline for lowering anxiety, and says the value slides repeat each other ([John Stone](https://johnstone.substack.com/p/product-teardown-monarch-money)). | Goal question early. Trial timeline on the paywall. A celebration when a connection works. |
| **YNAB** | A 6-step guided setup that teaches the method (goal, link account, budget) with a progress bar, in a friendly tone. The goal is changing how people think about money, more than teaching the software ([GoodUX](https://goodux.appcues.com/blog/you-need-a-budget-ynab-s-friendly-ux-copywriting)). Follow-up email: "knowing your why" ([Copyhackers](https://copyhackers.com/2022/04/onboarding-flow/)). | Warm, plain copy. Teach one idea ("it logs itself"), not every feature. |
| **Rocket Money** | "Pay what you think is fair" premium ($7–14/mo) with a 7-day trial ([Rocket Money](https://www.rocketmoney.com/learn/personal-finance/how-much-does-rocket-money-cost)). I couldn't find a screen-by-screen teardown. | Could be tested later on pricing. Not an onboarding pattern. |
| **Cleo** | The last onboarding step is a chat that asks where you want to start: controlling spending, cash advance, credit, or seeing where money goes ([The Everygirl](https://theeverygirl.com/cleo-review/)). Its personality is designed on purpose, but it's a fine line ([Econsultancy](https://econsultancy.com/cleo-chatbot-financial-services-persona-marketing/)). | "Where do you want to start?" as a goal question. Sortd's copy can have a little warmth, not sass. |
| **Emma** | Bank connection is still the biggest drop-off. Before open banking they lost "50% of people right at the connection page". A daily 8 am balance notification "increased retention quite a lot". Roughly half their users pay. They use a 7-day trial ([Fintech Growth Insider](https://www.fintechgrowthinsider.com/p/edoardo-moreni-emma)). | Sortd has no bank login, which is an advantage: its hardest step is the Shortcut. A fixed-time daily summary is a proven retention lever. |
| **Revolut** | "What do you want to use Revolut for?" is really a compliance question, but it's shown as emoji chips grouped by theme, with honest copy ("for regulatory reasons. And also, we're curious!"). One action per screen, progress feedback, previews of features during signup ([Raw.Studio](https://raw.studio/blog/how-revolut-uses-4-onboarding-ux-tactics/), [Craft Innovations](https://craftinnovations.global/revolut-onboarding-flow-analysis/)). | Chip-based multi-select for goals. Be honest about why you ask. |
| **Wise** | The price calculator works before signup: amount, currency, fees and rate are shown upfront ([Wise](https://wise.com/us/blog/how-to-open-wise-account)). | Show a currency conversion preview on the currency screen ("A$20 ≈ S$17 today") so it feels like a result, not a form. |
| **Up Bank (AU)** | Account open in under 3 minutes. They designed the physical welcome pack and card so the start feels special ([Up blog](https://up.com.au/blog/designing-a-super-powered-welcome-pack-experience/)). | Aim for 2–3 minutes, and make the landing moment (first home screen) feel like an arrival. |
| **Frollo (AU)** | Open-banking consent is the pain point. Frollo reports nearly 30% of consent authorisations failing at the bank level ([Frollo media release](https://frollo.com.au/media_release/australian-open-banking-reaches-inflection-point-with-industry-wide-momentum-building/), via search summary; I didn't read the full release). | Sortd's "no bank login" is a real selling point in Australia. Say it early. |
| **Mint successors** | Credit Karma absorbed Mint. I found no useful onboarding teardown. Skipped. | — |

### Best-in-class outside finance

| App | Pattern | Evidence |
|---|---|---|
| **Duolingo** | Goal → motivation → level → **first lesson before signup**. Signup comes when you want to save progress. Reported +20% DAU from delaying signup (a secondary blog claim; I couldn't find Duolingo's own source). | [GoodUX](https://goodux.appcues.com/blog/duolingo-user-onboarding), [Relaunch](https://relaunch.ai/blog/duolingo-onboarding-teardown-7-b-tests-behind-their-9-conver.html) |
| **Headspace** | "Why are you here?" intent screen. Critiques: paywall before any value, a notification ask with no value first, 9–10 taps to the first session. Best data point: the quiz-then-recommend test above. | [Tear Them Down](https://tearthemdown.substack.com/p/headspace), [growth.design](https://growth.design/case-studies/headspace-user-onboarding), [Purchasely](https://www.purchasely.com/blog/headspace-behavioral-science-onboarding-experiment) |
| **Noom** | 113 screens, 10–15 min. Works because each step gives something back: explains *why* it asks, reassures after sensitive answers, shows the personal timeline *before* the email gate, uses loaders to teach, uses "Question X of 10" counters. Missed chance: never shows the actual app before pricing. | [RevenueCat teardown](https://www.revenuecat.com/blog/growth/web-to-app-onboarding-funnel), [Retention.blog](https://www.retention.blog/p/the-longest-onboarding-ever) |
| **Calm** | "Take a deep breath" first screen. Multi-select goals **with skip**. Notification ask, then signup, then premium. | [Usability Geek](https://usabilitygeek.com/ux-case-study-calm-mobile-app/) |
| **Opal** | 24 steps. A quiz produces a personal "Focus Report" (hours of life lost to the phone), then a commitment moment, then a soft paywall with a 7-day trial at about 1:48. | [ScreensDesign](https://screensdesign.com/showcase/opal-screen-time-control) |
| **Fabulous** | Long quiz → user "signs" a commitment contract → soft paywall. Commitments start small and grow. | [Behavioral Scientist](https://www.thebehavioralscientist.com/articles/fabulous-app-product-critique-onboarding), [ScreensDesign](https://screensdesign.com/showcase/fabulous-daily-habit-tracker) |
| **Flighty** | Your first flight gets Pro free, no card. You feel the premium features on real data before paying. | [Flighty pricing](https://flighty.com/pricing) |
| **Structured** | Interactive onboarding where you build your first day's plan, so value shows immediately (criticised as 10+ steps). Liquid Glass redesign for iOS 26. | [ScreensDesign](https://screensdesign.com/showcase/structured-daily-planner) |
| **Things 3** | No quiz. A "Meet Things" tutorial project lives in the app as real to-dos you tick off. | [Cultured Code](https://culturedcode.com/things/support/articles/2803553/), [Mobbin](https://mobbin.com/explore/flows/37eb30d1-caa8-4795-ae8b-0ea1a7e790eb) |
| **Arc (Browser Company)** | Rich, colourful setup that ends in a personal "membership card". Users liked being "set free" early. (Found for Arc desktop, not Arc Search specifically.) | [Inverse](https://www.inverse.com/input/design/the-browser-company-arc-design-interview) |

---

## 3. Patterns and what the evidence says

**Goal-first personalisation quiz.** This is the best-supported pattern. The Headspace test shows the *act of being asked* creates perceived fit (31% → ~63% course starts). The caveat matters: active meditation days did **not** rise significantly in any arm ([Purchasely](https://www.purchasely.com/blog/headspace-behavioral-science-onboarding-experiment)). A quiz boosts starting, not the habit itself. The same test's pre-commitment arm (a plan for *when* to meditate) gave +7.5% app opens and +4% return days. That's the case for asking "when do you want to check in?"

**Explain why you ask.** Noom explains every sensitive question and reassures after hard answers ([RevenueCat](https://www.revenuecat.com/blog/growth/web-to-app-onboarding-funnel)). NN/g says content customisation is fine in onboarding if it's brief and says why the data is needed ([NN/g](https://www.nngroup.com/articles/mobile-app-onboarding/)).

**Keep it short unless every step pays back.** NN/g's default advice is to avoid onboarding. Their test of 70 users found deck-of-cards tutorials didn't improve task success ([NN/g](https://www.nngroup.com/articles/mobile-tutorials/)). Long flows (Noom, Opal, Cal AI) work only when each screen shows "visible personalization or a buyer filter" (rule distilled from Tim Gabe teardowns by a third party, [bixxter/app-growth-design](https://github.com/bixxter/app-growth-design)). For Sortd: questions are fine, feature tours are not.

**Progress indicators.** Chameleon (web product tours, not mobile onboarding) found progress indicators raise completion by 12% and cut dismissals by 20%. 3-step tours complete at 72% vs a 61% average ([Chameleon](https://www.chameleon.io/blog/product-tour-benchmarks-highlights)). Noom uses "Question X of 10". uxpeak: don't start the bar at 0%. Pre-filled loyalty cards roughly doubled completion ([summary of uxpeak video](https://sozai.app/transcript/ux-psychology-behind-addictive-apps/)).

**Value before signup, and try before you connect.** Duolingo gives a lesson before signup. Flighty gives the first flight free. Wise shows a calculator with no login. The fintech advice is to show a sample-data dashboard so connecting "feels like unlocking something" ([Lifecycle Architect](https://lifecyclearchitect.com/guides/onboarding-optimization-for-fintech/). Its "60–75% never reach first action" figure is **unsourced**, so I don't rely on it). Sortd already has sample data. Keep it, and offer it again at the plan step.

**Permission priming.** Apple HIG: ask during onboarding only if the app needs it to work, and say why. Otherwise ask when the feature is first used ([HIG Onboarding mirror](https://github.com/incrediblecrab/apple-os-documentation/blob/main/human-interface-guidelines/patterns/onboarding.md)). On pre-alert screens, the HIG says ([search summary of HIG Accessing private data](https://developers.apple.com/design/human-interface-guidelines/patterns/accessing-private-data/); the page didn't render for me):
- use **one button** that clearly opens the system alert
- don't label it "Allow"
- don't draw or copy the system alert
- don't point at its Allow button

Appcues: ask only when needed, explain the benefit, and make saying no easy and reversible ([Appcues](https://www.appcues.com/blog/mobile-permission-priming)). The common "priming lifts opt-in 2–3x" claims come from vendor blogs without primary data, so treat them as unverified. The strongest real number is Blinkist's 6% → 74% push opt-in, and it came from tying notifications to a trial-reminder promise the user wanted.

**Sunk cost and commitment.** Noom, Fabulous (signed contract) and Opal ("fist bump") all add a small commitment just before the paywall. Use it gently. Sortd's version is the plan screen, where the user ticks what they'll do.

**A personal plan at the end.** Noom shows the personal timeline before the email gate. Opal shows a personal report before the paywall. Monarch builds its forecast from onboarding answers ([Monarch help](https://help.monarch.com/hc/en-us/articles/48344305092244-Forecasting-in-Monarch)). Loading screens should teach, not just spin ([growth.design Headspace](https://growth.design/case-studies/headspace-user-onboarding)).

**Where the paywall goes.**
- About 50% of paid conversions happen on Day 0, and "users who don't try immediately rarely try at all" ([RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps)).
- Onboarding paywalls produce about 50% of trial starts at strong apps ([RevenueCat guide](https://www.revenuecat.com/blog/growth/guide-to-mobile-paywalls-subscription-apps)).
- Moving the paywall into onboarding: Greg went from 3% → 15% sign-up-to-trial, and Rootd saw 5x revenue ([RevenueCat placement](https://www.revenuecat.com/blog/growth/paywall-placement)).
- PhotoRoom puts the paywall right after the aha moment (removing a photo background).

So the paywall belongs **inside onboarding, right after the first aha** (the plan plus the first logged tap), then again in context whenever a locked feature is tapped. Headspace was criticised for a paywall *before* any value.

**Skip options.** Apple HIG says make onboarding optional and defer setup with sensible defaults. Calm lets you skip goals, and Noom offers "I haven't decided". Sortd already has "Skip setup". Keep it, and add a "Not sure yet" option on each question.

**Trial length and honesty.** The longer the trial, the better it converts: median trial-to-paid is 25.5% for trials of 4 days or less, 37.4% for 5–9 days, and 42.5% for 17–32 days. 55.4% of 3-day trials are cancelled on Day 0 ([RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps)). A transparent timeline (Blinkist, Monarch) helps. Sortd needs about a week of taps before insights mean anything, so a 7–14 day trial fits better than 3 days. That's a pricing call for the founder, not a research fact.

---

## 4. Videos (YouTube)

I couldn't open any YouTube page content (only footers came back). Everything below comes from titles, third-party summaries or the creator's own blog. Nothing here is from watching the videos.

- **uxpeak — "The UX Psychology Behind Apps People Can't Stop Using"** ([video](https://www.youtube.com/watch?v=2TlIg3VokY8); points from third-party summaries [Sozai](https://sozai.app/transcript/ux-psychology-behind-addictive-apps/) and [YouTubeSummary](https://youtubesummary.com/summary/2TlIg3VokY8)):
  - use smart defaults, since 70–90% of people never change them (cited in the video; I didn't find its original source)
  - never start the progress bar at 0%
  - give a usable partial result before asking for signup
  - let people build something first (the IKEA effect)
  - frame by loss
  - anchor prices
- **Chris Raroque — "How I Make Apps FEEL Premium (5 examples)"** and **"How I Make Apps FEEL 10x Better (5 Design Secrets)"** ([video](https://www.youtube.com/watch?v=MXLF8b15GhQ), [video](https://www.youtube.com/watch?v=8mMH6Pq8qnE)). **Title only.** The transcript site was down. His own post on "surprise and delight" ([Builder Notes](https://notes.chrisraroque.com/p/what-surprise-and-delight-actually)) argues real delight is a moment that feels "almost impossible", from hidden work (e.g. using nearby restaurant names to fix dictation), more than flashy animation. For Sortd, the hidden work is guessing home currency from locale, suggesting the user's likely banks, and having the first Apple Pay tap appear instantly.
- **Tim Gabe** — "This app onboarding hides the paywall", "I Studied 10,000 Paywall Screens" ([channel](https://www.youtube.com/@TimGabe), [video](https://www.youtube.com/watch?v=uw0Y_FiKkYQ)). **Titles plus a third-party distillation** of 30 teardowns ([bixxter/app-growth-design](https://github.com/bixxter/app-growth-design)):
  - onboarding length is justified only by visible personalisation
  - paywall *structure* (trial, plan length, plan count) beats price and visuals in testing
  - "82–89% of trial starts occur on install day"

  I haven't checked his underlying data.
- **Apple WWDC haptics sessions** ("Practice audio haptic design", WWDC21, [link](https://developer.apple.com/videos/play/wwdc2021/10278/)). From the session description: haptics should match what's on screen and feel like a physical cause and effect.

---

## 5. Proposed Sortd onboarding — 12 screens, about 2 minutes

**Rules for the whole flow**
- **Order:** questions (screens 2–7), then a result (8–9), then setup (10–11), then the offer (12). Nothing is asked for before the app has earned it.
- **Progress:** a segmented bar that starts with the first segment already filled. Show "Question 2 of 5" on quiz screens.
- **Skipping:** "Skip setup" stays top-right and jumps to the plan (screen 9) with defaults. Each question has a quiet "Not sure yet".
- **iOS style:**
  - Liquid Glass only on the floating layer (the bottom button bar, the back and skip controls, sheets). Never on the answer cards themselves; Apple reserves glass for the navigation layer ([summary of HIG guidance](https://www.createwithswift.com/liquid-glass-redefining-design-through-hierarchy-harmony-and-consistency/)).
  - Answer chips are solid cards with an SF Symbol each.
  - `.sensoryFeedback(.selection)` on each chip tap, `.impact(.light)` on Continue, `.success` when the first tap arrives and when the plan appears.
  - Chips use a multi-select check mark, not auto-advance, so people can explore before confirming (Headspace critique).
- **Copy:** short sentences, second person, no jargon. Say "on this iPhone" rather than "on-device".

### Screen-by-screen

**1. Welcome**
- *Purpose:* say what Sortd is in one line and promise it's quick.
- *Content:* "sortd" wordmark. "Your spending, logged by itself." Three small SF Symbol rows: `wave.3.right` Apple Pay taps, `envelope` receipts, `lock.iphone` "Stays on this iPhone. No bank login."
- *Actions:* **Get started** (primary). "I already have spending to bring in" and "Look around with sample data" (secondary, both kept from today).
- *Personalises:* nothing. The sample-data path still gets the quiz later from a home banner ("Make Sortd yours — 1 min").

**2. What brings you here?** (Question 1 of 5)
- *Purpose:* the goal. This drives almost everything else.
- *Question:* "What do you want Sortd to help with?" *Pick any.*
- *Options (chips):*
  - `chart.pie` See where my money goes
  - `gauge.with.dots.needle.33percent` Spend less each month
  - `airplane` Keep track across countries
  - `repeat` Catch subscriptions and bills
  - `receipt` Keep receipts in one place
  - `questionmark.circle` Not sure yet
- *Personalises:*
  - **Home card order.** Where-it-goes → category breakdown first. Spend-less → "left this month" card first and the budget step shown. Countries → currency split card. Subscriptions → upcoming bills card. Receipts → receipts inbox card.
  - Which later steps appear (the budget step only if "Spend less").
  - Which Pro benefits the paywall leads with.
  - The first insight Sortd shows after a week.

**3. How you pay** (Question 2 of 5)
- *Purpose:* decide which capture methods matter, so we don't push the Shortcut on a cash-heavy user.
- *Question:* "How do you usually pay?"
- *Options (single choice):*
  - `iphone` Mostly Apple Pay
  - `creditcard` Mostly card, tapped or online
  - `cart` A lot of online shopping
  - `banknote` Often cash
  - `shuffle` A mix
- *Personalises:*
  - Apple Pay users → the Shortcut step (11) is shown as the main step.
  - Online shoppers → the paywall leads with Gmail receipts.
  - Cash users → a quick-add widget and the Control Center / Action Button tip go on the plan, and Apple Pay drops to optional.
  - Order of items on the plan screen.

**4. Where you spend** (Question 3 of 5)
- *Purpose:* home currency, plus whether multi-currency matters.
- *Question:* "Your main currency" with a smart default from the device region (AUD in Australia, SGD in Singapore; the uxpeak point on defaults). Below it: "Do you spend in other currencies?" with Often / Sometimes / Rarely.
- *Live preview:* "A$25.00 ≈ S$21.xx today", using the on-device rate. This makes it feel like the app is already working (the Wise pattern).
- *Personalises:*
  - Home currency for all totals.
  - Often or Sometimes → the currency split card on home, a second-currency chip in quick add, and the FX line on transactions.
  - Rarely → FX details hidden until a foreign purchase appears.

**5. How it feels right now** (Question 4 of 5)
- *Purpose:* the emotional check-in (Noom). It sets tone and nudge strength, and the user feels heard.
- *Question:* "How do you feel about your spending lately?"
- *Options:*
  - `checkmark.seal` In control
  - `hand.thumbsup` Mostly fine
  - `cloud.fog` A bit lost
  - `exclamationmark.triangle` Stressed
- *Reply:* after tapping, a one-line reassurance fades in above the button. For "Stressed": "Thanks for being honest. Most people feel better once they can just see it. No judging here."
- *Personalises:*
  - Wording of insights ("You spent more on food" vs "Food was higher than usual — here's why").
  - The default budget suggestion: none for "In control", gentle for "Lost" or "Stressed".
  - Whether the weekly recap leads with wins or with totals.

**6. A monthly limit?** (Question 5 of 5 — only if "Spend less" was picked; otherwise skipped and the counter reads "of 4")
- *Purpose:* set a number while the motivation is fresh.
- *Question:* "Want a monthly spending limit?" A slider with a suggested round number in the home currency. "No limit for now" is equally visible.
- *Note:* budgets are a **Pro feature**. Show a small "Pro · free during your trial" tag. Don't hide it. **Decision for Raj:** either keep one simple budget free (which makes this screen honest for everyone), or keep this screen as intent capture that turns on with the trial.
- *Personalises:* the "left this month / left today" home card, budget alerts, and the plan item.

**7. When should we check in?** (the pre-commitment step, then the permission ask)
- *Purpose:* the user picks their own rhythm (Headspace pre-commitment arm: +7.5% app opens; Emma's daily 8 am balance drove retention). Then the notification ask makes sense.
- *Question:* "When do you want a quick look at your spending?"
- *Options:*
  - `sun.max` Each morning (8 am)
  - `moon` Each evening (8 pm)
  - `calendar` Sunday recap
  - `bell.slash` Only when something needs me
- *Plus a toggle:* "Tell me the day before a bill or subscription is due" (on by default when "Catch subscriptions" was picked).
- *Button:* one button, "Turn on notifications". It opens the iOS alert directly. Per HIG: no "Allow" label, no fake alert, one button. "Not now" is small text below. If they choose "Only when something needs me" and turn the bill toggle off, skip the system prompt entirely.
- *Personalises:* notification schedule and content, recap timing, bill reminders.

**8. Building your setup** (the loader that explains)
- *Purpose:* a short pause (about 2.5 s, skippable by tap) that makes the result feel made for them, and teaches the one privacy idea.
- *Content:* three lines tick in with a light haptic each:
  - "Setting your home currency to AUD"
  - "Putting 'Left this month' first"
  - "Keeping everything on this iPhone — Sortd never sees your bank login"
- *Personalises:* nothing new. It shows back what the answers did (the Noom and Headspace lesson).

**9. Your plan** (the commitment and aha screen)
- *Purpose:* a personal plan, shown as a short checklist. The user sees what Sortd will do for them before any chores.
- *Header:* "Here's your Sortd." Subheader built from the answers, e.g. "Built for spending in AUD and SGD, with a monthly limit of A$1,500."
- *Checklist* (ordered by answers, each item with time and a Free or Pro tag):
  1. Add the cards you pay with — 30 sec · Free
  2. Log Apple Pay taps by themselves — 2 min · Free
  3. Catch online receipts from Gmail — 1 min · Pro
  4. Scan paper receipts — later, when you need it · Pro
- *Preview:* a small mock of *their* home screen, with cards in the order from their answers and faded sample numbers. It answers Noom's missing "what will I actually use?"
- *Actions:* **Start with step 1** (primary). "Do this later and look around" (secondary). That drops them on home with the checklist pinned as a "Finish setup" card (the Things tutorial-project idea).
- *Personalises:* sets the order of screens 10–12 and the home "Finish setup" card.

**10. Your cards** (setup, now framed as plan step 1)
- *Purpose:* banks plus the last 4 digits, so taps and emails match the right card.
- *Content:* today's cards and card-details screens merged into one screen. Bank chips are pre-sorted by country (CommBank, NAB, ANZ, Westpac, Up for AU; DBS/POSB, OCBC, UOB for SG). Tap a bank, then type the last 4. Credit or debit sits on the same row. The Apple Pay device number is behind a "Where do I find this?" disclosure, not upfront.
- *Skip:* "Add cards later". Taps still log, just without a card name.
- *Personalises:* card names on transactions, email matching, per-card filter on home.

**11. First Apple Pay tap** (setup, plan step 2 — the aha)
- *Purpose:* the moment the app proves itself. Keep today's live "Waiting for your first tap" design; it's the best screen in the current flow.
- *Content:* a 3-step mini guide to the Shortcuts automation, an "Open Shortcuts" button, and a live status card. When the first tap arrives: `.success` haptic, the card flips to "Logged A$4.50 at Market Lane", and a small confetti burst in brand colours. Include a "Log a test tap" button so people can see it work without buying anything.
- *Skip:* "I'll do this later". It stays in the home checklist. Hidden entirely for "Often cash" users, who get the quick-add widget tip instead.
- *Personalises:* marks the Apple Pay capture as on, and teaches the user where taps appear.

**12. Pro — two pages** (the paywall, after the aha)
- *Page A, "What Pro adds for you":* 3 benefits picked from their answers.
  - Online shopper → "Receipts from Gmail, added by themselves".
  - Spend less → "Budgets and a daily 'left to spend'".
  - Where it goes → "Monthly insights: what changed and why".
  - Always: "Scan paper receipts with the camera".
- *Page B, "How your free trial works":* a Blinkist-style timeline.
  - Today: full access.
  - Day X−2: "We'll remind you" (tied to the notification choice from screen 7).
  - Day X: "Your plan starts. Cancel any time before."
  - Price in the home currency, with annual shown as a per-month equivalent.
  - Visible close button, no asterisks.
- *Actions:* **Start free trial** / "Maybe later" (plain, same size as body text, not hidden).
- *Straight after starting a trial:* if they chose online shopping or receipts, go right to "Connect Gmail" while motivation is high (Gmail is Pro, so ask only now). If they said "Maybe later", every locked feature shows a small in-context paywall when tapped (the RevenueCat placement advice).
- *Personalises:* Pro state, Gmail setup, and which locked cards show "Try Pro" on home.

**Then → Home.** Cards appear in the order the answers set. A dismissable "Finish setup · 2 of 4 done" card at the top reuses the plan checklist (it starts partly filled, the goal-gradient effect). There's a gentle welcome animation the first time, like Up's point about making the landing feel like an arrival.

### Where permissions and the paywall sit

| Ask | Screen | Why there |
|---|---|---|
| Notifications | 7, straight after the user picks a check-in time | The benefit is concrete and chosen by them. Skipped if they want no alerts. |
| Shortcuts automation (not a permission, but a trust ask) | 11 | After the plan, framed as a step they already signed up for. |
| Gmail (OAuth) | After starting a trial on 12, or later from the home checklist | Pro-only, and needs trust. Ask in context, never before value. |
| Camera | Only on the first receipt scan | HIG: ask when the feature is first used. |
| Paywall | 12, after the plan and the first tap, plus in context later | Day 0 is when most conversions happen, but only after value (PhotoRoom, Headspace critique). |

### What each answer drives later (summary)

| Answer | Drives |
|---|---|
| Goals (2) | Home card order, budget step shown or not, paywall benefit order, first insight |
| Payment habit (3) | Apple Pay step shown or not, quick-add widget tip, Gmail pitch |
| Currency (4) | Home currency, currency split card, FX display, quick-add currency chip |
| Feeling (5) | Insight tone, default budget nudge, recap framing |
| Limit (6) | "Left this month / today" card, budget alerts |
| Check-in time (7) | Notification schedule, recap day, bill reminders, trial reminder |

### What to measure after it ships

- Step-by-step drop-off (screen 1 → 2 is the riskiest).
- Share reaching the plan screen.
- First tap logged on Day 0.
- Trial starts from screen 12 vs from in-context paywalls.
- Day 7 retention by answer to Q1.

A/B test first: plan screen vs no plan screen, and a 1-page vs 2-page paywall.

---

## 6. Hard numbers (with sources)

| Number | Context | Source |
|---|---|---|
| ~50% of paid conversions on Day 0 | All categories | [RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps) |
| 82–90% of trial starts on Day 0 | Health & Fitness 82.1%, Business 89.9% | [RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps) |
| 55.4% / 39.8% / 35.7% / 31.1% Day-0 cancels | 3 / 7 / 14 / 30-day trials | [RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps) |
| 25.5% vs 37.4% vs 42.5% trial-to-paid | ≤4 / 5–9 / 17–32-day trials (median) | [RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps) |
| 10.7% vs 2.1% D35 download-to-paid | Hard paywall vs freemium (median) | [RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps) |
| 12.41% vs 9.07% | Multi- vs single-page onboarding paywalls, 40M opens, Feb–May 2026 | [Superwall](https://superwall.com/blog/new-postmulti-page-onboarding-paywalls-convert-37-better-than-single-page-heres-why) |
| 3% → 15% sign-up-to-trial | Greg app, paywall shown in onboarding | [RevenueCat](https://www.revenuecat.com/blog/growth/paywall-placement) |
| 5x revenue | Rootd, paywall moved earlier in onboarding | [RevenueCat](https://www.revenuecat.com/blog/growth/paywall-placement) |
| +23% trial conversion, −55% complaints, push opt-in 6% → 74% | Blinkist transparent trial paywall | [growth.design](https://growth.design/case-studies/trial-paywall-challenge) |
| 31% → ~63% course starts | Headspace quiz + recommendation. No significant change in active days | [Purchasely](https://www.purchasely.com/blog/headspace-behavioral-science-onboarding-experiment) |
| +7.5% app opens, +4% return days | Headspace pre-commitment arm | [Kristen Berman](https://kristenberman.substack.com/p/lessons-on-habit-formation-from-an) |
| 50% lost at bank connection page | Emma, before open banking | [Fintech Growth Insider](https://www.fintechgrowthinsider.com/p/edoardo-moreni-emma) |
| 61% average, 72% for 3 steps | Web product tour completion (not mobile onboarding) | [Chameleon](https://www.chameleon.io/blog/product-tour-benchmarks-highlights) |
| +12% completion, −20% dismissals | Progress indicators in product tours | [Chameleon](https://www.chameleon.io/blog/product-tour-benchmarks-highlights) |
| No better task success | Deck-of-cards tutorials, 70 users | [NN/g](https://www.nngroup.com/articles/mobile-tutorials/) |

**Weak or unverified, don't quote as fact:**
- Duolingo "+20% DAU from delayed signup" (secondary blog).
- "Priming lifts opt-in 2–3x" (vendor blogs).
- "60–75% of fintech signups never reach first action" (unsourced).
- "72% of users want onboarding under 60 s" (a Clutch 2017 survey, cited via [Appcues](https://www.appcues.com/blog/mobile-permission-priming)).

---

## 7. Open questions for Raj

1. **Budgets.** Should one simple budget be free? It makes screen 6 honest for everyone and gives free users a daily reason to open the app.
2. **Trial length.** Sortd needs about a week of taps before insights are worth anything. The RevenueCat data favours 7 days or more over 3.
3. **Where to store answers.** They should live on the iPhone (e.g. a `UserProfile` in SwiftData) so home, insights and notifications can read them. They need to be editable in Settings ("Your goals").
4. **Sample-data path.** Should "Look around first" users see the quiz on their first return, or only when they tap "Make Sortd yours"?

---

## Sources

Finance apps
- https://help.copilot.money/en/articles/11157550-quick-start-guide
- https://appllama.io/apps/1447330651/copilot-track-budget-money
- https://kristenberman.substack.com/p/copilot-we-can-do-hard-things
- https://johnstone.substack.com/p/product-teardown-monarch-money
- https://help.monarch.com/hc/en-us/articles/48344305092244-Forecasting-in-Monarch
- https://goodux.appcues.com/blog/you-need-a-budget-ynab-s-friendly-ux-copywriting
- https://copyhackers.com/2022/04/onboarding-flow/
- https://www.rocketmoney.com/learn/personal-finance/how-much-does-rocket-money-cost
- https://theeverygirl.com/cleo-review/
- https://econsultancy.com/cleo-chatbot-financial-services-persona-marketing/
- https://www.fintechgrowthinsider.com/p/edoardo-moreni-emma
- https://raw.studio/blog/how-revolut-uses-4-onboarding-ux-tactics/
- https://craftinnovations.global/revolut-onboarding-flow-analysis/
- https://wise.com/us/blog/how-to-open-wise-account
- https://up.com.au/blog/designing-a-super-powered-welcome-pack-experience/
- https://frollo.com.au/media_release/australian-open-banking-reaches-inflection-point-with-industry-wide-momentum-building/
- https://lifecyclearchitect.com/guides/onboarding-optimization-for-fintech/

Non-finance apps
- https://goodux.appcues.com/blog/duolingo-user-onboarding
- https://relaunch.ai/blog/duolingo-onboarding-teardown-7-b-tests-behind-their-9-conver.html
- https://tearthemdown.substack.com/p/headspace
- https://growth.design/case-studies/headspace-user-onboarding
- https://www.purchasely.com/blog/headspace-behavioral-science-onboarding-experiment
- https://kristenberman.substack.com/p/lessons-on-habit-formation-from-an
- https://www.revenuecat.com/blog/growth/web-to-app-onboarding-funnel
- https://www.retention.blog/p/the-longest-onboarding-ever
- https://usabilitygeek.com/ux-case-study-calm-mobile-app/
- https://screensdesign.com/showcase/opal-screen-time-control
- https://www.thebehavioralscientist.com/articles/fabulous-app-product-critique-onboarding
- https://screensdesign.com/showcase/fabulous-daily-habit-tracker
- https://flighty.com/pricing
- https://screensdesign.com/showcase/structured-daily-planner
- https://culturedcode.com/things/support/articles/2803553/
- https://mobbin.com/explore/flows/37eb30d1-caa8-4795-ae8b-0ea1a7e790eb
- https://www.inverse.com/input/design/the-browser-company-arc-design-interview

Paywalls, data and research
- https://www.revenuecat.com/state-of-subscription-apps
- https://www.revenuecat.com/blog/growth/paywall-placement
- https://www.revenuecat.com/blog/growth/guide-to-mobile-paywalls-subscription-apps
- https://superwall.com/blog/new-postmulti-page-onboarding-paywalls-convert-37-better-than-single-page-heres-why
- https://growth.design/case-studies/trial-paywall-challenge
- https://www.chameleon.io/blog/product-tour-benchmarks-highlights
- https://www.nngroup.com/articles/mobile-app-onboarding/
- https://www.nngroup.com/articles/mobile-tutorials/
- https://www.appcues.com/blog/mobile-permission-priming

Apple guidelines
- https://developer.apple.com/design/human-interface-guidelines/onboarding (read via mirror: https://github.com/incrediblecrab/apple-os-documentation/blob/main/human-interface-guidelines/patterns/onboarding.md)
- https://developers.apple.com/design/human-interface-guidelines/patterns/accessing-private-data/ (page didn't render; guidance taken from search summary)
- https://www.createwithswift.com/liquid-glass-redefining-design-through-hierarchy-harmony-and-consistency/
- https://developer.apple.com/videos/play/wwdc2021/10278/

Videos (not watched; titles, descriptions or third-party summaries only)
- https://www.youtube.com/watch?v=2TlIg3VokY8 (uxpeak) — summaries: https://sozai.app/transcript/ux-psychology-behind-addictive-apps/, https://youtubesummary.com/summary/2TlIg3VokY8
- https://www.youtube.com/watch?v=MXLF8b15GhQ and https://www.youtube.com/watch?v=8mMH6Pq8qnE (Chris Raroque, titles only) — his post: https://notes.chrisraroque.com/p/what-surprise-and-delight-actually
- https://www.youtube.com/@TimGabe, https://www.youtube.com/watch?v=uw0Y_FiKkYQ (titles only) — third-party distillation: https://github.com/bixxter/app-growth-design
