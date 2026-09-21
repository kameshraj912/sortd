# Google verification — Sortd (gmail.readonly)

Everything to paste into Google Cloud for the restricted-scope review. Project: `sortd-509110`.
Written 19 Sep 2026. Check Google's current form before submitting; field names can change:
https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification

## Status (20 Sep 2026)

- [x] Domain bought (sortd.page), site live, support@sortd.page forwarding set up
- [x] Search Console: domain verified (DNS TXT), sitemap submitted, home page indexing requested
- [x] Branding page saved: name, logo, links, authorised domain, support email (Google Group), contacts
- [x] Data Access: gmail.readonly (restricted) + email + openid
- [x] Audience: Testing, 2 test users
- [x] support@sortd.page forwarding verified (Cloudflare)
- [x] Demo video (unlisted): https://youtu.be/Lflj8rfZDwI (file in docs/demo/, not in git)
- [x] Branding verified and published by Google
- [x] Published to production; submitted for restricted-scope review 20 Sep 2026
      (use: Email reporting and monitoring; justification as below; CASA question asked in notes)
- [x] 21 Sep 2026: Google replied. Video rejected: "does not sufficiently demonstrate why" gmail.readonly
      is needed "or why narrower permissions cannot be used". Plan below under "Round 2".
- [x] 21 Sep: privacy page fix deployed (live, checked)
- [x] 21 Sep: new video recorded and edited: docs/demo/sortd-gmail-demo-v2.mp4 (5:58, captions)
- [x] 21 Sep: v2 uploaded (Unlisted): https://youtu.be/-cIUinevNfs (8.6 MB 604x1592 copy of the v2 file)
- [x] 21 Sep 2:33 pm AEST: replied on the Google thread (cc sortd-support group + support@sortd.page)
- [ ] Watch for Google's next email and reply fast
- [ ] CASA security assessment when Google asks (paid, yearly; see below)

## Round 2 — after the 21 Sep 2026 rejection

### What the first video missed

The first video (3m 57s, simulator) showed the consent screen, sync and disconnect. Gaps:

1. Gmail itself never appears. Google can't see that a Sortd entry came from a real email.
2. Nothing shows why `gmail.metadata` isn't enough (amount and shop are in the body).
3. "See access details" on the Gmail permission was never tapped, so the scope wasn't expanded.
4. Client ID was on a title card, not in the sign-in address bar.
5. Disconnect was shown in Sortd only, not in the Google Account.
6. Title card says "Sortd Money"; the consent screen says "Sortd". Use "Sortd" everywhere in the video.

### Fixed before recording

- `site/privacy.html` (21 Sep): added "No AI training" line and the Google Workspace API
  Limited Use sentence. Deploy: `cd site && npx wrangler deploy`.

### Set up before recording

- Test Gmail has at least: one food delivery receipt (Uber Eats/DoorDash), one app store
  receipt, one bank alert (NAB/SC etc.), ideally one refund. Leave one receipt **unread**.
- Disconnect Sortd from that Google account first, so the consent screen appears fresh:
  https://myaccount.google.com/connections
- Delete app data in Sortd so the list starts empty.
- Phone or simulator language: English.
- On the simulator there's no Gmail app; use Safari at mail.google.com (signed in to the test account).

### Shot list (one take, 3–5 minutes, captions on screen)

| # | Show | Caption |
|---|---|---|
| 1 | Sortd home screen | "Sortd: iPhone spending tracker. This video shows how it uses gmail.readonly." |
| 2 | Safari → mail.google.com: the receipts in the inbox. Open one Uber Eats receipt, scroll to the total. | "The shop and total are in the email body, not the subject." |
| 3 | Same email, ⋮ → Show original (headers). | "Headers only (what gmail.metadata gives): no amount. So gmail.metadata can't do this." |
| 4 | Sortd → Settings → Email Receipts → Connect Gmail. Pause on Sortd's explanation screen. | "User chooses to connect Gmail." |
| 5 | Google sign-in. Tap the address bar so the full URL with `client_id=` shows. | "OAuth client ID in the address bar." |
| 6 | Consent screen. Tap **See access details** on "View your email messages and settings". Hold 5 s. Tick the box. | "Only scope: gmail.readonly (plus email for the account name)." |
| 7 | Back in Sortd: Connected, N new. | "Sortd searches only for receipts and bank alerts." |
| 8 | Activity → open the Uber Eats entry. Then switch to Gmail, same email. | "Same shop, amount and date as the email." |
| 9 | Repeat 8 for the bank alert (and the refund if there is one). | "Bank alerts catch card spending with no receipt." |
| 10 | Gmail: the receipt left unread is still unread, nothing moved or deleted. | "Read-only. Sortd never sends, changes or deletes email." |
| 11 | myaccount.google.com/connections: Sortd listed, with its Gmail access. | "Access shown in the user's Google Account." |
| 12 | Sortd → Settings → Email Receipts → account → Disconnect. | "User can disconnect any time." |
| 13 | Refresh myaccount.google.com/connections: Sortd gone. | "Disconnect revokes access in Google." |
| 14 | End card | "All reading happens on the iPhone. Sortd has no server." |

