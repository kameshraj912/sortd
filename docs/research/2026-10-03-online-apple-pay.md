# Online Apple Pay logging for Sortd: research (3 Oct 2026)

Web research only. No repo edited. Search/fetch tools return summaries, so quotes are short and where I could not open the page itself I say so. Most "iOS 27" sources are blogs and vendor pages, not Apple.

## Bottom line (what Sortd should do)

Keep the Wallet "Transaction" (tap) trigger for shop taps. For online and in-app Apple Pay, add the iOS 27 "Notification" trigger, but point it at the **bank's own app** (CommBank, DBS, etc.), not only at Wallet. The reason: Wallet notifications only exist for some issuers, and their text is not documented anywhere I found. Bank apps are what other trackers use (finerd tells users to pick the bank app). Bank apps send one push per card purchase if the user turns it on, online or not. Keep the Wallet-notification trigger as a second option, but do not rely on it until a real-phone test passes. The simulator result (Messages works, Wallet does not) proves little: Apple's own forum says you cannot even add a card in the simulator, so there is no real Wallet payment flow to test. I found **no source** saying iOS blocks Wallet from the Notification trigger, and one third-party guide (WalletPal) says Wallet works. Also add a manual "quick add" for gaps. FinanceKit is no help in AU/SG today (US and UK only). Parse amount and currency from the notification text, make it tolerant of different bank formats, and de-duplicate against taps (a tap can produce both a Transaction trigger and a notification).

## Findings table

| # | Question | Answer | Confidence | Source |
|---|---|---|---|---|
| 1a | Trigger name | "Notification" (iOS 27); UI reads "When I receive a notification from [App]". Apple lists it under Event triggers | High | https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios |
| 1b | Options and fields | Pick one App. Optional filters on Message, Subtitle, Title. A "Notification" magic variable gives body, time-sensitive flag, date | High (Apple doc for filters), Medium (variable) | same Apple page; https://www.macstories.net/stories/ios-and-ipados-27-review/13/ |
| 1c | Runs without asking | Yes, runs in background, even locked, per guides | Medium | https://wiki.beard.fm/whats-new-ios-27/how-to-use-ios-27s-notification-triggers-for-advanced-cross- ; https://walletpalapp.github.io/apple-shortcuts-notification-trigger.html |
| 1d | Which apps selectable; Apple apps allowed? | No Apple doc found on limits. WalletPal guide uses Wallet as the source app. Nothing found saying Wallet or Messages is excluded | Low | https://walletpalapp.github.io/apple-shortcuts-notification-trigger.html |
| 1e | Reports of Wallet notifications triggering it | One vendor guide (WalletPal) says it works. No independent report, no Reddit, no Cassinelli, no RoutineHub post found. No report that it fails either | Low | same |
| 1f | Contrary hint | A Homey forum post calls it a "beta issue" that info is not extracted from other apps, "even Apple's own messages app". Unclear what it means, conflicts with your Messages test | Low | https://community.homey.app/t/ios-27-notifications-and-new-shortcuts/156044/5 |
| 2a | When Transaction trigger fires | Apple says only: "Select a card to trigger an automation whenever it's tapped." Apple does not say NFC-only | High (Apple wording) | https://support.apple.com/guide/shortcuts/transaction-trigger-apd65c67538a/ios |
| 2b | Online / in-app | Several third parties say it does not fire (NFC taps at a terminal only). None is Apple. No contrary report found | Medium | https://www.cashjot.com/blog/apple-pay-expense-tracking ; https://moneycoach.ai/apple-pay-import |
| 2c | Watch / Transit | MoneyCoach says Watch is "inconsistently captured". Apple Watch works per TravelSpend search snippet. Express Transit: not found | Low | https://moneycoach.ai/apple-pay-import |
| 2d | iOS 26 / 27 changes | iOS 26 renamed it "Wallet" (still Transaction on 27 per Apple page selector and WalletPal). No change to when it fires found | Medium | https://walletpalapp.github.io/apple-pay-expense-tracker-shortcuts.html |
| 2e | Reliability | Open dev-forum reports: timeouts, "Automation failed", stopped on iOS 18 (FB14035016, FB16379100). Cannot test in Simulator | High (that reports exist) | https://developer.apple.com/forums/thread/773745 ; https://developer.apple.com/forums/thread/746889 |
| 3a | Does Wallet notify for online/in-app Apple Pay | Apple says you get a notification when the transaction is confirmed, and for some cards also for non-Apple-Pay use. "For cards that support it" i.e. issuer dependent | Medium | https://support.apple.com/bn-in/guide/watch/apdbe9c11bba/6.0/watchos |
| 3b | Which cards | Issuer dependent. Old MacRumors thread says many credit cards give no or Apple-Pay-only notifications. Not Apple Card only | Low (snippet only, page blocked) | https://forums.macrumors.com/threads/apple-pay-transaction-notifications-not-all-cc-issuers-are-the-same.1979675/ |
| 3c | Wallet notification text format | Not found. No real title/body examples from any bank | Not found | n/a |
| 3d | AU/SG bank examples | DBS and OCBC say you get real-time notifications when using Apple Pay. CommBank, ANZ Plus say alerts for card use. No Wallet-notification text samples found for NAB, Westpac, UOB, StanChart, YouTrip, Wise, Revolut | Medium (existence), Not found (text) | https://www.dbs.com.sg/personal/deposits/pay-with-ease/apple-pay ; https://www.commbank.com.au/digital-banking/transaction-notifications.html |
| 4 | How other trackers do it | See table below. Most use only the tap trigger and say online is not covered. finerd is the one found using a bank-app Notification trigger (iOS 27) | High | see notes |
| 5a | FinanceKit regions | US (iOS 17.4+): Apple Card, Apple Cash, Savings. UK (iOS 18.4+): connected accounts via open banking | High | https://developer.apple.com/financekit |
| 5b | AU / SG | Not covered. Found no announcement | Medium (absence) | same |
| 5c | Entitlement | `com.apple.developer.financekit`, by request form. App must be in Finance category and distributed in the US or UK App Store | High | same |
| 5d | Ordinary bank cards in Wallet | No in US. Only Apple's own accounts. Not for AU/SG bank cards | High | https://moneko.io/blogs/apple-wallet-sync-2026 (secondary) |
| 6a | Bank SMS + Message trigger | Works as a pattern (India guides). AU/SG purchase SMS: DBS sends SMS/email/push by threshold; AU big four mostly push. Not confirmed per bank | Medium | notes below |
| 6b | Bank app push + Notification trigger | Best fit on iOS 27. finerd does exactly this | Medium | https://help.finerd.ai/apple-pay.md |
| 6c | PayNow/PayID | Not found as a purchase-logging route; they are transfers | Low | n/a |
| 6d | Most reliable | Bank-app notification for the user's own cards, with threshold set to zero, plus tap trigger for shops | Medium | see notes |

