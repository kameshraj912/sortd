# App Store listing — Sortd Money

Paste into App Store Connect › App Information and the version page. Character counts are
checked by `docs/check_listing.py` (Apple's limits in brackets).

## App information

- **Name** (30): Sortd Money
- **Subtitle** (30): Apple Pay spending, logged
- **Primary category**: Finance
- **Secondary category**: Productivity
- **Age rating**: 4+ (no objectionable content, no user-generated content, no gambling)
- **Privacy policy URL**: https://sortd.page/privacy
- **Support URL**: https://sortd.page/support
- **Marketing URL**: https://sortd.page/
- **Copyright**: 2026 Kameshraj Gnanaprakasam (shown on the store for individual accounts)

## Promotional text (170)

Pay with Apple Pay and Sortd writes it down. See every subscription before it charges you. No bank login, no account, nothing leaves your iPhone.

## Description (4000)

Tap to pay. Sortd writes it down.

Sortd logs your Apple Pay purchases by itself: the shop, the amount and the card, a few seconds after you pay. No typing, no bank login, no account. Everything stays on your iPhone.

LOGGED FOR YOU
• Apple Pay taps log themselves through one Shortcuts automation. Setup shows a picture for every step and takes about three minutes.
• Works with every card in Apple Wallet, on iPhone and Apple Watch.
• Two cards from the same bank? Sortd tells them apart by their Apple Pay number.
• Add anything by hand in a couple of taps.

SEE WHERE IT WENT
• This month at a glance, by category and by card.
• Every card gets its own page.
• 30+ currencies, converted to your home currency at that day's European Central Bank rate. Handy if you live or travel across countries.
• Categories learn: change one purchase and that shop stays fixed.

SORTD PRO
• Gmail receipts: deliveries, rides, app stores and bank alerts, read from your inbox on your iPhone. Read-only.
• Receipt camera: point at a paper receipt and Sortd fills in the shop and total.
• Insights: this month next to last month, day by day.
• Subscriptions and bills: every repeat charge found, price rises flagged, and a reminder the day before it charges.
• Category budgets for eating out, shopping or anything else.

PRIVATE BY DESIGN
• No bank passwords, ever. Sortd only keeps the last 4 digits of a card.
• Your data is stored on your iPhone. We don't run a server, so there is nothing for us to see, sell or lose.
• No ads, no analytics, no trackers.
• Face ID lock, export everything as a spreadsheet, or delete it all in one tap.

PRICING
Sortd is free to use, including Apple Pay auto-logging. Sortd Pro is available monthly, yearly (with a free trial for new subscribers) or as a one-time purchase. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period, in Settings › Apple Account › Subscriptions.

Terms of Use: https://sortd.page/terms
Privacy Policy: https://sortd.page/privacy

## Keywords (100, comma-separated, no spaces)

budget,expense,tracker,spending,apple pay,receipt,subscription,bills,wallet,finance,currency,travel

## What's New (first version)

First release. Tap to pay, and Sortd writes it down.

## App Review contact

Fill in App Store Connect directly (name, phone, email). Review notes: docs/AppReviewNotes.md.

## Screenshots

`docs/screenshots/6.9/` — 1320 × 2868, light mode, in this order:
1. Your spending, logged by itself (Home)
2. Pay. It's logged. (Activity)
3. See how this month compares (Insights)
4. Catch every subscription (Recurring)
5. A page for every card (Card)
6. Set up in three minutes (Setup guide)

## In-app purchases (create in App Store Connect)

| Reference name | Product ID | Type | Price | Offer |
|---|---|---|---|---|
| Sortd Pro Yearly | com.kameshraj.spend.pro.yearly | Auto-renewable, group "Sortd Pro", level 1 | US$49.99 | Intro: 2-week free trial |
| Sortd Pro Monthly | com.kameshraj.spend.pro.monthly | Auto-renewable, group "Sortd Pro", level 2 | US$6.99 | none |
| Sortd Pro Lifetime | com.kameshraj.spend.pro.lifetime | Non-consumable | US$99.99 | — |

Turn on Family Sharing for all three. Each needs a display name, description and a review
screenshot of the paywall (docs/screenshots/paywall.png).

Note: Apple allows one introductory offer per subscription. The website's "$29.99 first year"
launch price can't be combined with the free trial as an intro offer; run it as an Offer Code
campaign instead, or drop it. The site should be updated to match whichever you choose.
