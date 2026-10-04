# Compliance check before TestFlight — 4 Oct 2026

Checked on 4 Oct 2026: the repo at `main` `2461eca`, the live site sortd.page, and Apple's
current pages. Three read-only passes (app, site, Apple rules). Where something could not be
confirmed on an Apple page it says "not verified". None of this is legal advice.

## Fine as is

| Area | What was checked |
|---|---|
| Build | 1.0 (1), iOS 26.0 target, Xcode 27.0, iPhone only, portrait, Finance category |
| Export | `ITSAppUsesNonExemptEncryption = NO`. Only Apple's own crypto (HTTPS, CloudKit, Keychain, CryptoKit) |
| Flags | Release: `SORTD_SIGNIN SORTD_ICLOUD`. No session replay. Every `SPEND_*` escape is inside `#if DEBUG` |
| Permissions | Camera and Face ID strings only, both say why. No tracking, no ATT, no push, no background modes |
| Privacy manifest | `Spend/PrivacyInfo.xcprivacy` matches the code (UserDefaults CA92.1). PostHog 3.82.0 and Sentry 9.29.0 ship their own. Neither is on Apple's SDK list |
| Sign-in | Optional. Apple beside Google (4.8). Google scopes are `openid email` only. Gmail is gone |
| Tips | Row hides until the three products exist. Nothing is unlocked. No outside payment link |
| Site | Live pages are byte-identical to `site/`. `/privacy`, `/terms`, `/support` return 200. Every URL the app opens works, `/help#…` redirects keep their anchors |
| Trademarks | Footer credit line on every page. No Apple badge or logo. No Apple mark in the app name or icon |
| CloudKit | `Backup` record type is in Production |

## Fixed with this note (before the first upload)

1. **Account deletion (5.1.1(v)).** The account Worker was not deployed and `ACCOUNT_WORKER_URL`
   was empty, so Delete Account could not revoke a Sign in with Apple token or remove the usage
   record. Raj chose to deploy the Worker before the upload.
2. **Worker PostHog host.** `worker/wrangler.jsonc` pointed at the EU API host. The project is on
   the US cloud. Now `https://us.posthog.com`. Still not verified with a real key.
3. **Hidden developer menu (2.3.1).** Settings › About, 7 taps on the version, works in Release
   and has "Crash Now". One line in `docs/AppReviewNotes.md` now tells the reviewer.
4. **Secrets in the archive.** A fresh worktree has no `Secrets.xcconfig`. Without it the build
   ships with analytics and crash reports off and the EU PostHog host. Copy it in before archiving.
5. **Stale docs.** The checklist said "no Sortd accounts". HANDOVER listed `SORTD_GMAIL`.

## Before the App Store, not needed for TestFlight

| # | Item | Rule or source |
|---|---|---|
| 1 | Privacy policy names no person or business, only "the makers of Sortd" | 5.1.1(i); Australian and Singapore privacy law |
| 2 | Privacy policy does not name PostHog or Sentry ("names on request") | 5.1.1(i), 5.1.2(i) |
| 3 | Usage data is on by default outside the EU/UK/CH, with no first-run question | 5.1.1(ii): consent "even if such data is considered to be anonymous" |
| 4 | sortd.page home is behind the "found us early" gate. The app's Website row opens it | 2.1(a) working URLs |
| 5 | Terms have no governing-law line | general |
| 6 | `/beta` promises one email, soon.sortd.page says two. No unsubscribe line in the emails | Australian Spam Act (ACMA) |
| 7 | Listing says Apple Watch works. The app says it does not on iOS 26 | 2.3 accurate metadata |
| 8 | App name: handoff says "Sortd", listing doc says "Sortd Money" | 2.3.7 (30 characters) |
| 9 | Tips: Paid Apps agreement, tax, banking, three consumables, attached to the first version | 3.1.1, 2.1(b) |
| 10 | App Privacy label: add PostHog's "Other Usage Data"; check Xcode's privacy report for linked vs not linked | App privacy details |
| 11 | Age rating with the new social-media questions (answer none) | Apple news 9 Jul 2026 |
| 12 | EU DSA trader status. Trader details (address, phone, email) are shown publicly | App Store Connect Help |
| 13 | 6.9" screenshots, 1 to 10 | Screenshot specifications |
| 14 | Untick Apple Silicon Mac and Vision Pro unless tested | Pricing and Availability |
| 15 | Finance rule 3.2.1(viii) names "money management"; Raj is an individual. How Apple reads a tracker: not verified. Keep the "never holds or moves money" line in the notes | 3.2.1(viii), 5.1.1(ix) |
| 16 | Gate the developer menu, or keep telling the reviewer | 2.3.1 |
| 17 | `scripts/preflight.sh --appstore` greps the whole pbxproj for `SORTD_REPLAY`, so the Debug line trips it | repo |
| 18 | Year-end encryption self-classification report: whether it applies is not verified | Apple export doc; BIS |
| 19 | Trademark check on "Sortd" ("Get Sortd" is registered in Australia) | `Brand/README.md` |
| 20 | US state age laws (Texas, Utah, Louisiana): whether a 4+ tracker must use the Declared Age Range API is not verified | Apple news 2026 |

## Added later on 4 Oct

- **Bundle ID** is now `com.kameshraj.sortd`. Raj wanted "sortd", and it cannot change once the
  record exists.
- **Store name.** "Sortd" alone is taken (Sortd | Shopping Wishlist App, Sydney). The record is
  "Sortd: Spending Tracker". Research notes: the name carries the most search weight (ASO firms,
  not Apple); each word should appear once across name, subtitle and keywords; Apple marks stay
  out of the name. No public search-volume numbers were found for "spending tracker".
- **"Sorted" in finance.** An Australian finance app "Sorted" exists and its owner holds the marks
  "SORTED BUSINESS" (AU 1820139) and "SORTED SERVICES" (AU 1818579). The registers were not
  searched live. Check before the public launch. Not legal advice.
- **Site vs store name.** sortd.page titles say "Sortd Money". Raj to decide whether to change them.
- **`SortdTips.storekit` ships inside the app bundle.** Harmless test data; take it out of the
  target before the App Store build.
- **ITMS-90626.** App Store Connect refused build 1 because two App Intent descriptions said
  "Apple Pay". Intent titles, descriptions and phrases must not contain "apple". Reworded; preflight
  checks it now.
- **Review notes** were rewritten to what a reviewer cannot find by tapping (Apple: "specific
  settings, user account information, or special instructions").

## TestFlight facts used

- Internal testers: up to 100 App Store Connect users, no review.
- External testers: up to 10,000. The first build goes to Beta App Review. Plan 1 to 6 days.
- External needs: beta description, feedback email, review contact with phone in + format,
  sign-in details if there is a login (ours is optional: "not required"), notes up to 4,000 bytes,
  What to Test.
- Builds last 90 days. Each upload needs a new build number.
- TestFlight uses production CloudKit and production App Attest.
- App Privacy label, age rating, DSA status and screenshots are for the App Store, not TestFlight.

## Sources

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Upcoming requirements: https://developer.apple.com/news/upcoming-requirements/
- TestFlight overview: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- Test information: https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/
- Account deletion: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Export compliance: https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- Third-party SDK list: https://developer.apple.com/support/third-party-SDK-requirements/
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Apple trademarks: https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
- DSA trader: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
- Earlier research: `docs/research/2026-10-03-testflight-requirements.md` on branch `applepay-bank`
