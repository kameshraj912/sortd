# Copy moved from the app to the website

Task: `copy-cut`. The app screens listed here used to carry long explanatory
text (bullet lists, data-flow essays, multi-sentence footers). Each screen now
shows one short line, with a "Learn more" link (or the existing Privacy
Policy link) pointing at the site. The site is being redone separately — this
is the handoff list of what needs a home there, and under which anchor.

The in-app source for each paragraph is still in git history
(`Spend/Views/DataControlsView.swift`, `Spend/Views/Settings/*.swift`) if the
exact old wording is needed.

## sortd.page/privacy (no anchors needed — it's the whole page)

From `PrivacyView` (Settings › Privacy & Security › Privacy):

- **Stored on this iPhone** — Purchases, cards and settings are stored only
  on this iPhone. There's no Sortd server or account.
- **Gmail, read on this iPhone** (Gmail builds only) — Sortd only looks for
  receipts and bank alerts. Nothing is copied to a server or shared.
  Disconnect any time.
- **Google sign-in kept safe** (Gmail builds only) — Your Gmail sign-in is
  kept in the iPhone Keychain, Apple's secure storage.
- **No bank logins** — Sortd never asks for your bank username or password.
- **Only the last 4 digits** — Cards are matched by their last 4 digits.
  Full card numbers are never asked for or stored.
- **Exchange rates** — Daily rates come from frankfurter.dev. Only currency
  codes and dates are sent.
- **No ads, no tracking** — No advertising, no tracking across other apps or
  sites, and nothing is sold or shared.
- **Good to know** — Sortd isn't a bank, can't move money and doesn't give
  financial advice. Amounts come from Apple Pay, receipts and what you type,
  so check your bank statement for exact figures.

## sortd.page/help#app-lock

From `PrivacySecuritySettingsView`, the Security section footer:

> With the lock on, Sortd locks when you open it or come back after a
> minute. Widgets hide amounts on the Lock Screen and in StandBy unless Show
> Amounts When Locked is on.

## sortd.page/help#stays-on-iphone

From `PrivacySecuritySettingsView`, the "Stays on This iPhone" rows:

- **Your setup answers** — Kept only on this iPhone. They choose your setup
  steps and check-in time. Change them in Help & Feedback › Run Setup Again.
  Delete All Data removes them.
- **Notifications** — Made on this iPhone, with no push server. Your
  check-in never shows amounts. Bill reminders show the shop and amount.
- **Apple Intelligence** — Where your iPhone has it, reads what you type,
  scan or get in a receipt email, on this iPhone. Nothing is sent anywhere.
  Check what it fills in.
- **Widgets** — Show a summary kept on this iPhone. Only Sortd and its
  widgets can open it.

## sortd.page/help#icloud-backup

From `BackupDataSettingsView`, the iCloud section footer:

> Your purchases are encrypted on this iPhone before they go to your
> iCloud. The key stays in your iCloud Keychain, so only your devices can
> read them. On a new iPhone, restore first.

## sortd.page/changelog

`AboutSettingsView` used to be scoped for a "long version history" block
(per the copy-cut brief). No such text was found in the current app —
`AboutSettingsView` only ever showed Purchases/Stored/Version rows, no
history list. Nothing to move here; flagging so the changelog page still
gets built from whatever release-notes source Raj already keeps, not from
app code.

## Other short trims (no separate site copy — just shortened in place)

These lines were already close to one sentence; they were tightened to fit
under ~90 characters without moving anything to the site:

- Currency footer: "Purchases in other currencies are converted to \(home)
  at that day's European Central Bank rate." → "Converted to \(home) at
  that day's European Central Bank rate."
- Bills & Reminders budget footer: dropped the worked example
  ("On track to pass your budget by the 22nd") and the "only if
  notifications are already allowed" caveat → "One alert a month if you're
  on track to pass your budget."
- Backup File footer: "A backup file is a copy you keep yourself: in Files,
  on iCloud Drive, or sent to a new phone." → "A copy you keep yourself: in
  Files, on iCloud Drive, or a new phone."
- Tip sheet line: cut from three sentences to one — "Sortd is free. A tip
  unlocks nothing, it just says thanks."

## From the Apple Pay page (25 Sep 2026)

Handoff notes for whoever next edits `site/`. Each entry: what moved, why, and the
exact change still needed on the site (not made here — this worktree only touches
`Spend/` and `SpendTests/`, per its brief).
## Apple Pay Logging: the by-hand walkthrough (26 Sep 2026)
**Why:** router feel check on `applepay-page` — Raj wants Settings › Purchase
Sources › Apple Pay Logging short and clean. It carried two full picture guides
(the ready-made shortcut, and a by-hand walkthrough for anyone who'd rather build
it themselves); now it shows only the first. The by-hand steps stay useful, so
they move to the support site instead of being deleted.
**Removed from the app:** `WalletSetupGuide(route: .byHand)` (iOS 27) and the
`SetupGuideView` iOS 26 plain-text fallback (`Step`, `legacySteps`) — both are
gone from `Spend/Views/SetupGuideView.swift`. `WalletSetupGuide.swift` itself is
untouched: `.byHand`/`.byHandPages` still compile, just unused in-app for now.
**Where it already lives:** `site/support.html` already has a "By hand" `<h3>`
under `<h2 id="apple-pay">` with the same seven steps (added earlier, ahead of
the app's own copy — see the section starting `<h3>By hand</h3>`). It only needs
one change:
```html
<h3 id="apple-pay-manual">By hand</h3>
```
(currently `<h3>By hand</h3>`, no id). That makes `https://sortd.page/support#apple-pay-manual`
a direct link to it, matching the anchor named in the router's note. Content is
otherwise already correct and doesn't need rewriting — check it against
`Spend/Views/WalletSetupGuide.swift`'s `byHandPages` if the in-app steps ever
change, since the two can drift.
