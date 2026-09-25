# Overhaul 4: sign in with Apple or Google (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`.
**Decided on 25 Sep (Raj):** build it with one stateless revoke function and no other server. It comes after sub-spec 3.

## Problem

Raj (relayed by the router, 25 Sep) said yes to both Apple and Google. He wants sign-in to give:
1. a backed-up account;
2. an identity for support;
3. analytics tied to the user (PostHog, sub-spec 2).

Sortd has no server, so a sign-in on its own holds nothing. Sub-spec 3 already covers point 1 without any sign-in. What sign-in adds is identity: one PostHog person across a user's phones, and a way to find that person when they ask for support.

Today `GoogleAuth.swift` is only a Gmail connection. It is our own OAuth over `ASWebAuthenticationSession` with PKCE, **not the GoogleSignIn SDK**. It asks for `openid email gmail.readonly`, so Google already returns an `id_token` with a stable `sub`.

## Options

| | A. Local identity, Apple + Google (decided) | B. Apple only | C. Backend accounts (Firebase Auth or Supabase) |
|---|---|---|---|
| What | `ASAuthorizationAppleIDProvider`, plus a separate Google request for `openid email` only. The ID (Apple `user`, Google `sub`) goes in the Keychain | Same, Apple only. Google stays Gmail-only | Accounts and data on a server |
| Guideline 4.8 | Met: Apple sits beside Google | Not triggered: Gmail connect falls under the mail-client exception | Met if Apple is offered |
| 5.1.1(v) deletion | In-app delete required. The Apple token revoke needs a server-side `client_secret` JWT, so **one stateless function** (Cloudflare Worker, stores nothing) | Same function | Server does it |
| No server of ours | Almost: one revoke function, no user data | Same | **No** |
| Label | User ID, linked (already declared by sub-spec 2) | Same | Many types, linked |
| Work | 4 d + Worker | 3 d + Worker | 3+ weeks, CASA, App Check |

## Recommendation

A, after sub-spec 3.

Keep the Google identity request separate from the Gmail one. `openid email` are not restricted scopes, so the identity request cannot slow the Gmail review. **Not verified** with Google.

First step: `AccountStore` with sign in, sign out and delete, behind a protocol, with no UI yet.

## Protection

- **Tokens.**
  - There is no server, so no ID token is verified on one.
  - On the device, the token is trusted only as it arrives from Apple's `ASAuthorizationController`, or directly from Google's token endpoint over TLS. Google's rule: validate ID tokens "unless you know that they came directly from Google".
  - If a backend ever uses these IDs, it must validate the tokens against Apple's and Google's public keys.
  - Refresh tokens stay in the Keychain.
- **Secrets.** The Worker's secret store holds the Apple private key and the PostHog personal key (for deleting a person). Neither goes in the app or in git.
- **Abuse of the Worker.**
  - It acts only on a request that carries a valid Apple authorization code, or a signed-in hash, for our client ID.
  - A per-IP rate limit on Cloudflare, and a tight free-plan budget.
  - App Attest if abuse shows up.
  - Cloudflare limits and prices: **not verified**.
- **Account lifecycle** (all in the app, on one screen):
  - **Sign out:** forget the ID, and call PostHog `reset()`. Data on the phone stays.
  - **Delete account:**
    - revoke the Apple token (Worker), or the Google token (`GoogleAuth` revoke exists: `retryPendingRevokes`);
    - ask the Worker to delete the PostHog person;
    - clear the Keychain and call `reset()`;
    - offer "also delete purchases on this phone and in iCloud" (the Delete All Data path).
  - **Export:** CSV and backup already exist.
- **Analytics.** Call `identify` with `sha256(appSalt + provider + subject)` only. Never the email or name. `appSalt` is `Analytics.accountSalt`, one fixed string compiled into the app (not a secret; it only stops a plain lookup of a known subject). A per-phone salt would make one person two PostHog persons on two phones, and Delete All Data would wipe it. `AccountStore.hash` and `Analytics.signedIn` use that one function and salt.
- **Delete order.** The provider and the Worker are asked first, with the hash made from the still-signed-in account; the local wipe comes after. A job that could not be sent is queued in `accountPendingDeletes` with the hash inside it, never recomputed.

