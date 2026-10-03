# Capturing in-app / online Apple Pay on iOS 26 (and 17-27): what actually works

Research date: 3 Oct 2026. Web research only. Nothing was tested on a device.
"Not verified" = I found a claim or no source, but no primary proof.

## Bottom line

1. On iOS 26 there is NO clean, automatic, on-device way to capture online or in-app Apple Pay purchases without a bank link. Every working method is either (a) a tap or screenshot from the user, (b) reading an email or SMS the bank/merchant sends, or (c) a server.
2. The Wallet "when I tap a card" trigger is NFC-tap only. Multiple expense apps say online and in-app purchases do not fire it. Apple's own page says almost nothing (it only lists "When I tap"). Treat "NFC only" as the working assumption. I found no report of it firing for online purchases.
3. Best real coverage on iOS 26, ranked by coverage x reliability x privacy:
   - A. Bank alert SMS via the Message trigger (Run Immediately). Good for banks that text every purchase. Fully on-device. Weak in AU (banks use push, not SMS). Medium in SG (UOB and DBS text only above a threshold you can set, e.g. to a low value).
   - B. Bank/merchant email via the Email trigger. Works only for Apple Mail accounts. Receipts have no card info and are slow. Conflicting reports on whether it can run without asking (Apple's own page says it can).
   - C. Weekly screenshot of the Wallet or bank transaction list, read with on-device OCR. Not automatic, but covers everything the bank shows, including online Apple Pay. Most honest fallback.
   - D. "Open the merchant app" trigger that asks for the amount. Needs a typed amount. A nudge, not capture.
   - E. Server email forwarding. Works, but breaks local-first.
4. iOS 27 fixes this properly: the new "When I receive a notification" trigger can listen to the Wallet app (or the bank app) and pass title, subtitle and body to a shortcut. It is the only fully automatic, on-device route. Not available on iOS 26. Whether it also fires for online/in-app purchases depends on Wallet/bank sending a notification for them (not verified for AU/SG banks).
5. FinanceKit does not help in AU or SG. Apple lists only US (Apple Card, Cash, Savings) and UK (open banking accounts). Also needs Finance-category app distributed in US or UK, plus a managed entitlement.

## Comparison table

| # | Approach | iOS | Automatic? | Gets | Online/in-app Apple Pay? | Reliability | Privacy / local-first |
|---|---|---|---|---|---|---|---|
| 1 | Wallet "tap a card" trigger | 17.4+ (named "Wallet" on 26) | Yes (shows a "ran" notice) | Amount, merchant, card, currency, date | No (NFC taps only, per many apps) | Mixed: times out for slow issuers, esp. Mastercard in some countries | On-device |
| 2 | Email trigger (receipts or bank alerts) | 17+ | Per Apple, can Run Immediately; one forum reply disagrees | Subject + body as input; Sender/Subject/Account/Recipient filters | Only if an email is sent | Depends on parsing; Mail app accounts only (not verified for Gmail app) | On-device; reads whole email |
| 3 | Message trigger on bank SMS | 17+ | Yes (Run Immediately) | Whatever SMS text has: usually amount, merchant, last 4 digits | Yes, if bank texts that purchase | Banks use short codes; filter on text, not contact | On-device |
| 4 | Wallet Orders / order tracking | 26 (email scan), AU from 27 | n/a | Order status, merchant | n/a | No public way for other apps to read it (not verified) | Apple Intelligence on-device |
| 5 | FinanceKit | 17.4 US, 18.4 UK | Background reads | Full transactions | Yes, but only US/UK accounts | Good where available | On-device, entitlement needed |
| 6 | Screenshot + on-device OCR | 17+ (Tables mode in 27) | No (user action) | Whatever is on screen | Yes (any row the bank shows) | OCR errors; needs review | On-device |
| 7 | Email forwarding to server address | Any | Yes (after setup) | Full receipt | Yes | Parsing on server | Breaks local-first |
| 8 | App-open trigger that asks amount | 17+ | Half (needs typing) | Nothing but the app name | Only as a nudge | Double-fires | On-device |
| 9 | Bank APIs (Up, CDR, SGFinDex) | Any | Yes | Full transactions | Yes | Good | Needs bank link (Sortd avoids) |
| 10 | Mac bridge | n/a | Partial | n/a | n/a | Weak | n/a |
| 11 | iOS 27 notification trigger | 27 only | Yes, runs in background | Notification title, subtitle, body | Yes if Wallet/bank notifies | New; no reliability reports found yet | On-device |

## Notes per approach

### 1. Wallet transaction trigger ("When I tap a Wallet card or pass")
- How: Shortcuts > Automation > Wallet (called "Transaction" before iOS 26) > pick cards > Run Immediately > use "Receive Transaction As Input".
- Data: card, merchant, amount, date, optional filter by card/category/merchant. Seen in Matthew Cassinelli's iOS 17 post and in apps (Splitsies adds currency code).
- Online/in-app: Not fired. CashJot says it "fire[s] exclusively on physical NFC contactless taps". Graham Haley says "NFC only, not from a web browser." TravelSpend help says it "only works for physical payments." Apple's own Shortcuts page lists only "When I tap" and gives no detail.
- Apple Watch: conflicting. TravelSpend says Watch needs you to run the shortcut once on the Watch. One BudgetBakers snippet (page blocked, 403 when I fetched; seen only via search summary) says Watch/Mac payments do not trigger. An Apple dev forum post from March 2026 says a Wallet automation works on iPhone but not Watch (no replies).
- Reliability: Apple Dev Forums threads 765516, 773745, 758053 report timeouts, "Automation failed", and no trigger after iOS 18. Reported affected: Mastercard cards, Cembra (Switzerland), Nubank (Brazil). Visa reported better. Wallet can get the transaction hours late and the trigger gives up first. Also said to fire on declined transactions. Open Feedback IDs FB14035016 and FB16379100 (as quoted in the forum). Category filter ("food & drinks") never fires (Apple Community 255836983, iOS 17).
- Run Immediately: Apple requires a notification each time it runs (Cassinelli, Aug 2023, iOS 17 betas). Still true on 26: not verified.
- I found no report (r/shortcuts, Apple forums, app help pages) of it firing for online or in-app Apple Pay on any iOS version. Not verified either way for AU/SG issuers, but no evidence for it.
- Sources: https://support.apple.com/en-au/guide/shortcuts/apd65c67538a/ , https://www.cashjot.com/blog/apple-pay-expense-tracking , https://grahamhaley.co.uk/2024/11/19/apple-pay-automation/ , https://help.travel-spend.com/shortcuts--automation/ignQHsp85RQDsig2QwVcdX/fix-problems-with-the-apple-pay-automation/4nyjF9naMFGzU8JbVuWDsc , https://developer.apple.com/forums/thread/765516 , https://developer.apple.com/forums/thread/773745 , https://discussions.apple.com/thread/255836983 , https://developer.apple.com/forums/thread/819473 , https://matthewcassinelli.com/?p=26581 , https://matthewcassinelli.com/automations-run-immediately-shortcuts-notifications/ , https://support.budgetbakers.com/hc/en-us/articles/29100343309586-Apple-Pay-Integration

### 2. Email trigger
- How: Shortcuts > Automation > Email. Filters: Sender, Subject Contains, Account, Recipient (all must match). Then run an App Intent or action with Shortcut Input.
- Shortcut Input: a forum answer (Automators Talk) says it is a file whose name is the subject and content is the email body. Not verified on iOS 26.
- Without asking: Apple's "run automatically" page lists Email as allowed (Run Immediately). One Apple Community reply (255550769) says sensitive-data actions force a prompt, with no workaround. One search summary said email "cannot" run automatically. This conflicts with Apple's page. Treat as unconfirmed; test on device.
- Needs Apple Mail: the trigger works on accounts set up in Apple Mail. Whether Gmail-app-only users get it: not verified.
- Coverage: bank alert emails give amount, merchant, card last 4 (DBS, UOB, OCBC all offer email alerts). Merchant receipts (Uber, DoorDash, Amazon, Apple) give totals but arrive minutes later and have varied layouts. Apple Pay receipts from Apple (for App Store) arrive by email.
- Privacy: the whole email goes through Shortcuts to the app on-device. Fine. Sortd's existing Gmail parser (per project notes) is a similar idea but uses OAuth.
- Sources: https://support.apple.com/en-gu/guide/shortcuts/apdd711f9dff/ios , https://support.apple.com/en-au/guide/shortcuts/apd602971e63/ios , https://talk.automators.fm/t/automating-e-mail-content/16537 , https://discussions.apple.com/thread/255550769

### 3. Message trigger on bank SMS
- How: Automation > Message > "Message Contains" a phrase unique to the bank SMS (not Sender, because bank short codes are not contacts). Apple Dev Forums 705659 confirms this and says it works on iOS 16.6+. Run Immediately allowed per Apple.
- Input: the SMS text. App parses amount, merchant, last 4.
- AU: big banks lean on push notifications. NAB says it does not use SMS to contact customers for security. Westpac and CBA offer push alerts for card purchases. So SMS coverage in AU is low. Not verified: whether any AU bank texts every purchase. Push-only means this only works with the iOS 27 notification trigger.
- SG: DBS/POSB defaults to S$500 threshold for alerts (can be lowered in digibank), UOB alerts at or above a threshold, OCBC can send alerts by push, email or SMS. SG banks are the better fit, with the threshold set to the minimum.
- Reliability: no reports found on missed SMS. FinArt/Finny note SMS capture on iPhone is "less reliable than Android" because apps cannot read the inbox.
- Privacy: on-device.
- Sources: https://developer.apple.com/forums/thread/705659 , https://www.dbs.com.sg/personal/support/bank-ibanking-notification-alerts.html , https://www.uob.com.sg/personal/cards/services/card-alerts.page , https://www.ocbc.com/personal-banking/security/secure-banking-ways/transaction-alerts.page , https://www.nab.com.au/personal/credit-cards/manage-your-credit-card/push-notifications , https://www.westpac.com.au/faq/push-notifications/ , https://getfinny.app/blog/sms-expense-tracking-app

### 4. Wallet Orders / order tracking
- iOS 26: Apple Intelligence scans Apple Mail for order emails and shows them in Wallet (Settings > Wallet & Apple Pay > Order Tracking > Mail (Beta)). iOS 27 expands order tracking to Australia and Canada (per smartphones24, a secondary source).
- Can other apps read it? I found no API, no Shortcuts action, and no intent. Merchants push orders to Wallet; there is no read path for third parties. Not verified, but nothing in Apple docs I found says otherwise.
- Verdict: dead end for Sortd.
- Sources: https://9to5mac.com/2026/05/19/ios-26s-wallet-app-has-long-awaited-order-tracking-fix-heres-how-to-use-it/ , https://en.smartphones24.org/apps/finance/801312-ios-27-apple-wallet-iphone , https://developer.apple.com/wallet/resources/

### 5. FinanceKit
- Apple's page: US (iOS 17.4+): Apple Card, Apple Cash, Savings. UK (iOS 18.4+): open-banking accounts (Barclays, HSBC, Lloyds, Monzo, NatWest etc.). No AU or SG. I saw no iOS 27/WWDC 2026 sign of expansion (not verified; the search turned up nothing).
- App must be in Finance category, sold on US or UK App Store, and request a managed entitlement. Sortd would not qualify from AU/SG.
- Source: https://developer.apple.com/financekit

### 6. Screenshot + on-device OCR (weekly catch-up)
- How: user screenshots the Wallet card's transaction list or the bank app list. Shortcut or the app runs "Extract Text from Image" (Live Text/Vision), then parse rows. iOS 27 adds a Tables mode that returns rows. Trigger by Back Tap, Action Button, or share sheet.
- Not automatic. User must take the screenshot.
- Gets: whatever is visible: merchant, amount, date; card only if on screen.
- Reliability: needs the full row visible; avoid pending items (Finny's own guidance). Always show a review list before saving.
- Privacy: fully on-device if Sortd uses Vision/Live Text. Some competitors send images to the cloud; Sortd should not.
- Sources: https://getfinny.app/blog/log-transactions-from-screenshots , https://getfinny.app/blog/apple-shortcuts-expense-tracking-automations-2026

### 7. Email forwarding to a server address
- Seen in: Moneko (forward the Wallet notification in WhatsApp), SimplyWise (imports from Gmail, Outlook, Amazon), and others.
- Works for any email receipt. Needs a server and a vendor reading the mail. Breaks Sortd's local-first promise. Skip.
- Sources: https://moneko.io/blogs/apple-wallet-sync-2026 , https://apps.apple.com/us/app/simplywise-receipts-expenses/id1538521095

### 8. Other surfaces (Siri, Focus, Notification Summary, Screen Time, Live Activities, App Intents)
- I found no source showing any of these exposes purchase data to a third-party app. Not verified. Reasoning only:
  - Notification Summary, Focus filters: only change how notifications show.
  - Screen Time: app usage, not purchases.
  - Live Activities and App Intents: only the merchant's own app can donate them. A third-party app cannot read them.
  - "App opened" trigger: fires on open, not payment. Finny describes it as a nudge needing manual amount entry.
- Source: https://getfinny.app/blog/auto-log-spending-open-app-automation-2026

### 9. Bank-side (needs bank link, listed for completeness)
- Up Bank (AU): official API with webhooks for transaction events, personal access token. https://github.com/up-banking/api
- CDR open banking (AU): accredited-recipient regime; individual apps need accreditation or a data-holder partner. Not verified for hobby apps.
- SGFinDex (SG): Singpass consent, 7 banks (Citi, DBS/POSB, HSBC, Maybank, OCBC, StanChart, UOB). It is for balances and planning; I found no evidence it gives card-level transaction feeds (not verified). https://www.abs.org.sg/consumer-banking/sgfindex
- All of these break "no bank login".

### 10. Mac bridge
- Mail rules on a Mac only apply on that Mac; they cannot be made on iOS. iCloud.com rules sync but only for iCloud mail. macOS Shortcuts has the same Email/Message triggers, not a Wallet or notification trigger. A Mac must be awake and on. I found no working reports for expense capture. Verdict: weak, skip.
- Source: https://www.computerworld.com/article/3618006/how-to-make-apples-mail-deliver-more-productivity.html

### 11. iOS 27 notification trigger (beyond iOS 26)
- How: Automation > Notification > pick the app (Wallet, or the bank app) > optional filters on Title, Subtitle, Message > Notification magic variable (body text, time-sensitive flag, date). MacStories: filtering by title, subtitle or message content.
- Runs in the background without opening anything (Beard.fm, MacStories coverage). Does it still need the "ran" notification and can it run immediately? Not verified.
- Also new in 27: automations are now "special actions" at the top of a shortcut so they can be shared (disabled until the receiver enables them); a Keyboard trigger; Extract Text from Image Tables mode. Order tracking in Wallet reaches Australia and Canada. I found no new FinanceKit regions or any new Wallet transaction API in 27.
- WalletPal and CashJot already document the Wallet-notification route. WalletPal says field mapping takes a few minutes.
- Open questions to test on a device: (a) does Wallet send a notification for online/in-app Apple Pay for AU and SG cards; (b) are "Not now" and Focus filtered notifications still delivered to the trigger; (c) does the user have to allow it per app; (d) amount and currency format in the body text varies by bank.
- Sources: https://www.macstories.net/stories/ios-and-ipados-27-review/13/ , https://walletpalapp.github.io/apple-shortcuts-notification-trigger.html , https://wiki.beard.fm/whats-new-ios-27/how-to-use-ios-27s-notification-triggers-for-advanced-cross- , https://twit.tv/posts/tech/ios-today-27-shortcuts-how-automate-notifications-messages-and-more-your-iphone

## Other products' claims (read with care)
- FinArt says Apple Pay is "captured and logged instantly" plus SMS and email alerts, with Private Mode on-device. It does not say how online Apple Pay is captured. Not verified. https://finart.app/automatic-expense-tracker-iphone/
- finerd: one Shortcuts automation, for "tap to pay with Apple Wallet or receive a bank notification". Does not address online. https://help.finerd.ai/apple-pay
- Finny/Finly "Tap to Track" is the same NFC trigger. Nothing new.
- Moneko: forward the Wallet notification to its WhatsApp bot. Needs their server. Not local-first.
- TravelSpend, WalletPal, CashJot, Splitsies, BudgetBakers, Skwad, mise: all use the same Wallet trigger. None solve online.
- I did not find useful posts on r/shortcuts, r/YNAB, r/AusFinance, r/singaporefi or MacStories for online Apple Pay on iOS 26 through the search tool, so there may be threads I missed. Not verified.
- YNAB: RoutineHub shortcut "YNAB Transaction Automation" uses the same Wallet trigger. https://routinehub.co/shortcut/16422/

## What Sortd should build (5 lines)
1. Keep the Wallet-tap shortcut as the automatic path for in-store, and say plainly that it does not see online or in-app purchases.
2. For iOS 27: ship a one-tap "Wallet notification" shortcut (Notification trigger, app = Wallet or bank app) that sends title, subtitle and body to a Sortd App Intent, with a text parser per bank format for AU and SG, and mark it iOS 27 only.
3. For iOS 26: add an SMS-trigger recipe (Message Contains + bank text) for SG banks with the threshold lowered, and an email-trigger recipe for bank alert emails; test whether "Run Immediately" holds for both on a real device before promising it.
4. Add a "Catch up" screen: paste or share a screenshot of the Wallet or bank list, read it with on-device Vision/Live Text, show a review list, dedupe against what was already logged, then save. This is the honest weekly fallback for online and in-app.
5. Do not add server forwarding, bank APIs or FinanceKit; if the user wants those, say they are outside Sortd by design.
6. (Added) Reuse rules: write the parser in Swift from MIT/BSD designs (saurabhgupta050890/transaction-sms-parser, scrapinghub/price-parser cases) and the ExpLog field-by-field idea; never copy AGPL/GPL/no-licence code (PennyWise, Auto-Expense-Tracker, ExpLog). Build the test corpus from Raj's own real AU/SG messages and Wallet banners, because no open repo covers AU or SG. Copy finerd's one-route-per-card rule.

## Reusable existing work

Licence rule of thumb for Sortd (closed app): MIT, BSD and Apache-2.0 code can be ported (keep the copyright notice). GPL and AGPL code cannot be copied or translated into Sortd. Code with no LICENSE file is "all rights reserved": do not copy it. Ideas, field grammars and the shapes of messages are not copyrightable, so you can learn from any of them, but write your own code and your own tests. I checked licences with the GitHub API (LICENSE file present or not) on 3 Oct 2026.

### A. Open-source parsers and trackers (GitHub)

| Repo | Lang | Licence | Stars / last push | Covers | Use for Sortd |
|---|---|---|---|---|---|
| https://github.com/saurabhgupta050890/transaction-sms-parser | TypeScript | MIT | 60 / May 2026 | Generic, regex, mostly India. Returns type (debit/credit), amount, merchant, account (card/wallet/account), balance, reference no. | Portable to Swift. Best-known simple design. Test cases are driven by a spreadsheet (docs/UNIT_TESTS.md); the repo ships only an example file, not a corpus. |
| https://github.com/MabudAlam/transaction_sms_parser | Dart | MIT | 5 / Nov 2025 | 30+ Indian banks, 14 wallets, 95+ UPI handles. DBS in the list is the India DBS (INR). | Portable. Shows a per-sender "can this sender be handled" step. Not SG or AU. |
| https://github.com/akhilnarang/bank-sms-parser and https://github.com/akhilnarang/bank-email-parser | Python | MIT | 2 and 0 / pushed 30 Sep 2026 | Indian bank SMS and email alert bodies, one parser per bank and alert type, outputs Money(amount, currency). Has an "add a bank" guide. | Portable. Good model for per-bank templates and SMS+email siblings. New, so quality unknown. |
| https://github.com/dtinth/transaction-parser-th | TypeScript | MIT | 16 / Jan 2019 | Thai bank SMS and notifications. | Portable, old. Useful as an example of non-English, non-India formats. |
| https://github.com/SharkFourSix/momo | Java | MIT | 6 / Oct 2020 | Mobile-money SMS (Africa). | Low value for AU/SG. |
| https://github.com/scrapinghub/price-parser | Python | BSD-3-Clause (portable) | 348 / Aug 2026 | Extracts price and currency symbol from messy strings; tests are described as 900+ real price strings. | Best source of amount/currency edge cases (1.234,56 vs 1,234.56, symbols, codes). Re-implement in Swift; use its cases as a checklist. |
| https://github.com/tboopeshkumar/ExpLog | Swift | NO LICENSE FILE | 0 / 1 Oct 2026 | UAE-style card SMS via share sheet; SwiftUI + SwiftData. | Do not copy. Read the design for ideas (see below). It is the closest match to Sortd's stack. |
| https://github.com/Ekshith-P/spendAnalyzer | Swift | NO LICENSE FILE | 0 / 3 Oct 2026 | Offline-first, no bank login, App Intents. | Do not copy. Confirms the same product shape. |
| https://github.com/sarim2000/pennywiseai-tracker | Kotlin | AGPL-3.0 | 566 / 3 Oct 2026 | 165 parser classes (India, Middle East, Africa, Thailand, a few US/UK banks); 200+ test files; on-device. I saw no SG or AU major bank parsers. Its "DBSBankParser" is INR (India), despite the comment saying Singapore. | CANNOT reuse code (AGPL). Allowed: read it to learn how messy real messages look and how they structure per-bank parsing. Do not paste its test messages wholesale. |
| https://github.com/wealth-wave/Auto-Expense-Tracker (praslnx8) | Kotlin | GPL-3.0 | 14 / Jul 2024 | Android, bank SMS. | CANNOT reuse. |
| https://github.com/marques576/OpenSpend, https://github.com/arrunraj66/rupeeflow-android, https://github.com/KapilYadav-dev/SmsParser | Kotlin / TS | NO LICENSE FILE | 0-5 | Android notification listeners (OpenSpend lists 18+ finance apps, RupeeFlow has a bank-app allowlist). | Ideas only: allowlist of source apps, "reject OTP/decline" filters. |
| https://github.com/AdiletNZ/applepay-expense-tracker | JavaScript | NO LICENSE FILE | 0 / 26 Sep 2026 | iOS 17 Wallet-tap Shortcut posts shop, amount, card to a Google Sheet or own server; categorises by shop name. | Ideas only; it uses a server, so not local-first. |
| https://github.com/alvinncx/dbs-transaction-parser, https://github.com/bearylogical/actualbudget-sg | Elixir / Python | NO LICENSE FILE | 4 and 0 | SG DBS/POSB/UOB/OCBC statement (PDF/CSV) parsing, not SMS. | Ideas only. Useful for SG merchant clean-up ("payee" rules). |
| https://github.com/donn/Rexley | Swift | MIT | 1 / 2021, archived | iOS regex SMS filter. | Not a parser; skip. |

Findings:
- No open-source repo I found covers AU or SG purchase alerts. The corpus gap is real: Sortd will need its own samples from DBS/UOB/OCBC (SMS or email) and from the AU banks' notification text. Raj can collect his own real messages: that is the safest and most accurate test data. Blur or remove card numbers first.
- Test corpora with real messages: PennyWise (AGPL) has the most, but treat it as reference only. Saurabh's repo has a data-driven test design you can copy as a pattern (one table of message to expected fields) with your own rows.
- Money-parse libraries (price-parser, ExpLog's rules) agree on the same traps: two amounts per message (spent vs balance), decimal comma vs point, three-digit group vs three-decimal currencies (KWD), missing year in dates, OTP/decline messages that must not be logged.
- In Swift you can lean on Foundation (`Decimal`, `FormatStyle.Currency`, `NumberFormatter` with a locale) for the final number and use regex only for finding the amount.

Ideas to copy from ExpLog's README (idea only, credit in comments): match each field on its own instead of keeping one rule set per bank, because card alerts share a grammar like "card at merchant for CUR amount on date"; anchor the amount on the currency token so the balance is never picked; non-greedy merchant match that stops at the amount clause; reject sentences that look like merchants (mask numbers, "account", "was", "debited"); keep the raw message so bugs can be fixed later; read dates either way and pick the one closest to the message arrival; title-case SHOUTING merchants but keep words with digits. Source: https://github.com/tboopeshkumar/ExpLog

### B. Ready-made Shortcuts for Apple Pay logging
- RoutineHub pages are blocked to my fetch (403), so the details below are from search snippets only. Treat as not verified.
  - "Wallet 2 YNAB" (https://routinehub.co/shortcut/16328/): Wallet trigger, posts the tap to YNAB.
  - "YNAB Transaction Automation" (https://routinehub.co/shortcut/16422/): Wallet trigger with per-merchant category/account mapping.
  - "The Expenses Tracker" (https://routinehub.co/shortcut/17052/): "When I tap any Wallet passes/Credit cards"; asks for a category; saves amount and details to a database.
  - "Wallet Transactions" (https://routinehub.co/shortcut/17115/): logs taps to a spreadsheet.
  - Blog post on Wallet automations: https://routinehub.co/blog/harness-the-features-of-new-wallet-automations-with-this-shortcut/
- Blog and app shortcuts using the same Wallet trigger: Graham Haley (card, merchant, amount, time to CSV, "NFC only, not from a web browser"), TechTiff on Substack (date, card, merchant, amount, category into Numbers; everything runs on the iPhone), Splitsies (amount, merchant, currency code, timestamp), TravelSpend, MoneyCoach, WalletPal, CashJot, Skwad. All in-store only.
- iOS 27 Notification-trigger shortcuts with a bank app: I found none for a specific bank. The only published recipes are for Wallet as the source app (WalletPal, and finerd's "Apple Wallet or Bank notification" option). Bank-app route exists as an option in finerd (see C). Not verified for any AU or SG bank.
- Real Wallet notification wording: I could not find a screenshot or quoted real example in any article, Apple Community thread, or Apple Dev Forums thread I opened. Clues only:
  - WalletPal's iOS 27 guide maps Title to card name, Subtitle to transaction (merchant) name, Body to amount. That implies Wallet's notification has those three parts. Not verified, and no sample text.
  - Apple Community says what Wallet shows is controlled by the issuing bank and some banks share more than others, so wording will differ by bank and country.
  - Apple Community and Yonder help: with some cards you get two notifications for one payment, one from Wallet and one from the bank app.
  - Moneko's "USD 12.40 at Sweetgreen" and CashJot's "Logged $0.50 at FairPrice" are those apps' own confirmation texts, NOT Wallet's wording. Do not use them as test data.
  - Apple's Wallet notification delay thread (forums 757460) reports Wallet notifications arriving 50 minutes to 1+ hour late for some users (iOS 17.5.1, 18.0.1).
  - Action: Raj should capture 10 or more real Wallet banners (in-store and online, AU and SG cards, plus the bank apps' pushes) as screenshots and use them as Sortd's test corpus.

### C. How other apps describe their setup (copy the good ideas, credit them)
- finerd (https://help.finerd.ai/apple-pay):
  - iOS 27: choose "Apple Wallet" or "Bank notification", install a shortcut, turn the automation on, pick the card, assign the finerd account, test with a real payment. Sends straight to finerd on iOS 27.
  - iOS 26: Wallet trigger plus a text template with Merchant, Description, Amount and a date in "VV" format, then a Send Email action to the user's personal finerd address with "Show Compose Sheet" off. This needs Apple Mail and finerd's server. Not local-first.
  - Rules worth copying: one route per card ("If you set up both for the same card, every payment is recorded twice"); delete the old shortcut before installing a new one; bank notifications must show the amount with a currency symbol or code (their examples "$6.45" and "120.50 UAH"); parse the merchant from the text; clear in-app error messages ("Couldn't add this payment", "Open finerd and finish setup").
  - Their Privat24 setup page parses bank alert emails read from the user's Gmail: https://app.ftr.finerd.ai/landing/privatbank (seen via an issue on GitHub, not opened).
- WalletPal (https://walletpalapp.github.io/apple-shortcuts-notification-trigger.html): Notification trigger, source app = Wallet, add WalletPal action, map Title to card name, Subtitle to transaction name, Body to amount using Shortcut Input, then test with a real notification. In-app setup test creates a test transaction. Does not state duplicate rules.
- Moneko (https://moneko.io/blogs/apple-wallet-sync-2026): forward the notification by WhatsApp to Moneko (their server) or use a "Capture Wallet Transactions" action. Server route.
- CashJot (https://www.cashjot.com/blog/apple-pay-expense-tracking): on iOS 27 the whole automation ships inside the shortcut, so the user installs one shortcut instead of building steps. It still uses the Wallet-tap trigger, not the Notification trigger. Idea to copy: share a ready-made shortcut with the automation inside (works in 27 because automations are now actions; they arrive disabled and the user must enable them).
- Finny / Finly (https://getfinny.app/blog/apple-shortcuts-expense-tracking-automations-2026): "Tap to Track" is the Wallet trigger; screenshots and receipt photos handled by on-device OCR; says plainly that iOS shortcuts do not read bank APIs.
- FinArt (https://finart.app/automatic-expense-tracker-iphone/): four channels (Apple Pay, SMS, email alerts, PDF statements), "Private Mode" on-device with backup to the user's own iCloud Drive. Marketing text; the method for online Apple Pay is not shown.
- Good ideas to copy for Sortd: (1) one route per card, shown clearly in the UI, with a warning if two routes cover the same card; (2) require amount plus currency in the text or ask the user; (3) install-a-ready-shortcut flow; (4) a "test with a real payment" step; (5) keep the raw text with every logged item; (6) plain error messages when parsing fails and an "unparsed" inbox instead of silent loss.

### D. Duplicates between routes (important for Sortd)
- A single online Apple Pay purchase can produce a Wallet notification, a bank-app push, a bank SMS and a receipt email. If Sortd supports several routes it needs dedupe on (amount, currency, merchant-ish, time window) and a per-card "primary route" setting. finerd's one-route-per-card rule is the simple version.

## Sources (all)
- https://support.apple.com/en-au/guide/shortcuts/apd65c67538a/ios
- https://support.apple.com/en-gu/guide/shortcuts/apdd711f9dff/ios
- https://support.apple.com/en-au/guide/shortcuts/apd602971e63/ios
- https://developer.apple.com/financekit
- https://developer.apple.com/forums/thread/765516
- https://developer.apple.com/forums/thread/773745
- https://developer.apple.com/forums/thread/705659
- https://developer.apple.com/forums/thread/819473
- https://discussions.apple.com/thread/255836983
- https://discussions.apple.com/thread/255550769
- https://matthewcassinelli.com/?p=26581
- https://matthewcassinelli.com/automations-run-immediately-shortcuts-notifications/
- https://www.macstories.net/stories/ios-and-ipados-27-review/13/
- https://walletpalapp.github.io/apple-pay-expense-tracker-shortcuts.html
- https://walletpalapp.github.io/apple-shortcuts-notification-trigger.html
- https://www.cashjot.com/blog/apple-pay-expense-tracking
- https://help.travel-spend.com/shortcuts--automation/ignQHsp85RQDsig2QwVcdX/fix-problems-with-the-apple-pay-automation/4nyjF9naMFGzU8JbVuWDsc
- https://grahamhaley.co.uk/2024/11/19/apple-pay-automation/
- https://splitsies.dev/articles/2026-06-27-capture-payments-shortcut
- https://github.com/MGRL2201/mise/issues/153
- https://getfinny.app/blog/log-transactions-from-screenshots
- https://getfinny.app/blog/auto-log-spending-open-app-automation-2026
- https://getfinny.app/blog/sms-expense-tracking-app
- https://finart.app/automatic-expense-tracker-iphone/
- https://help.finerd.ai/apple-pay
- https://moneko.io/blogs/apple-wallet-sync-2026
- https://9to5mac.com/2026/05/19/ios-26s-wallet-app-has-long-awaited-order-tracking-fix-heres-how-to-use-it/
- https://en.smartphones24.org/apps/finance/801312-ios-27-apple-wallet-iphone
- https://www.dbs.com.sg/personal/support/bank-ibanking-notification-alerts.html
- https://www.uob.com.sg/personal/cards/services/card-alerts.page
- https://www.ocbc.com/personal-banking/security/secure-banking-ways/transaction-alerts.page
- https://www.nab.com.au/personal/credit-cards/manage-your-credit-card/push-notifications
- https://github.com/up-banking/api
- https://www.abs.org.sg/consumer-banking/sgfindex
- https://talk.automators.fm/t/automating-e-mail-content/16537
- https://github.com/saurabhgupta050890/transaction-sms-parser
- https://github.com/MabudAlam/transaction_sms_parser
- https://github.com/akhilnarang/bank-sms-parser
- https://github.com/dtinth/transaction-parser-th
- https://github.com/scrapinghub/price-parser
- https://github.com/tboopeshkumar/ExpLog
- https://github.com/Ekshith-P/spendAnalyzer
- https://github.com/sarim2000/pennywiseai-tracker
- https://github.com/AdiletNZ/applepay-expense-tracker
- https://routinehub.co/shortcut/16328/ , https://routinehub.co/shortcut/16422/ , https://routinehub.co/shortcut/17052/ , https://routinehub.co/shortcut/17115/
- https://developer.apple.com/forums/thread/757460
- https://discussions.apple.com/thread/254151194
- https://help.yondercard.com/en/articles/39095-why-am-i-receiving-two-ios-notifications-when-i-make-a-transaction-through-apple-pay