What actually happened (21 Sep): the iOS sign-in sheet never shows the full URL, and Safari
redirects to /v3/signin so the client_id isn't readable there either. The video shows the client
ID in Cloud Console › Clients › Sortd iOS › Additional information instead. Mobile Gmail has no
"Show original"; its "Details" view (sender, to, date, subject) is used for the headers shot.
Unread proof used the Amazon "Ordered" email (18 Sep, A$36.98).

If the in-app sign-in sheet won't show the full URL at step 5: add a shot of
Google Cloud Console → Google Auth Platform → Clients with the same client ID, and say so in the reply.

### Reply (send on the same email thread)

See the chat on 21 Sep 2026 for two versions; the short one was chosen as default.

## Order

1. Buy `sortd.page`. Set up email forwarding: `support@sortd.page` → your Gmail.
2. Publish `site/` on the domain (see `site/README.md`). Check these open:
   - https://sortd.page/
   - https://sortd.page/privacy.html
   - https://sortd.page/terms.html
3. Google Search Console → add `sortd.page` → verify with the DNS TXT record. Use the same
   Google account that owns the Cloud project.
4. Google Cloud → Google Auth Platform → **Branding**: fill in the fields below.
5. Record the demo video (script below), upload to YouTube as **Unlisted**.
6. Google Auth Platform → **Audience** → Publish app ("In production"). Google then asks for
   the scope reason and the video. Paste from below.
7. Answer Google's emails quickly. Each reply restarts their clock.

## Branding fields

| Field | Value |
|---|---|
| App name | Sortd |
| User support email | sortd-support@googlegroups.com (Google Group you own; keeps your Gmail off the consent screen) |
| App logo | `Brand/google-oauth-logo-120.png` (120×120) |
| App home page | https://sortd.page/ |
| Privacy policy | https://sortd.page/privacy.html |
| Terms of service | https://sortd.page/terms.html |
| Authorised domain | sortd.page |
| Developer contact | support@sortd.page |

The app name and logo must match what the App Store listing shows.

## Scopes

- `openid`, `email` — to show which Gmail account is connected.
- `https://www.googleapis.com/auth/gmail.readonly` — restricted.

## Why Sortd needs gmail.readonly (paste this)

> Sortd is an iPhone budgeting app. When a user chooses "Connect Gmail", Sortd finds their
> purchase receipts and bank alert emails (for example food delivery, ride and app store
> receipts) and turns each one into a spending entry: shop, amount, currency, date and card.
>
> Sortd needs to read the body of these emails, because the amount and shop are in the body.
> `gmail.metadata` does not give access to the body, so it can't do this. Sortd never sends,
> changes or deletes email, so it asks only for read-only access.
>
> All reading happens on the user's iPhone. Emails go straight from the Gmail API to the phone.
> Sortd has no server, and no email content or purchase data is sent to the developer or
> anyone else. Sortd keeps only the purchase details it finds and each email's ID (so it isn't
> read twice). It does not keep copies of emails. The user can disconnect at any time in the
> app; this revokes the token with Google and can delete the purchases that account added.

## Security assessment (CASA)

Google requires an assessment for apps that can "access data from or through a third-party
server". Say this when asked:

> Sortd has no backend server. The iOS app talks directly to Google's OAuth and Gmail APIs from
> the user's device. The refresh token is stored in the iOS Keychain on that device. No Gmail
> data is transmitted to, or stored on, any server we operate. Please confirm whether a CASA
> assessment is required for this architecture.

If Google says yes anyway, it is a paid assessment by an approved lab. Decide then.

## Demo video script (2–3 minutes, unlisted YouTube)

Record on the iPhone (Control Centre → Screen Recording). Show the whole flow in one take.

1. Open Sortd. Show the app name on screen.
2. Settings → Email Receipts → Connect Gmail. Pause on Sortd's own explanation screen.
3. Google's sign-in page opens. Pick the test Gmail account.
4. On Google's permission screen, pause for 3 seconds. The app name "Sortd" and the Gmail
   read permission must be readable. (Google also wants the OAuth client ID visible once: open
   the sign-in page URL bar if possible, or show it in Google Cloud at the end of the video.)
5. Back in Sortd: show "Connected" and new purchases appearing.
6. Tap one purchase to show the shop, amount and date that came from a receipt.
7. Settings → Email Receipts → the account → Disconnect. Show that access is removed.

Say or caption: "Emails are read on this iPhone. Nothing is sent to our servers — Sortd has
none."

## After approval

- Remove the 100-test-user limit note from `docs/AppStoreChecklist.md`.
- Add Gmail to the App Store build and mention it in the review notes (with the test account).