## Notes per question

### 1. iOS 27 Notification trigger
- Apple's Shortcuts guide, Event triggers page, lists "Notification" with "App: Specify the app a notification will be received from" and "Add Filter: ... Message, Subtitle, or Title". URL: https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios (high). The page does not say whether it runs immediately and says nothing about which apps are allowed.
- MacStories iOS 27 review says you can filter title, subtitle or message and use a "Notification" variable for body text, time-sensitive and date (medium). https://www.macstories.net/stories/ios-and-ipados-27-review/13/
- Several guides say it runs silently in the background, including when locked (medium, blogs).
- WalletPal publishes a guide where Wallet is the chosen app and the shortcut passes title, subtitle and body to its log action. It says "Automations initially show as invalid" until you pick the app. This is a vendor page for a competing expense app, so treat it as a claim, not proof. https://walletpalapp.github.io/apple-shortcuts-notification-trigger.html
- I did not find: an Apple statement that Wallet or other system apps are excluded, any r/shortcuts or Cassinelli post on it, any RoutineHub item, or any "Wallet does not trigger" report. Absence of reports is weak evidence.
- Possible simulator cause: pushing a fake `com.apple.Passbook` payload may differ from how Wallet really posts (Wallet may post local notifications, not remote ones). That is my guess, not sourced. Only a real phone settles it.

