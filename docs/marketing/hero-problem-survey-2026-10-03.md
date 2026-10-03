# Hero problem survey: what people struggle with, and eight hero options

Written 3 Oct 2026. Draft only. Nothing here is posted, sent or deployed. No other file was edited.
All web pages were read on 3 Oct 2026. Built on `tagline-and-copy-review.md` (the five-persona
review), `positioning.md`, `brand-voice.md`, `copy-audit.md` and the live hero in `site/index.html`.

**The ask (Raj):** the top of sortd.page should speak to the real problem people have, not only
describe the mechanism. Evidence first, then options.

**Short answer.** People already have budgets. What breaks is feeding them. Tapping makes spending
easy to miss. Typing it in is a chore. Many people will not hand a budget app their bank login.
Sortd fixes those three well. It fixes forgotten subscriptions only in part.

---

## Part 1. Market survey

How sure: **High** = I opened the page and read the number. **Medium** = I opened it, but it is
old, comes from another country, or is a vendor's own survey. **Low** = a forum post, one data
point, or a search summary only. **Not verified** = I could not open the source.

### 1a. Contactless and Apple Pay make spending easy to miss

| Finding | Number | Source | Year | Sure? |
|---|---|---|---|---|
| Australians use phone wallets more every survey. | 43% used a phone to pay contactless in the diary week (35% in 2022). Phone payments are about 40% of card payments (31% in 2022). Over 50% of 18-29s used mobile payments. Cash is about 15% of payments. | [RBA Bulletin, May 2026, Consumer Payment Behaviour in Australia](https://rba.gov.au/publications/bulletin/2026/may/consumer-payment-behaviour-in-australia.html) | 2025 survey | High |
| After people start paying by phone, card spending goes up. | 9.4% more charged to cards after adopting mobile payments (Chinese bank data, one study). | [NPR / Michigan Public, 7 Apr 2024](https://michiganpublic.org/2024-04-07/using-your-phone-to-pay-is-convenient-but-it-can-also-mean-you-spend-more) | 2024 | Medium (China, not AU/SG) |
| Some tap users say they lose track. | 17% of UK contactless users said tap-to-pay makes them lose track of spending. Sample size not stated. | [NFCW on a GoCompare survey](https://www.nfcw.com/?p=57890) | 2018 | Medium (UK, old) |
| Singapore wallet share. | 56% of Singaporeans used mobile contactless (n=511). I found nothing newer. | [Visa Singapore study](https://sg.review.visa.com/about-visa/newsroom/press-releases/more-than-half-of-singaporeans-use-mobile-contactless-payments-visa-study.html) | 2019 | Medium (old) |
| People forget what they paid by card (a known study by Soman). | Not checked. | Search summaries only | 2001-2003 | **Not verified** |

### 1b. Budgets fail at the feeding stage, not the starting stage

| Finding | Number | Source | Year | Sure? |
|---|---|---|---|---|
| Most Australians say they have a budget. Many run it by hand. | 63% have a 2026 budget (18-24: 62%, 25-34: 84%). 45% use manual spreadsheets, 28% budgeting apps. | [YouGov Australia, Financial Outlook 2026](https://yougov.com/articles/54318-australian-financial-outlook-2026-how-consumers-plan-to-budget-save-and-spend) (n=1,015, 12-16 Feb 2026) | 2026 | High |
| People with a budget still break it. | 84% of US adults with a monthly budget say they have sometimes gone over. | [NerdWallet / Harris Poll](https://www.nerdwallet.com/finance/learn/data-2023-budgeting-report) (n=2,000+) | 2023 | Medium (US) |
| Money apps turn into a chore. People name manual entry, category upkeep and guilt-style alerts. | No number. One forum thread. | [Product Hunt thread, "What's the money app you rage-quit"](https://www.producthunt.com/p/general/what-s-the-money-app-you-rage-quit-and-what-finally-did-it) | 2026 | Low |
| "Most people quit in the first month." | Found as a claim on blogs. I could not tie it to a study, so I do not use it. | n/a | n/a | **Not verified** |
| Singapore young adults: they have a rough idea of spend and still worry. | 8 in 10 have a rough idea of monthly spend. Still worried about overspending. (n=2,001, ages 21-39.) | [IPS Singapore poll, via Asia News Network, 15 Apr 2024](https://asianews.network/younger-singaporeans-financially-prudent-but-some-buy-things-to-be-happy-ips-poll/) | 2022 fieldwork | High |
| Singapore young adults say money admin takes time. | 64% say managing money takes a lot of time. 38% say it is complicated. (About 1,000 young adults.) | Via search summary of a DBS release. I did not open it. | Year not confirmed | **Not verified** |
| Young Australians feel stress about money. | 51% of 15-21s "often feel stressed about money" (n=3,000). | [ASIC media release](https://asic.gov.au/about-asic/news-centre/find-a-media-release/2022-releases/21-052mr-asic-helps-young-people-get-moneysmart/) | 2021 | High (teens, old) |

**Warning from this table.** The site's "Why Sortd exists" note says "Most people have no idea where
their money went last month." I found no source for it. The Singapore poll above points the other
way: most young adults say they have a rough idea, and worry anyway. A hero that says "you have no
idea" would be wrong for half our market. "Where did it go?" works if it means "exactly where".

### 1c. Subscription creep

| Finding | Number | Source | Year | Sure? |
|---|---|---|---|---|
| Half of Australians pay for something they do not use. | 50% pay for unused subscriptions (n=1,015). Gym is the costliest (about $1,116 a year). Netflix is the most named (57%). | [Compare the Market, published 9 Jun 2026](https://www.comparethemarket.com.au/news/wasted-subscriptions-2026) | Mar 2026 | Medium (a vendor's survey) |
| Forgotten or unused scheduled payments cost real money. | 39% of people with scheduled payments say some are forgotten or unused. Average $105 a month. 9 months on average to cancel. | [ING Australia, YouGov survey (n=1,075)](https://helphub.ing.com.au/financial-health/aussies-could-save-1261-a-year-by-cutting-back-on-unused-or-forgotten-subscriptions/) | Dec 2022 | Medium (a bank's survey, old) |
| Singapore forgotten-subscription number. | Not found. | n/a | n/a | **Not verified** |

### 1d. Trust: bank logins and data

| Finding | Number | Source | Year | Sure? |
|---|---|---|---|---|
| Australians worry about data breaches. | 75% call data breaches one of the biggest privacy risks. 47% were told their data was in a breach in the past year. (n=1,916.) | [OAIC Privacy Survey, March 2023](https://www.oaic.gov.au/newsroom/data-breaches-seen-as-number-one-privacy-concern-survey-shows) | 2023 | High |
| Australians were unwilling to share financial data with non-banks. | 66% unwilling. 84% would trust only their bank. Sample size not stated. | [Technology Decisions on an Accenture survey](https://technologydecisions.com.au/content/it-management/article/australians-wary-of-open-banking-61787329) | 2018 | Medium (old) |
| A Singapore user avoids bank access in his own words. | "I prefer to DIY than to let Dobin access my bank info." | [Seedly community thread, 18 Dec 2025](https://seedly.sg/posts/the-seedly-expense-tracker-app-is-being-sunset-what-are-some-good-alternatives-free-or-not/) | 2025 | Low (one person) |
| Bank-login aggregators have drawn lawsuits. | Plaid agreed to pay $58m over claims it took login data and more than users expected. Final approval 20 Jul 2022 (US). | Search summary of a law firm page (Lieff Cabraser) and others. I did not open it. | 2022 | **Not verified** |
| Australia is moving against screen scraping. | A government "ban" plan, called "fundamentally unsafe". | Search summary only. | n/a | **Not verified** |

### 1e. Two currencies, travel, many cards

I found **no solid number** for tracking trouble with two currencies or several cards. One search
summary said 49.1% of international students in Australia worry about their finances. I did not open
it (**not verified**) and it is not about currencies. Use "every card, every currency" as a proof
point lower on the page, not as a hero.

### 1f. What people say in their own words

Thin, and I want to say so. Reddit blocked me. The mirrors and old.reddit.com returned 403 or were
refused. The App Store review feed returned no review text. So these are **not verified** unless
marked.

- r/AusFinance, "How do you track your expenses?" (2024). Search summary only: one person found
  tracking every expense in Excel too tedious and set a weekly allowance instead. Not opened.
  Thread: `reddit.com/r/AusFinance/comments/1cvnqsi/`
- r/ynab, "I lasted 6 months" (Jun 2024) and "How do I stick to YNAB" (Aug 2024). Search summary
  only: entering transactions by hand wore people out. Not opened.
- Product Hunt thread (linked above): money apps become a chore, categories need upkeep,
  alerts feel like a scolding. Opened. Low confidence (one thread, summarised by a tool).
- Seedly community (linked above, opened): a Singapore user prefers DIY to bank access. The same
  thread says Seedly's expense app is being sunset (posted 18 Dec 2025). A SingSaver list updated
  17 Apr 2026 still shows Seedly as available. They disagree, so **do not mention Seedly's status
  anywhere**.
- Rocket Money on Trustpilot (about 3.3 to 3.5 stars, with complaints about bank links looping and
  hard cancellation): search summary only. Not opened.

### 1g. Competitor headlines (read 3 Oct 2026)

| Who | Headline (and subline) | Problem it names |
|---|---|---|
| [Copilot](https://www.copilot.money/) | "Your money, beautifully organized." "...automatically tracked." | Mess. Generic. |
| [YNAB](https://www.ynab.com/) | "Do you worry about money?" "Get YNAB. Get good at money." | Worry. Skill. (Preachy for some.) |
| [Monarch](https://www.monarch.com/) | "The modern way to manage your money" | None. |
| [Rocket Money](https://www.rocketmoney.com/) | "The money app that works for you" ("...take back control of your financial life.") | None in the headline. Control in the subline. |
| [PocketGuard](https://pocketguard.com/) | "Know where your money is going with the PocketGuard budget app" ("...links your accounts") | "Where did it go?" With a bank link. |
| [WeMoney](https://wemoney.com.au/) | "Crush your debt" | Debt. |
| [Frollo](https://frollo.com.au/) | "Feel good about money" (the page now speaks to businesses and brokers) | A feeling. |
| [Up](https://up.com.au/) | "Life's better on the Upside" | None. |
| [Beem](https://www.beem.com.au/) | "Tap less. Get more." | None clear. |
| [Spendee](https://www.spendee.com/) | "The only app that gets your money into shape" | None. |
| [Finny](https://getfinny.app/) | "Stop typing your transactions." "Apple Pay purchases record on their own... No bank linking, ever." | **Typing. Apple Pay. No bank link. Same space as Sortd.** |
| Seedly | "Welcome to Seedly!" (a community page) | None. |

Not verified: Dobin (site would not load), MoneyCoach and Revolut (see the tagline review).

**What the table says.** Most big names sell a mood ("organized", "modern", "feel good"). Two name a
problem: PocketGuard ("where is it going") and Finny ("stop typing"). **Finny is a direct rival**
with the same trick: Apple Pay logging with no bank link. It is a vendor's own site, so I treat
its claims as theirs. Do not copy "Stop typing". Say it another way.

---

## Part 2. The problems, ranked

Scores are 1 to 5 and are **my judgment, not data**. Score = People x Fix x Few rivals (max 125).
People = how many have it, by the evidence above. Fix = how well Sortd fixes it today.
Few rivals = how few competitors already own it (5 = nobody).

| # | Problem | People | Fix | Few rivals | Score |
|---|---|---|---|---|---|
| 1 | **Tap and forget.** Phone payments are over 40% of card payments in Australia. They hurt less, so the spending is easy to miss. | 5 | 5 | 3 | 75 |
| 2 | **"I will not give an app my bank login."** 75% worry about breaches. Bank-link apps are the norm. | 4 | 5 | 3 | 60 |
| 3 | **Typing every purchase is a chore.** 45% run budgets in spreadsheets. Forums keep naming manual entry. | 4 | 4 | 2 | 32 |
| 4 | **Finding out after you went over.** 84% of US budgeters say they have gone over. Sortd has a pace alert. | 4 | 3 | 2 | 24 |
| 5 | **The subscription you forgot.** 50% pay for something unused. Rocket Money and banks already own this. | 5 | 3 | 1 | 15 |

Why each fix score:
- **1 (Fix 5):** Sortd logs the shop, amount and card after a tap. Caveat: Apple's trigger can miss a
  tap (radars FB14035016 / FB16379100), so never say "every".
- **2 (Fix 5):** No bank login. Purchases stay on the iPhone. Rivals 3, not 4: Finny, YNAB manual mode
  and others also skip bank links.
- **3 (Rivals 2):** Finny owns the exact line. Big apps fix typing with bank links instead.
- **4 (Fix 3):** The pace alert only knows what is logged. Cash is not logged.
- **5 (Fix 3):** Sortd finds repeats in what it has logged. A subscription billed to a card outside
  Apple Pay only shows up if you import a statement.

Honourable mention: two currencies and many cards. Real feature, no evidence of how many people
have the pain. Keep it as a proof point.

### Two problems Sortd does NOT solve (do not promise these)

1. **"I want to see all my spending."** Cash and cards not in Apple Pay stay invisible unless added by
   hand, with the camera or from a statement (Known gaps, `CLAUDE.md`; site FAQ). So no "all", no
   "every", no "the full picture". Android users also can't use Sortd.
2. **"I want to spend less" or "I'm in debt."** Sortd shows the money. It does not change the habit,
   cut a bill or pay off a card. No "save more", no "crush debt", no "get good with money". That is
   YNAB's and WeMoney's ground, and it is the preachy tone Ben dislikes in the review.

Also never imply the data is safe if the phone is lost.

---

## Part 3. Hero options

Rules used. Plain words. Dry. No exclamation marks. None of: frictionless, seamless, effortless,
unlock, take control, financial freedom, journey, empower. "Free" only, never "free forever".
"Consider it Sortd." is the second line only, or under the buttons. "You've been Sortd." is not used
(it is for the moment a purchase logs). Never "Get Sortd". "Apple Pay taps", never "every tap".

**Fit check.** Each headline line is 18 characters or fewer, counting spaces and punctuation. The live
line "Consider it Sortd." is exactly 18, so these should fit at 42px if that one does. **Not tested in
a browser.** Raj, check on a real phone.

**Not reused from the review's rejected list:** "Every tap, written down", "remembered/remembers",
"takes note", "Pay. It's written down", "keeps the receipts", "Tap. Done. Noted." Option 3's idea is
close to reserve line H ("No bank login") and option 7 uses "Tap to pay." as the review's winner did.
Both on purpose.

### Problem-led (3)

**1. Where did it go?**
- Eyebrow: Apple Pay tracker
- Headline: `Where did it go?` / `Consider it Sortd.`
- Support: Tapping is so quick it barely feels like spending. Sortd logs your Apple Pay taps, so the list is there when you wonder. (23 words)
- Problem: 1 (tap and forget).

**2. Spreadsheets want a row per coffee.**
- Eyebrow: Free spending tracker
- Headline: `Spreadsheets want` / `a row per coffee.`
- Support: Sortd logs your Apple Pay taps by itself, so there is nothing to type. Receipts take one photo. Statements import. (20 words)
- Problem: 3 (typing). Roasts the chore and the market, not the person. Close to Finny's idea but not its words.

**3. Budget apps want your bank login.**
- Eyebrow: iPhone spending tracker
- Headline: `Budget apps want` / `your bank login.`
- Support: Sortd doesn't. It logs your Apple Pay taps instead, and your purchases stay on your iPhone. (16 words)
- Problem: 2 (trust). Note: "Budget apps want" is a wide claim. True of the big ones I opened (PocketGuard says "links your accounts"). Not true of YNAB manual mode or Finny. The voice file already makes this joke.

### Outcome-led (2)

**4. Open Sortd. Coffee's logged.**
- Eyebrow: Free for iPhone
- Headline: `Open Sortd.` / `Coffee's logged.`
- Support: Sortd logs your Apple Pay taps, so a month of spending is a list you can read, not a guess. (20 words)
- Problem: 1, and the "where did it go" feeling. Shows the result in four words.

**5. Know before it renews.**
- Eyebrow: Bills and budgets
- Headline: `Know before` / `it renews.`
- Support: Sortd spots payments that repeat, shows what is due and what it costs a month, and warns you when spending runs ahead of budget. (24 words)
- Problem: 5 and 4. Weakest on mute. It does not say Apple Pay or tap, so the eyebrow has to.

### Keep "Tap to pay." and add the problem in the support line (2)

**6. Typing is the boring part.**
- Eyebrow: Spending tracker for iPhone
- Headline: `Tap to pay.` / `Consider it Sortd.` (as live today)
- Support: Typing in purchases is the boring part. Sortd logs your Apple Pay taps, so you skip it. (17 words)
- Problem: 3 (typing).

**7. Weird ask, that bank login.**
- Eyebrow: No bank login
- Headline: `Tap to pay.` / `Consider it Sortd.` (as live today)
- Support: Many apps want your bank password. Sortd logs your Apple Pay taps on your iPhone instead, so there is nothing to hand over. (23 words)
- Problem: 2 (trust). Answers Grace's and Daniel's objection in the review without changing the tested line.

### Wildcard (1)

**8. It was takeaway.**
- Eyebrow: Spending tracker
- Headline: `It was takeaway.` / `We checked.`
- Support: Sortd logs your Apple Pay taps with the shop, the amount and the card. So "where did the money go" has an answer. (23 words)
- Problem: 1. "It was takeaway" is already an approved voice line, and "We checked" matches the $5.50 coffee
  joke on the page. Roasts the habit, kindly. Risk: a stranger may not know what the app is until the
  eyebrow and support line.

### My top three

1. **Option 1, "Where did it go? / Consider it Sortd."** It speaks to the top-ranked problem in the
   shortest plain words, keeps the sign-off, and the support line adds the mechanism. **This is the one I would ship.**
2. **Option 7.** The safest change: it keeps the tested "Tap to pay." line and answers the trust
   worry (problem 2) in the first screen. Pick it if Raj wants the least risk.
3. **Option 2.** The funniest line that still names a real chore, and it matches the dry voice
   Mia and Ben liked in the review. Pick it if Raj wants more personality than safety.

Why not the others. 3 is sharp but its claim is wide. 4 and 8 depend on the support line to explain
the app. 5 does not name the mechanism. 6 is fine but plain, and close to Finny.

---

## Claims checked

- **Free.** `CLAUDE.md` ("Everything is free forever" is internal; the copy says only "free").
  Support lines say nothing about price. No Pro, no tip-jar mention.
- **No bank login, purchases stay on the iPhone.** `CLAUDE.md` and `brand-voice.md` "Always true". I
  wrote "purchases", not "everything", per `copy-audit.md`.
- **Apple Pay logging.** "Logs your Apple Pay taps". Never "every". Apps and websites on iOS 27 are
  left out of the hero (they need a Wallet notification), as in the site FAQ.
- **Receipts "take one photo", statements import, pace alert, repeat-payment detection.** Taken from
  the brief and the site FAQ. Not re-tested in the app.
- **No invented numbers.** Every number above has a link. Support lines contain no statistic.

## Needs Raj

- Pick a hero, or ask for a tweak. I did not touch `site/`.
- Look at the winner on a real phone at 42px, both lines.
- Decide what to do with "Most people have no idea where their money went" and "most budgets die by
  February" on the page. I found no source for either. The Singapore poll cuts against the first.
  I did not edit them.
- Finny is a rival with a near-identical trick. Worth knowing before launch posts.

## Not verified

- Every Reddit thread (blocked), and every App Store review (feed gave no text). Reddit and
  Trustpilot items above are search summaries.
- The DBS 64% / 38% figures, the Plaid $58m figure, the Australian screen-scraping ban plan, the
  international-student 49.1% figure, and the Soman memory study. Search summaries only.
- Dobin, MoneyCoach and Revolut headlines.
- Whether Seedly's expense app is shut down (sources disagree).
- Singapore subscription and current wallet-share numbers (not found).
- Headline fit at 42px on a real phone.
- Any claim in Finny's marketing (their own site).
