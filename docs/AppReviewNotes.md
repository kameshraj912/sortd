# App Review notes — draft

Paste the "Notes" part into App Store Connect › App Review Information › Notes. Keep it under
4,000 characters. Placeholders in [square brackets] are the ones only Raj can fill; see the list
at the bottom. Updated 26 Sep 2026: sign-in and iCloud backup are on, contact name and email
filled from the repo. Updated 4 Oct 2026: the ready-made shortcut (two triggers), no tip jar in this build, no session replay, the diagnostics menu line (rule 2.3.1). Updated 2 Oct 2026: Gmail removed (no Gmail steps or test account any more);
Budget Ring, Today and Recent widgets added.
Rewritten 4 Oct 2026 (saved in App Store Connect that day): cut from a feature tour to what a
reviewer cannot find by tapping, per Apple's App Review page. 1,812 bytes. Plain text, no markdown:
the box shows asterisks as typed.

---

## Notes

```
Thanks for reviewing Sortd.

WHAT IT IS
Sortd is a personal spending tracker. It does not hold, move or manage money. It does not connect to a bank and never asks for a bank login. Purchases are stored on the iPhone.

FASTEST WAY TO TEST
1. Open the app. On the first screen tap "Look Around With Sample Data". This loads about two months of sample purchases, so every screen has something in it.
2. To go back to an empty app, tap "Clear" on the banner at the top of Home.

NO ACCOUNT NEEDED
Every screen works without signing in, so there is no demo account. Sign in with Apple or Google is optional and lives in Settings > Account. Delete Account is on the same screen.

APPLE PAY LOGGING NEEDS A REAL CARD
Sortd cannot read Wallet. The user adds a Shortcuts automation instead: Settings > Purchase Sources > Apple Pay Logging > Get the Shortcut. When a card is tapped, the automation runs Sortd's "Log Wallet Tap" action and the purchase appears in the app. This only fires on a real iPhone with a card in Wallet, so it may not work in your test setup. Purchases can also be added by hand, scanned from a receipt, or imported from a statement. I can send a short screen recording of a real tap if that helps.

NOTHING TO BUY
Every feature is free. There are no in-app purchases in this build.

ONE HIDDEN MENU
Settings > About: tapping the version number 7 times opens a diagnostics menu (send a test event, send a test crash report). It is there for beta support only.

DATA
No ads and no tracking. Usage counts and crash reports never include purchases, shop names or amounts. They can be turned off in Settings > Privacy & Security > Privacy, and they start off in the EU/EEA, UK and Switzerland. This build does not record the screen.

CONTACT
Kameshraj Gnanaprakasam, support@sortd.page (phone given in App Store Connect only)
```

---

## Filled from the repo (26 Sep 2026)

- Contact name: Kameshraj Gnanaprakasam (the copyright holder in `docs/AppStoreListing.md`).
- Contact email: support@sortd.page (the support address on sortd.page and in the app).
- Contact phone: entered in App Store Connect only. Not kept in the repo, which is public.

## One thing that needs a phone in hand

Sign-in needs no demo account: it is optional and every screen works without it, and the
notes say so.

### 1. Optional: a short setup video

Not required for TestFlight. If Beta App Review asks how to test Apple Pay logging, reply with a
screen recording (under 90 s): Apple Pay Logging page › Get the Shortcut › the automation in
Shortcuts › a small Apple Pay purchase › the purchase in Activity.

## Before submitting

- [x] Notes are 1,812 bytes (limit 4,000), measured in the form on 4 Oct 2026.
- [ ] Optional: the setup video, only if Beta App Review asks.
- [x] The Apple Pay Logging page promises online Apple Pay only on iOS 27, from Wallet's
      notification (`ApplePaySetupSteps.scopeLine`), checked 4 Oct 2026.