### 2. Wallet Transaction trigger
- Apple's wording is about taps: "whenever it's tapped" (high). It lists no card limits or online behaviour.
- Matthew Cassinelli (iOS 17): fires on "When I tap a Wallet Card or Pass", works with payment, transit, access, identity passes, passes card, merchant, amount. https://matthewcassinelli.com/shortcuts-automations-ios-ipados-transaction-display-stage-manager/ (high for wording; says nothing on online).
- CashJot: "iOS Wallet automations fire exclusively on physical NFC contactless taps". MoneyCoach: in-person only. A Threads post says it "does not work for online purchases". All third party, none official, but consistent with your own observation. (medium)
- Apple Developer Forums: transaction trigger timeouts when the card issuer is slow; bug reports FB14035016 and FB16379100; no Apple reply. https://developer.apple.com/forums/thread/765516
- App Intents only get Name, Amount, Merchant, Card as separate fields (Apple forum, Feb 2025). https://developer.apple.com/forums/thread/773797
- Apple Watch and Express Transit: not found in any solid source. Needs a phone test.

### 3. Wallet notifications for online purchases
- Apple Watch guide: "You receive a notification in Notification Center when the transaction is confirmed" and for supported cards you also get notifications for purchases made another way. Issuer-dependent. https://support.apple.com/bn-in/guide/watch/apdbe9c11bba/6.0/watchos
- Apple Community answer: for third-party cards the Wallet alert is push only, no email or text. https://discussions.apple.com/thread/254151194
- The Wallet notification title/body format is not documented anywhere I found. Finny's blog uses "Chase: $4.85 at Blue Bottle" as an example of a bank push, not a Wallet one. https://getfinny.app/blog/apple-pay-two-channels-one-tap
- DBS: "real-time notifications and details of your purchases when you use Apple Pay" (via digibank). OCBC: Apple Pay purchase notifications appear on the iPhone and are set per card under Settings > Wallet & Apple Pay > Card Notifications (search summary, PDF unreadable).
- Not found for NAB, Westpac, UOB, StanChart, YouTrip, Wise, Revolut.

### 4. How other trackers do it

| App | Trigger they tell users to set | Online covered? | How | Source |
|---|---|---|---|---|
| MoneyCoach | Transaction trigger, Run Immediately | No ("in-person" only) | Shortcuts action | https://moneycoach.ai/apple-pay-import |
| TravelSpend | "When I tap" card, iOS 17+ | No (physical) | Shortcuts | https://help.travel-spend.com/shortcuts--automation/ignQHsp85RQDsig2QwVcdX/set-up-apple-pay-automation/7tL8XfjBceg4D7mQeiSK2V |
| Expenses app | "When I tap" card | Not mentioned | Shortcuts | https://expenses.cash/faq/import-transaction-from-wallet/ |
| Finny | Tap trigger | No ("online card-number purchases" not covered) | Shortcuts, plus quick log | https://getfinny.app/blog/auto-capture-apple-pay-spending-2026 |
| finerd | (a) Wallet trigger, or (b) iOS 27 "Notification" trigger on a chosen bank app | Bank option covers whatever the bank pushes; the page does not say online explicitly | Reads notification on device, sends only payments; needs amount with currency, e.g. "$6.45". One method per card or you get duplicates | https://help.finerd.ai/apple-pay.md |
| WalletPal | Transaction (iOS 27: also Notification on Wallet) | Claims Wallet notification route; unverified | Shortcuts | https://walletpalapp.github.io/apple-pay-expense-tracker-shortcuts.html |
| Budgie (open source) | Transaction trigger | No, "tap-event capture only" | Shortcuts to App Group | https://github.com/budgie-at/budgie/pull/630 |
| Moneko | Blog says it "supports notification capture on iOS 27", plus WhatsApp forwarding | Unclear | Not verified; App Store listing did not confirm | https://moneko.io/blogs/apple-wallet-sync-2026 |
| India SMS parsers (xyratrack, technofino guides) | Message trigger, "Message contains" e.g. "spent"/"debited", Run Immediately | Yes, whatever the bank texts | Bank SMS | https://xyratrack.in/docs/iphone-automation |
| MoneyCoach, Copilot, Monarch, Spendee, Buddy, Nudget, Bobby, Dime | Not checked in depth; Copilot/Monarch use bank connections (Plaid-style) | n/a | n/a | not found |

- BudgetBakers Wallet help page returned 403, so unread.
- Finny blog, "bank-says-charged-but-finance-app-shows-nothing" and "ios-shortcuts-automations-flaky-fix" were found but not opened. They may carry useful reliability notes.

