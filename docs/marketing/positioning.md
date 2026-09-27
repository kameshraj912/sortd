# Sortd positioning brief

Written 27 Sep 2026. Draft only — nothing here is posted, sent or deployed. Sources:
`docs/marketing/tagline-and-copy-review.md` (five reasoned personas, seventeen slogans
scored, two subtitles scored), `docs/marketing/founder-note.md`, `CLAUDE.md`,
`site/index.html`, and the onboarding/Settings Swift files listed in the brief.

---

## 1. Core USP

**Sortd logs your Apple Pay taps by itself, free, no bank login or account.** (14 words)

## 2. Target audience profiles

Drawn straight from the five personas in `docs/marketing/tagline-and-copy-review.md`
(reasoned personas built from Sortd's stated audience, not real users — the review says
so itself, and I'm keeping that hedge).

**Primary — the tap-and-forget spender.** Mia, 20, Melbourne student: taps for
everything, cash almost never touches her hands, skims fast, likes dry jokes, and has
"never had a 'real' bank relationship to distrust." Ben, 23, has never finished a budget
and calls money apps preachy — any hint of "you should" closes the app on him. Nurul, 29,
a Singapore nurse on rotating shifts, reads things half-asleep and wants the plainest
possible sentence, no patience for cleverness at 6am. None of the three need the
bank-trust pitch spelled out; what moves them is speed, plain words and zero lecturing —
their scores barely move between slogans with or without a privacy line.

**Secondary — the trust-first payer.** Daniel, 34, works Sydney ⇄ Singapore with cards in
two countries and is "suspicious of anything vague about where data goes." Grace, 45,
quit a bank-linking app over its password screen and is the most guarded reader in the
set: anything that doesn't say "no bank login" out loud gets a raised eyebrow. Both gave
the line "Where your money went. No bank login." the top score of everything tested (5/5
each) — proof the privacy line has to be said early, not left for the FAQ (see §6).

## 3. Before & After

**Before (five words):** Confused, guilty, behind, overwhelmed, suspicious.
Two lines: They open their banking app once a month and wince at the total. They've
tried two budget apps and a spreadsheet, and all three died before the year's second
month.

**After (five words):** Aware, caught-up, unbothered, current, informed.
Two lines: They open Sortd and the coffee's already there — no typing, no bank password
ever asked for. The subscription that quietly put its price up gets caught before it
charges them again.

## 4. Top 3 marketing angles

**1. It logs itself.**
Hook: Your spending shows up before you've put your phone away.
Caption: "Pay with Apple Pay. Sortd writes it down before you've put your phone away.
(Your spreadsheet is still loading.)"

**2. No bank password, ever.**
Hook: Sortd tracks spending without ever asking for your bank login.
Caption: "Most budgeting apps want your bank login. Weird ask. Sortd just watches the
Apple Pay tap instead."

**3. The subscription you forgot.**
Hook: Sortd finds the subscription still quietly charging you every month.
Caption: "You have at least one forgotten subscription. Sortd finds it before it charges
you again. (Row 4. It's always row 4.)"

## 5. Landing page copy — three H1 + H2 pairs

**A. (the persona-review winner — scored 22/25 across all five personas in
`docs/marketing/tagline-and-copy-review.md`, beating sixteen other candidates outright.
7 words, one over the "under seven" guide below; kept anyway, since the review's own
recommendation is "don't change it anywhere.")**
H1: Tap to pay. Sortd writes it down.
H2: No bank login, no account needed. Your purchases stay on this iPhone.

The review assumed the site already carried this line or a close variant — it doesn't.
`site/index.html`'s hero H1 today reads "Tap to pay.<br>Already logged.", not this exact
line. See `copy-audit.md`'s site H1 row for the fix and why it isn't a simple
same-length swap.

**B.**
H1: Your spending, logged by itself. (5 words)
H2: Every Apple Pay tap lands in the list, seconds after you pay.

**C.**
H1: Stop guessing where it went. (5 words)
H2: Sortd catches the coffee, the delivery and the subscription you forgot — without you
typing a thing.

## 6. The biggest objection

**Trust: "there must be a catch, or you'd want my bank login like everyone else."**
This is Grace's objection by name. `docs/marketing/tagline-and-copy-review.md` has her
score the current slogan a 3/5 specifically because "it doesn't tell me if it wants my
bank password," then give the alternate line "Where your money went. No bank login." a
5/5: "Finally — this is the sentence I needed to see first, not buried in the FAQ."
Daniel (the AU↔SG mover) reacts the same way to that same line: "This is the one.
Directly answers 'can I trust this with two countries' banks'." `site/index.html`'s own
FAQ agrees without meaning to — it leads with three straight trust questions ("Does Sortd
connect to my bank?", "What's the catch?", "So how do you make money?") before a single
feature question, which only makes sense if trust is what's stopping the tap from
becoming a download.

**Exact copy to answer it:**

- **Site** (hero or privacy section): "No bank login, ever. No account needed to start.
  Your purchases stay on this iPhone — we don't store them on any server, so there's
  nothing about your spending for us to leak, sell or lose."
- **App Store description** (replaces the current overclaiming line — see
  `copy-audit.md` row 1): "Purchases stay on your iPhone."
- **In the app** (already true, already shipping — `SetupCopy.welcomePrivacy` on the
  welcome screen): "No bank login" / "Your purchases stay on your iPhone." No change
  needed; it's already the answer to this exact objection, first screen someone sees.

**Claims checked against `CLAUDE.md` and the brief's "Always true" list:** no bank login,
no account needed, purchases stay on the phone (never "everything"/"nothing"), opt-out
usage counts and crash reports do leave the phone, an optional encrypted iCloud copy
exists, the account Worker only deletes accounts, Apple Pay taps log after one Shortcuts
setup with the known Apple-trigger timeout, and the app is free with no Pro tier today.
None of the copy above uses "absolute privacy," "nothing ever leaves your phone,"
"frictionless," "seamless," "effortless," "financial clarity," "take control," or
"philosophy."
