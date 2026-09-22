# Pro and payments — Sortd

Written 22 Sep 2026. How Sortd Pro actually works, how to check who's paying, how to hand out
free Pro with Offer Codes, and why homemade unlock codes can't be used in the real App Store
build. Every fact has an official source; anything I couldn't confirm from Apple's own docs says
so.

## How Pro works

Sortd Pro is sold entirely through **StoreKit 2**, on-device — two subscriptions (monthly,
yearly) and one lifetime purchase (`ProStore.swift`). There's no Sortd account and no server:
entitlement comes straight from the signed transactions StoreKit gives the app.

**Cross-device:** a purchase (subscription or the lifetime unlock) is tied to the buyer's **Apple
ID / App Store account**, and StoreKit restores it automatically on their other devices signed
into the same account — no code needed for that part; it's how the App Store account system
works.
Source: [Restoring purchased products](https://developer.apple.com/documentation/storekit/in-app_purchase/restoring_purchased_products) ·
[Supporting Family Sharing in your app](https://developer.apple.com/documentation/storekit/supporting-family-sharing-in-your-app)

**Family Sharing** is a separate, opt-in switch, turned on per in-app purchase in App Store
Connect — once on for a product it can't be turned back off for that product. Turning it on for
Sortd Pro's products would let up to five family members share one purchase.
Source: [Turn on Family Sharing for In-App Purchases](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases) — **not currently turned on for Sortd's products; a decision to make, not something already done.**

## How to check who's paying

In App Store Connect (needs the Admin, Finance or Sales role):

- **Sales and Trends** — units, proceeds and refunds by day, product and country. The
  closest thing to "how much money came in today".
- **Subscriptions report** (under Trends → Subscriptions Summary) — active subscriber count,
  retention/renewal rate, intro-price conversion rate, proceeds rate (Apple's cut is 30% in a
  subscription's first year, dropping to 15% after 12 consecutive months — or 15%/10% under the
  Small Business Program, see `docs/BetaPlaybook.md` §13), and event counts: activations,
  cancellations, conversions, reactivations, refunds, renewals, billing retries.
Source: [View subscription data](https://developer.apple.com/help/app-store-connect/view-sales-and-trends/view-subscription-data)

That's enough to answer "how many people pay, and how much" without building anything.

**Optional, later — App Store Server Notifications V2.** This is a real, current Apple feature:
a server-to-server feed of purchase-lifecycle events (purchases, renewals, offer redemptions,
refunds, and more) that Apple pushes to a URL you provide. It needs your own small server to
receive it — for Sortd, that would mean standing up a small Cloudflare Worker with an HTTPS
endpoint, verifying Apple's signed payload, and storing just enough to count subscribers (for
example `originalTransactionId` and current status) — not names, not emails, nothing from the
app itself. This is worth doing once there's real revenue to watch in closer to real time than
the daily reports above; it is **not built**, and this playbook only describes the shape of it,
deliberately, rather than building it now.
Sources: [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications) ·
[App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v2)

## Offer Codes — giving people free Pro

Offer Codes are Apple's official way to give someone a product free or discounted, redeemed
through the real App Store — unlike a homemade code (see below), Apple tracks redemption and
enforces the limits for you.

**Confirmed current scope:** offer codes now work for **all four in-app purchase types** —
consumables, non-consumables, non-renewing subscriptions, and auto-renewable subscriptions. So
Sortd's **lifetime purchase (non-consumable) is supported**, not just the two subscriptions. (The
subscription case has been supported longer; non-consumable support is the newer addition — if
you're on an older App Store Connect / Xcode toolchain, double-check it shows the option for the
lifetime product specifically.)
Source: [Supporting offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app) ·
[Create offer codes for In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases)

**Two kinds of code:**
- **One-time-use codes** — Apple generates a batch for you (500 to 25,000 per batch), each code
  works once. Good for "here's a code, use it".
- **Custom codes** — you choose the code text yourself (e.g. `THANKYOU`), reusable up to a limit
  you set, with an optional expiry date. Good for handing the same code to a group, like beta
  testers or a newsletter.

**Limits:** up to **10 active offers** per app at once, up to **1,000,000 codes per app per
quarter**, one-time batches capped at **25,000 codes** and a maximum **6-month** validity window.
Requires the app to be Ready for Distribution and the in-app purchase Approved.
Source: [Create offer codes for In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases)

**How someone redeems one:** either inside the app via the StoreKit redemption sheet (Apple's own
"Redeem Code" screen), or by tapping a redemption link (`apps.apple.com/redeem?...`) you hand
them directly — no app-side code needed to support this, it's built into StoreKit and the App
Store app.
Source: [Supporting offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app)

**For Sortd specifically:** once there's a real App Store build (not the `SORTD_BETA` build,
which already gives testers Pro for free), Offer Codes are the right tool for "give this specific
person free Pro" — pick custom codes for named individuals (traceable, revocable by not handing
out more) and one-time batches for a wider giveaway.

## Why our own secret codes can't unlock Pro in the App Store build

`CompedPro`'s own codes (see `docs/AppStoreChecklist.md`) are a `SORTD_BETA`-only escape hatch —
they must not, and structurally cannot survive into the App Store build, because Apple's review
guidelines forbid it outright:

> "If you want to unlock features or functionality within your app... you must use in-app
> purchase. Apps may not use their own mechanisms to unlock content or functionality, such as
> license keys, augmented reality markers, QR codes, cryptocurrencies and cryptocurrency wallets,
> etc."
Source: **Guideline 3.1.1 (In-App Purchase)**, [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

In plain terms: once Sortd is a real paid app, any way of unlocking Pro that isn't a StoreKit
purchase or an Apple Offer Code is against the rules and a rejection risk. Offer Codes exist
precisely so a developer can still give Pro away for free, through Apple's own system, without
breaking this rule.

## Refunds and revocations

Apple — not Sortd — decides and processes refunds; the developer finds out after the fact, not
before. Two ways to see it:

- **Reports:** refunds show up in Sales and Trends and the Subscriptions report (above).
- **App Store Server Notifications V2** (if built, see above): a `REFUND` notification type
  carries the revoked transaction's details (`originalTransactionId`, `productId`,
  `revocationDate`, `revocationReason`).
Sources: [Handling refund notifications](https://developer.apple.com/documentation/storekit/handling-refund-notifications) ·
[notificationType](https://developer.apple.com/documentation/AppStoreServerNotifications/notificationType)

Without a server, `ProStore.swift` already handles this the right way for a no-backend app:
StoreKit 2 verifies each transaction on-device and drops anything carrying a `revocationDate`, so
a refunded purchase stops unlocking Pro the next time the app checks entitlements — it just isn't
*instant* (it catches up next launch, not the second Apple processes the refund). That gap is
exactly what Server Notifications V2 would close, described but not built above.

There's no separate "approve this refund" step for the developer to do — Apple/the App Store
handles the whole refund process with the customer directly.