### 5. FinanceKit
- Apple page says US (iOS 17.4+): Apple Card, Apple Cash, Savings; UK (iOS 18.4+): connected accounts via open banking (Barclays, HSBC, Lloyds, Monzo, NatWest etc). https://developer.apple.com/financekit
- Entitlement: by form, Account Holder submits, one bundle ID. App must be in Finance category and on the US or UK App Store.
- Background delivery from iOS 26 (secondary source search snippet).
- AU/SG: no mention, no expansion news found. Connected accounts in Wallet: Apple support pages exist for other countries, but nothing for AU/SG found.
- Ordinary bank cards in Wallet in AU/SG would NOT come through FinanceKit.
- The Budgie PR confirms the same story for Ukraine: FinanceKit region and entitlement do not cover it.

### 6. Fallbacks in AU/SG
- Bank app push + Notification trigger (iOS 27): fits best. CommBank says "an alert on your phone every time you use your card". ANZ Plus lists "Purchases made using your card" and says the preview may show the amount. NAB and Westpac: pages did not confirm per-purchase alerts. https://www.commbank.com.au/digital-banking/transaction-notifications.html ; https://www.anz.com.au/plus/support/profile-security/notifications-and-marketing/push-notifications/
- DBS/POSB (search summary of DBS pages, not fully verified): default alert threshold S$500; for online card transactions the threshold can go down to S$0.01; recurring/subscription charges do not alert; channels SMS, email, push. So users must lower the threshold. https://www.dbs.com.sg/personal/support/bank-ibanking-notification-alerts.html
- OCBC, UOB TMRW: apps confirmed to send push for Apple Pay (UOB wording unclear). Per-purchase rules not verified.
- Bank SMS + Message trigger: works in India. AU big four mostly use app push, not SMS; SG banks use SMS for some alerts by threshold. Not verified per bank. SMS also needs "Message contains" keywords that differ by bank.
- YouTrip, Wise, Revolut: own-app pushes; formats not found.
- PayNow/PayID: transfers, not card purchases. Not a logging route.
- Weak points of the bank-notification route: text format differs by bank and language, amount with currency must be present, users must keep previews on and notifications on, subscriptions may be excluded, and the same purchase may also fire the Wallet tap trigger (duplicates).

## What a 10-minute phone test should check (real iPhone, iOS 27, one AU or SG card in Wallet)

1. Make a Shortcuts automation: Notification > App: Wallet > Run Immediately > action "Show Result" or a Notes append with Notification title, subtitle, body. Check it can be saved and does not stay "invalid".
2. Tap to pay in a shop. Did Wallet post a notification? Did the Notification automation run? Did the Transaction automation also run? (Check for duplicates.)
3. Pay online in Safari with Apple Pay (any small amount, e.g. a donation or a small web purchase). Did Wallet post a notification? Did the Notification automation fire? Write down the exact title, subtitle, body.
4. Pay in an app with Apple Pay (DoorDash, Uber). Same checks. Did the Transaction (tap) automation fire?
5. Check the card's settings under Settings > Wallet & Apple Pay > card > Card Notifications is on, and Wallet notifications are allowed in Settings > Notifications > Wallet.
6. Repeat steps 3 and 4 with a second Notification automation set to the bank's own app (CommBank, DBS, etc.). Write down its exact text. Confirm the bank app lets the user alert on every purchase (DBS threshold to S$0.01).
7. Try two cards from two banks (one AU, one SG if possible), and if available a Wise, Revolut or YouTrip card, to see whose notifications appear.
8. Lock the phone and repeat once, to confirm the automation runs while locked and that "Run Immediately" never asks.
9. Test a notification with the phone on Low Power Mode and with the app in the background, to see how reliable it is.
10. Record time from payment to automation run, and whether a notification preview setting ("Show Previews: Never") hides the amount from the shortcut (not found in docs; check).

## Not verified
- Any Apple statement on which apps the Notification trigger allows. Any Wallet-specific notification text. Whether iOS 27 excludes Wallet. Behaviour of the Transaction trigger for Watch/Express Transit. Per-bank AU/SG purchase SMS lists. Sources like CashJot, Finny, finerd, WalletPal and Moneko are product blogs with a commercial interest.