## Files

- New `Spend/Services/AccountStore.swift`: the protocols, `AccountStore`, `KeychainAccountStore` (own Keychain service, this device only), `WorkerRevoker` (URL from `ACCOUNT_WORKER_URL` in `Config.xcconfig`; empty means every delete is queued), `AnalyticsIdentitySink`, `AppleCredentialChecker`, `AppleIdentityProvider`, `GoogleIdentityProvider`. Always compiled.
- The account screen and the Settings row are behind a new `SORTD_SIGNIN` compile flag, off in both configs (the capability needs the paid account). Turn on: Xcode > Spend target > Build Settings > Active Compilation Conditions > add `SORTD_SIGNIN`.
- `WorkerRevoker` follows `2026-09-25-account-worker.md`: `POST /v1/challenge` (route and the body's sha256), App Attest on the challenge (a fresh key each time, `X-Attest-*` headers), then `/v1/apple/revoke` with a fresh authorization code (Apple's sheet again at delete time) or `/v1/posthog/delete-person` with the hash. 429, 503 and network errors are retried; 502 and any 4xx are dropped with the reason shown. An Apple revoke is never queued (the code lives five minutes): the user sees Apple's manual steps instead. A Google identity revoke is skipped when Gmail is connected for the same address, since one revoke ends the whole grant.
- The queue (`accountPendingDeletes`) holds kind, provider, sha256(subject) and the identity hash: never the subject or the email. Delete All Data keeps the queue across its defaults wipe and queues the PostHog person delete when signed in.
- Delete order for analytics: `reset()` first, so nothing is sent under the person being deleted, and no `signed_out` event. Sign Out sends `signed_out` then `reset()`.
- `Spend/Services/GoogleAuth.swift`: `identityScopes` and the identity-only `signInForIdentity()`; `revokeIdentity()` for delete.
- `Spend/Services/Keychain.swift`, `Spend/Services/Analytics.swift` (identify and reset).
- `Spend.entitlements`: the Sign in with Apple capability. **Needs the paid account.**
- New `Spend/Views/Settings/AccountSettingsView.swift`; `Spend/Views/SettingsView.swift`, `Spend/Views/DataControlsView.swift`.
- Worker: a new repo folder, outside `Spend/`, with its own spec.

## Test plan

- Sign in (a fake Apple provider returns user "A") → `AccountStore.current?.id == "A"`, stored in the Keychain, and `identify(hash("apple", "A"))` is called once.
- Google identity sign-in asks for exactly `openid email`, never `gmail.readonly`.
- Sign out → no account, the purchase count is unchanged, and `reset()` is called.
- Delete account, fake revoker succeeds → the Keychain is empty, `reset()` is called, and revoke and person-delete are each called once.
- Delete account, revoker offline → the account is removed on the phone. Revoke and person-delete are queued and retried at the next launch (the same pattern as `GoogleAuth.retryPendingRevokes`).
- The hash for account "A" is the same on two installs, and never contains "A" or the email.
- Apple credential state is `revoked` at launch → the user is signed out quietly.
- `ui-driver`: the account screen signed in and out; the buttons meet the HIG; AX5; VoiceOver.
- Device only: real Apple and Google sign-in; delete, then sign in again.

## Gate

- Sub-spec 3 has shipped.
- Paid enrolment is active.
- The Worker's spec is approved.

## Sources (read 25 Sep 2026)

- [App Review Guidelines 4.8, 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/)
- [Offering account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- `client_secret` JWT for revoke: [Apple, creating a client secret](https://developer.apple.com/documentation/accountorganizationaldatasharing/creating-a-client-secret) and [forum 707545](https://developer.apple.com/forums/thread/707545). Apple's revoke page did not render, so this is **not verified**.
- [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect)
- [PostHog identify and reset](https://posthog.com/docs/product-analytics/identify)
- [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)
- The `ASAuthorizationAppleIDProvider` page did not render, so the API names are **not verified** this session.
