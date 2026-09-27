# Copy audit — first ten minutes, About, and the website

Written 27 Sep 2026, against `docs/marketing/positioning.md` and
`docs/marketing/tagline-and-copy-review.md`. Draft only. Rewrites are the same length or
shorter, plain words, and checked against `CLAUDE.md`'s current truth (everything free, no
Pro tier; purchases stay on the phone; usage counts/crash reports are opt-out; optional
encrypted iCloud copy; the account Worker only deletes accounts; Apple's Wallet trigger can
time out).

| Where | Current line | Verdict | New line | Why |
|---|---|---|---|---|
| `docs/AppStoreListing.md:27` (Description, first paragraph) | "...No typing, no bank login, no account. Everything stays on your iPhone." | **rewrite** | "...No typing, no bank login, no account. Purchases stay on your iPhone." | "Everything" is the overclaim the brief bans in its positive form — usage counts, crash reports and the optional iCloud copy do leave the phone. First paragraph of the description: highest-reach line in the whole listing. |
| `docs/AppStoreListing.md:21` (Promotional text) | "Pay with Apple Pay and Sortd writes it down. No bank login, no account, nothing leaves your iPhone." | **rewrite** | "Pay with Apple Pay. Sortd writes it down. No bank login, no account. Purchases stay on your iPhone." | Same overclaim ("nothing leaves your iPhone") in the field every App Store visitor reads before deciding to download. Same length (99 chars either way, hand-counted — recount with `check_listing.py`). |
| `docs/AppStoreListing.md:53` (PRIVATE BY DESIGN) | "Your purchases are stored on your iPhone. We never see them, so we can't sell them or lose them." | **rewrite** | "Your purchases are stored on your iPhone. We never see them, so we can't sell them." | "So we can't... lose them" reads as "your data is safe" — untrue if a phone is lost with iCloud backup off (no other copy exists). The brief says never imply that. Shorter, drops the risky half, keeps the true half. |
| Welcome screen wordmark subtitle (`SetupCopy.new[.welcome]`, `SetupPages.swift:184`) | "Hi. Let's get your spending to log itself." | keep | — | True, plain, first line every new user reads. |
| Welcome feature row 1 (`OnboardingView.swift:661`) | "Apple Pay logs itself" / "Pay as usual. It shows up in a second." | rewrite | "Apple Pay logs itself" / "Pay as usual. It shows up in seconds." | "A second" is falsely precise next to the App Store copy's own "a few seconds," and Apple's own trigger can time out (`ApplePaySetupPanel`'s own caveat). Same length, drops one word. |
| Welcome feature row 2 (`OnboardingView.swift:662`) | "Every card, every currency" / "Converted at the day's rate." | keep | — | True (ECB daily rate), plain. |
| Welcome feature row 3 (`OnboardingView.swift:663`) | "Bills, seen coming" / "Know what's due before it's charged." | **rewrite** | "Bills before they hit" / "Know what's due before it's charged." | `docs/marketing/tagline-and-copy-review.md` tested this exact line: Mia and Nurul both stumbled on "seen coming" before reaching the detail line — it "reads like a typo or a riddle on first pass, not a benefit." The review's own plainer rewrite, same beat count, same detail line underneath. |
| Welcome feature row 4 / `SetupCopy.welcomePrivacy` (`OnboardingView.swift:664`) | "No bank login" / "Your purchases stay on your iPhone." | keep | — | The persona review flagged the *old* title here, "Private by design" (Mia: "sounds like it's from a pitch deck"; Ben: reads as a buzzword), and recommended dropping it for exactly this wording — "No bank login" is already in the code today. Already fixed; nothing to do. |
| Account / sign-in page, "Keep it yours." (open branch `onboarding-signin`, PR #84 — not merged into this worktree) — title | "Keep it yours." | keep | — | Short, plain, no claim to check. Fine as a page title once merged. |
| Same page — subtitle | "Optional. Two taps, no password." | keep (wording); claim **not verified** | — | Plain, and "no password" matches Sign in with Apple/Google (true, matches `site/index.html`'s "only if you want to" framing). "Two taps" is a specific interaction claim I can't check — PR #84's code isn't in this worktree, so it's not verified either way, not necessarily wrong. |
| Same page — row 1 | "Help that knows you" / "Ask a question and Sortd knows which install is yours." | **rewrite** | "Help that knows you" / "Ask a question and Sortd knows it's your phone." | "Install" is developer/analytics jargon, not a word a 12-year-old would use for "your copy of the app" — Raj's plain-words rule. Same length, same meaning, ordinary word. |
| Same page — row 2 | "Your iCloud copy, tied to you" / "Restore on a new iPhone with one tap." | keep | — | Matches the existing `CloudBackup`/"Restore from iCloud" button in `OnboardingView.swift` (one button, one tap to start) and the true "optional encrypted iCloud copy" claim. Not fully verified whether restore ever needs a second prompt (Face ID, iCloud sign-in) — PR #84's code isn't here to check. |
| Same page — row 3 | "Nothing else changes" / "Your purchases stay on this iPhone. Sortd has no account server." | **rewrite — factual error** | "Nothing else changes" / "Your purchases stay on this iPhone. Signing in doesn't change that." | **"Sortd has no account server" is false.** `CLAUDE.md` states plainly: "the account Worker (`worker/`) that only deletes accounts" — that Worker *is* an account server, and a sign-in page almost certainly talks to it. This is the kind of claim that gets an app rejected or just gets caught out by one skeptical Daniel-or-Grace reader. Fix sidesteps the false claim entirely rather than trying to define what the server does; shorter (9 words vs 11), still true, still lands the "nothing changes for your purchases" point. **Flag before PR #84 merges** — it isn't live yet, so it's not in the "Do first" list below, but it will be as soon as it ships. |
| Goals question (`SetupPages.swift:228`) | "What should Sortd help with?" / "Tap any that fit. Not sure? Just continue." | keep | — | Plain, no claim to check. |
| Payment question (`SetupPages.swift:251`) | "How do you usually pay?" / "So the right things get set up first." | keep | — | Plain, no claim to check. |
| Feeling question (`SetupPages.swift:273`) | "How does your spending feel lately?" / "No wrong answer. It just sets the tone." | keep | — | Plain, matches the "roast the habit, never the person" rule — this is the one screen that could tip into judging someone, and it doesn't. |
| Check-in question (`OnboardingView.swift` `.checkIn` case) | "When should we check in?" / "One short note. We'll ask about notifications later, not now." | keep | — | True to the new flow (permission ask moved to the Activation card on Home). |
| Plan page (`SetupPages.swift:409`) | "Here's your Sortd" / "All set from your answers. The rest can wait." | keep | — | Plain, true. |
| Plan page privacy footer (`SetupCopy.planPrivacy`) | "Your purchases stay on this iPhone. Sortd never asks for your bank login." | keep | — | Exactly the true form the brief asks for; no "nothing"/"everything." |
| Cards page (`OnboardingView.swift:814`) | "Your cards" / "Tap each bank you pay with. Fine to skip for now." | keep | — | Plain, true (skip is real in the new flow). |
| Apple Pay Logging panel header (`OnboardingView.swift:1077`) | "Log Apple Pay by itself" / "About a minute, once. Or do it later from Home." | keep | — | True to the one-shortcut setup; doesn't promise every tap. |
| Apple Pay Logging timeout note (`ApplePaySetupPanel.swift:148-149`) | "Sortd sees when a tap arrives, not your automation." / "Apple's trigger sometimes misses a tap, most often at vending machines, transport gates and parking." | keep | — | This is the model line — it's the one place in the app that states the Apple radar caveat plainly. Nothing to change. |
| Finish Setup card rows (`SetupChecklist.tasks`, not in the file list read for this brief) | — | **not verified** | — | Row titles/details live in `SetupChecklist.swift`, which this brief didn't list and I didn't open. The card's own chrome ("Finish Setup", "X of Y done") is plain and needs no change. |
| Activation card headline (`ActivationCard.swift:40`) | "Logged by itself. That's Sortd working." | keep | — | True, plain, the exact moment the aha-card is meant to land. |
| Activation card ask line (`ActivationCard.swift:22-27`) | "Want a check-in each morning?" / "...each evening?" / "Want a Sunday recap?" | keep | — | Plain, matches what's actually scheduled. |
| Settings › About tagline (`AboutSettingsView.swift:28`) | "Tap to pay. Sortd writes it down." | keep | — | Matches positioning §5's tested winner already — don't touch. |
| Help & Feedback (`HelpFeedbackSettingsView.swift`) | No intro paragraph exists; closest is the footer "Setup again keeps your purchases and cards." | keep | — | No headline copy to rewrite; the one footer line present is true and plain. |
| `site/index.html:6` `<title>` | "Sortd Money – Apple Pay spending tracker for iPhone" | keep | — | Plain, true, no claim beyond the fact of what it does. |
| `site/index.html:16` `og:description` | "Pay with Apple Pay and the purchase shows up in Sortd by itself. Receipts, subscriptions and every currency in one list, stored on your iPhone." | keep | — | Scoped to purchases, not "everything" — no overclaim. |
| `site/index.html:71` H1 | "Tap to pay.<br>Already logged." | **flag, not a mechanical rewrite** | Tap to pay.<br>Sortd writes it down. | Positioning §5 says this line won the persona review, so the two don't match today. Going from ~4 words to 7 breaks the "same length or shorter" rule for a straight rewrite — this is a call for Raj, not something to silently swap in. |
| `site/index.html:72` lead paragraph | "Seconds after every Apple Pay tap, Sortd has the shop, the amount and the card. You were never going to type in that $5.50 coffee anyway..." | keep | — | Real number, one joke in the parenthetical, true. |
| `site/index.html:319` privacy H2 | "We can't sell your spending. We never see it." | rewrite | "We can't sell your purchases. We never see them." | Not untrue, but "spending" and "it" are vaguer than the word this whole brief and the app itself use ("purchases"). Same length, closes the "what about the other data" reading a skeptical reader might reach for. |
| `site/index.html:344` pricing H2 | "Free. No asterisk." / "Every feature, for everyone..." | keep | — | Matches current CLAUDE.md truth (no Pro tier) exactly. |
| `site/index.html:379` FAQ — "Does Sortd connect to my bank?" | "No. It never asks for your bank password, and it never will..." | keep | — | True, directly answers the objection in §6. |
| `site/index.html:380` FAQ — "What's the catch?" | "There isn't one. Every feature is free, there are no ads, and your purchases stay on your phone..." | keep | — | Matches free-app truth; scoped claim ("purchases"), not "everything." |
| `site/index.html:381` FAQ — "So how do you make money?" | "We sell your data. (Kidding. We can't. It's on your phone.)..." | keep | — | Roasts ourselves, not the reader — on-brand, and the joke's premise (we can't sell purchase data) is true. |

## Do first (the five rewrites with the most reach)

1. **App Store description, first paragraph** — "Everything stays on your iPhone" →
   "Purchases stay on your iPhone." Read by every App Store visitor before they scroll.
2. **App Store promotional text** — drop "nothing leaves your iPhone," the same overclaim,
   in the field shown highest on the listing.
3. **App Store "PRIVATE BY DESIGN" bullet** — drop "or lose them"; it implies safety from
   phone loss that isn't true without iCloud backup turned on.
4. **Site hero H1** — bring it in line with the tested "Tap to pay. Sortd writes it down."
   This one needs Raj's call, since the fix is a longer line, not a shorter one.
5. **Site privacy H2** — "spending/it" → "purchases/them," same length, closes a small gap
   a burned-by-bank-linking reader would notice.

**Not ranked above, but urgent before it ships:** PR #84's "Keep it yours." page (branch
`onboarding-signin`) says "Sortd has no account server," which is false against `CLAUDE.md`.
Zero reach today since it isn't merged — but it will be the single most-read line on that
screen the day it is. Fix before merge, not after.

## Not verified

- The subtitle claim "Two taps, no password" on the PR #84 "Keep it yours." page — plausible,
  matches Sign in with Apple's usual flow, but the branch's code isn't in this worktree to
  check the actual tap count.
- Whether the PR #84 iCloud-restore row ("Restore on a new iPhone with one tap") ever needs a
  second prompt (Face ID, iCloud sign-in) — same reason, code not in this worktree.
- Finish Setup card row titles/details: they live in `SetupChecklist.swift`, not opened for
  this brief.
- Character counts for the two AppStoreListing.md rewrites above were hand-counted, not run
  through `docs/check_listing.py` — recount before anyone pastes them into App Store Connect.
