# Copy audit — trim explanatory/technical/disclaimer text (2026-09-22)

Branch `copy-trim`, worktree `Spend-copy`, based on `beta-rc1`.

Goal: keep in the app only (1) what Apple/Google require in-app, (2) short good-practice
notices, (3) plain instructions needed to use a feature. Everything else (how
Keychain/on-device processing/encryption works, reassurance paragraphs, repeated
disclaimers, example lists) is cut or replaced with one short line + a "Learn more" link
to sortd.page, which keeps the full detail.

Required-in-app research (Step 1) is in the session report. Rows below cover every
user-facing string reviewed in `Spend/Views` (incl. `Settings/`), `Spend/Intents`, and
`ProStore.Feature`.

Legend — action: **keep** (required or already short/instructional), **shorten**
(trimmed in place), **remove** (deleted, nothing left), **move-to-web** (cut from app,
already covered by the linked page). "voice: later" marks a shortened line that a
separate brand-voice pass (self-aware, cheeky-but-not-jokey) may rewrite later — this
pass kept every such line short and plain, deliberately without adding any jokes.

| Location | Current text (before) | Action | Reason |
|---|---|---|---|
| `Settings/HelpFeedbackSettingsView.swift` — Get Help footer | "Feedback opens Mail with your app version, iOS version and device model already filled in. Nothing else — no purchases, no account." | **remove** | Explanatory note about a mailto prefill; not required, not an instruction. Pre-filled email itself is kept. |
| `Settings/HelpFeedbackSettingsView.swift` — Online links | Privacy Policy / Support links | **keep** | Required accessible privacy-policy link (5.1.1(i)); support link is good practice. |
| `Views/DataControlsView.swift` (`PrivacyView`) — 7 detail rows (Keychain, frankfurter.dev, Sentry/TestFlight, etc.) | Long per-row technical sentences | **shorten** → few one-line bullets | Owner: privacy screen becomes a short summary + "Read the full privacy policy" link. Technical detail (Keychain, exchange-rate provider, crash-reporting vendor) moves to the website policy, which is not touched and already carries full detail. (voice: later) |
| `Views/DataControlsView.swift` — "Good to Know" paragraph (not a bank, not financial advice…) | 291-char disclaimer paragraph | **remove** | Reassurance/disclaimer paragraph; Terms of Use (linked) covers this. |
| `Views/DataControlsView.swift` — Privacy Policy / Terms links | Links | **keep** | Required (5.1.1(i), 3.1.2 EULA/Terms link). |
| `Views/DataControlsView.swift` — "Read the full privacy policy" | *(new)* | **add** | Owner's explicit instruction for the trimmed privacy screen. |
| `Settings/PrivacySecuritySettingsView.swift` — Security footer | "Sortd locks when you open it, and when you come back after more than a minute. Widgets hide amounts on the Lock Screen and in StandBy unless you turn that on." | **shorten** | Good-practice notice explaining toggle behaviour; kept but tightened. (voice: later) |
| `Settings/PrivacySecuritySettingsView.swift` — Privacy row/footer | "Privacy" / "What Sortd stores, and where." | **keep** | Short, navigational. |
| `Views/PaywallView.swift` — `terms(_:trial:)` renewal line | "…a year. Renews automatically until you cancel in Settings › Apple Account › Subscriptions, at least 24 hours before it renews." | **keep** | Required by 3.1.2: price, period, auto-renew, cancellation. |
| `Views/PaywallView.swift` — Terms / Privacy footer buttons | Links | **keep** | Required (3.1.2: functional links to Terms of Use/EULA and privacy policy). |
| `Views/PaywallView.swift` — betaNote / freeNote / alreadyPro | Short one-liners | **keep** | Already short, functional (beta has no billing; what's free). |
| `Views/GmailViews.swift` — `GmailSection` footer | "Finds bank alerts and receipts (food delivery, rides, app stores, online shops) in your Gmail and reads them on this iPhone." | **shorten** | Drop the example list; keep the read-only/on-device fact. (voice: later) |
| `Views/GmailViews.swift` — disconnect confirmation message | "Sortd stops reading this Gmail and Google cancels its access. Purchases also logged by Apple Pay are kept either way." | **shorten** | Keep the consequence (HIG: explain uncommon/irreversible-feeling actions), tighten wording. (voice: later) |
| `Views/GmailViews.swift` — `ConnectGmailSheet` intro + 4 bullets (Only receipts / Read on this iPhone / Read-only / Stop any time) | ~430 chars across a title, an intro sentence and 4 titled bullets | **shorten** → 3 short lines | Owner: keep the Gmail pre-connect disclosure (Google's "prominent disclosure" before OAuth) but make it 2–3 short lines. Still names what's accessed (receipts/bank alerts), that it's read-only and on-device, and how to stop. (voice: later) |
| `Views/GmailViews.swift` — "Google will show a warning that the app isn't verified yet…" | Footnote | **remove** | Transient, review-status detail, not a policy requirement; goes stale once Google verification completes. |
| `Views/GmailViews.swift` — `GoogleButtonLabel` | "Continue with Google" + G mark, Google's colors/spacing | **keep** | Required by Google Sign-In branding guidelines (verification checks this). |
| `Views/OnboardingView.swift` — email step header | "Connect Gmail and Sortd adds purchases from receipts and bank alerts — delivery, rides, app stores, online shops. Read-only, on this iPhone." | **shorten** | Drop example list; full disclosure still shown in `ConnectGmailSheet` before OAuth. (voice: later) |
| `Views/OnboardingView.swift` — welcome, currency, cards, applePay, budget, reminders, finish, pro headers/bodies | Short instructional copy | **keep** | Plain instructions needed to complete setup (HIG: keep onboarding brief — already brief). |
| `Views/OnboardingView.swift` — card-details "Where do I find these?" reveal | Card number vs Apple Pay number explanation | **keep** | Plain instruction needed to complete a required field; already gated behind a disclosure toggle. |
| `Views/OnboardingView.swift` — Pro page copy, redeem code | Feature list + joke line | **keep** | Feature list is required-ish context for a paid gate; joke is brand voice, not a disclaimer. |
| `Views/SetupGuideView.swift` — intro paragraph | "A one-time, two-minute setup in the Shortcuts app. After that, every Apple Pay tap is logged, even with Sortd closed." | **keep** | Short instruction. |
| `Views/SetupGuideView.swift` — "Last Tap Received" footer | "What Sortd did with the last tap, and exactly what Apple Pay sent. Useful if a tap shows the wrong shop, amount or card, or doesn't show up at all." | **shorten** | Kept (explains a diagnostic block that's otherwise unreadable), tightened. (voice: later) |
| `Views/SetupGuideView.swift` — "Good to Know" bullets | 3 one-line notices | **keep** | Already one line each, practical. |
| `Views/WalletSetupGuide.swift`, `SetupGuideView` steps | Numbered step text | **keep** | Plain instructions to use the feature. |
| `Views/ReceiptScanView.swift` — intro | "Sortd reads the shop, total, date and card on your iPhone. The photo isn't saved or sent." | **keep** | Already one short sentence; matches camera purpose string. |
| `Views/ImportView.swift` — "Add From" footer | "Read on this iPhone. Nothing uploads, and nothing saves until you tap Add." | **keep** | Short, behaviourally important (nothing saves until reviewed). |
| `Views/ImportView.swift` — "How" section | Export-then-pick instructions | **keep** | Plain instruction. |
| `Views/ImportView.swift` — backup restore footer | "Add keeps what's here and fills the gaps. Replace wipes it first — for a new phone." | **keep** | Needed to choose between a destructive and non-destructive option. |
| `Settings/BackupDataSettingsView.swift` — Backup footer | "Everything stays on this iPhone. A backup is the only way to move phones, or to get your purchases back if you lose this one." | **keep** | Short, practical. |
| `Settings/BackupDataSettingsView.swift` — Your Data footer | "Export gives you every purchase as a spreadsheet file. Delete removes everything Sortd has stored on this iPhone." | **keep** | Short. |
| `Settings/BackupDataSettingsView.swift` — Delete confirmation | "This removes every purchase, card, budget and setting from this iPhone. It can't be undone. Export first if you want a copy." | **keep** | Required: irreversible destructive action must be confirmed with its consequence stated (Apple HIG). |
| `Settings/CardsAppearanceSettingsView.swift` footer | "Cards are coloured by what you spend on them. Appearance follows your iPhone unless you pick Light or Dark." | **keep** | Short. |
| `Settings/CurrencySettingsView.swift` footer | "Purchases in other currencies are converted to X at that day's European Central Bank rate." | **keep** | Short, factual. |
| `Settings/PurchaseSourcesSettingsView.swift` footer | "Logs in-store Apple Pay taps the moment you pay." | **keep** | Short. |
| `Settings/BillsRemindersSettingsView.swift` footer | "A notification at 9 am the day before a subscription or bill is due." | **keep** | Short. |
| `Settings/LearnedRulesView.swift` empty state | Short description | **keep** | Short, instructional. |
| `Settings/AboutSettingsView.swift` | Version/stored/purchase count rows | **keep** | Factual, short. |
| `Views/CardsSettingsView.swift` — card-number footer, currency footer, Wallet-name footer, empty state | Instructional footers | **keep** | Plain instructions to use each field. |
| `Views/WidgetsGuideView.swift` — Privacy section | "Widgets read a small summary on this iPhone — today's total, what's left, the next few bills. Nothing is uploaded." | **keep** | Already one short sentence. |
| `Views/RecurringView.swift`, `InsightsView.swift`, `ActivityView.swift`, `CardDetailView.swift`, `HomeView.swift` empty states | Short `ContentUnavailableView` descriptions | **keep** | Short, brand-voice, instructional — not disclaimers. |
| `Spend/Intents/*.swift` — Siri/Shortcuts dialogs and parameter descriptions | Status messages ("Logged $X at Y", error explanations) | **keep** | Functional results and instructions for the automation, not disclaimers; several are Apple-required App Intent `description`/`@Parameter description` metadata. |
| `Services/ProStore.swift` — `Feature.detail` | One-line per feature | **keep** | Already short. |
| Info.plist purpose strings (`NSFaceIDUsageDescription`, `NSCameraUsageDescription`) | Short system-prompt strings | **keep** | Required by Apple (5.1.1(ii)); already minimal; not app UI text so out of this pass's edit scope. |

## Totals
- Reviewed: ~45 distinct user-facing strings/blocks across 20 files.
- Removed outright: 3 (Help & Feedback note, Privacy "Good to Know" paragraph, Gmail "unverified app" footnote).
- Shortened: 7 (Privacy screen rows, Privacy&Security footer, GmailSection footer, disconnect confirmation, ConnectGmailSheet disclosure, Onboarding email header, SetupGuide "Last Tap" footer).
- Kept unchanged (required or already short/instructional): remainder (~35).
