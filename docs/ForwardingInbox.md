# Forwarding inbox (receipt forwarding without Google sign-in)

Written 22 Sep 2026. Option C from `docs/ReceiptSourceOptions.md`, built and tested,
**not deployed and not wired into the app**. It is not in the first beta build.

The idea: each iPhone gets a private address like `r7k2x9…@in.sortd.page`. The person
sets Gmail (or Outlook) to forward receipts and bank alerts there. Our server encrypts
each email to that phone's key the moment it arrives and keeps only the ciphertext, for
at most 24 hours. The phone downloads it, decrypts it, reads it with the same parsers
as Gmail sync, and deletes it from the server.

No Google OAuth, no restricted scope, no CASA. Google only verifies that the person
owns the Gmail account (the forwarding confirmation email).

## Files

| Where | What |
|---|---|
| `inbox/` | The `sortd-inbox` Cloudflare Worker. Own `wrangler.jsonc`, own npm packages, own tests. Separate from `site/`. |
| `inbox/src/email.js` | Inbound mail: checks, DKIM, trims the email down, encrypts, stores. |
| `inbox/src/dkim.js`, `dns.js` | DKIM verification (RFC 6376/8301/8463) and DNS-over-HTTPS lookups. |
| `inbox/src/api.js` | The app's API: register, list, delete, turn off. |
| `inbox/src/setup.js`, `filters.js` | `https://inbox.sortd.page/setup` and the Gmail filter file. |
| `inbox/src/hpke.js` | HPKE seal (the server never has a private key). |
| `Spend/Services/InboxCrypto.swift` | The phone's key (Secure Enclave) and HPKE open. |
| `Spend/Services/InboxClient.swift` | HTTP client for the API. |
| `Spend/Services/ForwardingInbox.swift` | Turn on/off, check for mail, read and log it. |
| `Spend/Views/ForwardingInboxView.swift` | The setup screen. Not linked from Settings yet. |
| `SpendTests/ForwardingInboxTests.swift` | Swift tests. |

## How it works

```
 Gmail / Outlook                     Cloudflare (sortd-inbox Worker)                    iPhone
 ───────────────                     ───────────────────────────────                    ──────
                                                                      1. Turn on: make P-256 key in the
                                                                         Secure Enclave. POST public key
                         ┌──────────── POST /api/inbox/register ◄────────────────────────────┘
                         │  make random address + token,
                         │  KV a:<sha256(address)> = {pk, sha256(token)}   (180-day expiry)
                         └─────────────► { address, token } ─────────────► Keychain (this device only)

 2. Filter: "receipt OR bank
    alert" -> forward to address
         │  SMTP
         ▼
 Email Routing (in.sortd.page, catch-all -> Worker)
   Cloudflare's own checks: SPF or DKIM must pass,
   sender's DMARC policy enforced
         │
         ▼
 email():  unknown / disabled address?  -> reject (bounce)
           > 10 MB, > 30/min, > 100 waiting? -> reject
           parse MIME in memory
           verify DKIM ourselves -> list of proven domains
           keep only: from, subject, date, message-id, ONE body (text, else HTML), proven domains
           HPKE-seal to the phone's public key (aad = message id)
           KV m:<hash>:<id> = ciphertext   (24-hour expiry)
           log: event name, 8-char hash tag, size bucket. Nothing else.

                                                                      3. On open: GET /api/inbox/messages
                         KV ciphertext ─────────────────────────────────► decrypt in Secure Enclave
                                                                         read with EmailParsers / BankAlerts /
                                                                         GenericReceipts / ReceiptAI (same as Gmail)
                                                                         EmailSync.importRecords -> TransactionLogger.log
                         ◄──────────── DELETE /api/inbox/messages/:id ─── (only after it's saved)

                                                                      4. Turn off / new address:
                         ◄──────────── DELETE /api/inbox ──────────────── mailbox and everything waiting deleted;
                                                                         mail to the old address bounces
                                                                         (within ~1 min: KV caches reads)
```

### Crypto

- HPKE base mode (RFC 9180): DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM.
  CryptoKit calls it `HPKE.Ciphersuite.P256_SHA256_AES_GCM_256`. `info` = `sortd-inbox/v1`.
  The message id is the AAD, so a ciphertext moved to another id fails to open.
- The Worker uses `@hpke/core` 1.9.0 (WebCrypto only, no other dependencies).
- **Interop is proven both ways**, with fixed vectors in `inbox/test/fixtures/`:
  - the official RFC 9180 vector for this suite: the Worker reproduces it byte for byte,
    and CryptoKit opens it;
  - `js-to-swift.json`: made by the Worker's `seal()`, opened by CryptoKit in the Swift tests;
  - `swift-to-js.json`: made by CryptoKit (`inbox/scripts/make-swift-vector.swift`), opened by the Worker's tests.

### Auth

- Bearer `<address-local-part>.<token>`. Token = 32 random bytes. The server stores
  SHA-256 of the address and of the token, never either one, and compares in constant time.
- Registration is rate limited per IP (5/min). No account, no email, no name.

## Changes from the brief, and why

1. **API on `inbox.sortd.page`, not `sortd.page/api/inbox`.** The site Worker already runs
   on every `sortd.page/api/*` request, and a Worker custom domain takes precedence over
   routes, so a second Worker can't share that path without editing `site/`. A separate
   hostname keeps the two Workers (and their risks) apart. Mail stays on `in.sortd.page`.
2. **P-256, not X25519.** The Secure Enclave only does P-256, and it's worth it: the private
   key can't be copied off the phone, even by us or from a backup. The simulator has no
   Secure Enclave, so there it's a software key in the Keychain (this device only).
3. **The Worker encrypts a trimmed email, not the raw message.** It keeps only what the
   parsers read: sender, subject, date, message id, one body (plain text if there is any,
   else HTML), and the proven domains. Attachments, other headers and recipients (which
   include the person's own Gmail address) are never stored, even encrypted. The raw
   message exists only in the Worker's memory.
4. **DKIM is verified in the Worker.** Cloudflare doesn't give Email Workers any SPF/DKIM/DMARC
   results: no `Authentication-Results` header reaches the Worker (open issue,
   https://github.com/cloudflare/workerd/issues/6740, 7 May 2026). The app's bank parsers
   need to know the bank really sent it, so `dkim.js` checks signatures itself.
   It's tested against the signed example in RFC 8463 (someone else's implementation).
   Sortd's extra rules: the signature must cover From **and Subject** (the parsers read
   amounts and "refund" from the subject), and if From, Sender, Subject, Date, Message-ID,
   MIME-Version, Content-Type or Content-Transfer-Encoding appears twice, nothing is proven.
   (DKIM checks the bottom copy of a header; a mail parser reads the top one, so a fake
   Subject added above a real signed bank email would otherwise pass. Found in review.)
   A DMARC `p=reject` fallback exists but is **off** (`TRUST_CLOUDFLARE_DMARC`) until the
   owner check below shows Cloudflare rejects DMARC failures before the Worker runs.
5. **Address = 24 characters, 120 random bits**, from `abcdefghijkmnpqrstuvwxyz23456789`
   (no 0/1/l/o look-alikes). Exactly 32 symbols, so no bias.
6. **Rate limits use Cloudflare's Rate Limiting binding** (30 mails/min per address,
   120 API calls/min, 5 registrations/min per IP) plus a hard cap of 100 messages waiting
   per address. That also caps a day's storage per address. KV counters would add a
   write per email and KV is only eventually consistent.
7. **Unused mailboxes expire after 180 days** (KV expiry, refreshed at most once a day when
   the phone checks). Covers deleted apps and lost phones.
8. **Messages the phone can't decrypt are left to expire, not deleted.** Deleting only after
   a successful decrypt and save means a bug can't lose mail; the list is paged with a
   cursor so leftovers can't hide newer mail.
9. **No push.** The brief's option C mentioned a silent push. It needs APNs keys on the
   server and a device token (more data on the server). The app checks on open instead.
   Background App Refresh is a follow-up (see "Wiring").
10. **Setup page puts the address after `#`.** The QR code opens
    `https://inbox.sortd.page/setup#a=<address>`. Browsers never send the part after `#`
    to the server, so the address isn't in any request log. The page builds the Gmail
    filter file in the browser.
11. **Gated on Pro, like Gmail receipts** (`syncIfOn` checks `ProStore.shared.isPro`).
    Owner's call. If it stays Pro-only, a lapsed subscription means forwarded mail expires
    unread after 24 hours.

## What is stored, where, for how long

| Data | Where | Readable by us? | Kept |
|---|---|---|---|
| Forwarded email, trimmed | KV, HPKE ciphertext | No (only the phone's key opens it) | Until the phone reads it, max 24 h |
| Raw email | Worker memory while handling it | Yes, for milliseconds | Not stored |
| SHA-256 of address, SHA-256 of token, public key, created/last-seen times | KV | Hashes only | Until turned off, or 180 days unused |
| Worker logs | Cloudflare Workers Logs | Event name, 8-char hash prefix, size bucket, DKIM yes/no | Cloudflare's log retention |
| **Email Routing activity log** | **Cloudflare dashboard / GraphQL** | **Yes: from, to, subject, message id, SPF/DKIM/DMARC results, status** | **31 days** (Cloudflare's, not ours) |
| Private key | iPhone Secure Enclave | No | Until turned off or the app is deleted |
| Purchases read from the emails | iPhone (SwiftData) | No | Like any other purchase |

The Email Routing log is the biggest privacy gap and we can't switch it off from the Worker:
https://developers.cloudflare.com/email-routing/get-started/email-routing-analytics/
says it records "from, to, subject, status, action, ruleMatched, messageId, errorDetail,
dkim, dmarc, spf, isSpam" and keeps it for 31 days. "from" there is Gmail's forwarding
envelope sender, which contains the person's Gmail address. The privacy page must say so.

## Threat model

| Threat | What stops it | What's left |
|---|---|---|
| **Forged bank alert** sent straight to someone's address ("DBS: you spent $900") | The address is secret and unguessable. The Worker only lists a domain as proven with a valid DKIM signature by that domain covering From. The signature must also cover Subject, and a repeated From/Subject/Date/Content-Type (etc.) means nothing is proven. The app's bank parsers (`EmailParsers.isFrom`) need that domain. Refunds only come from exact-rule senders. | A forged *receipt* from an unknown shop can still be read by the general reader (same as Gmail today), marked "check the amount". A real, DKIM-signed email *replayed* (someone forwards their own genuine bank alert to your address) passes. If a bank doesn't sign Content-Type and its email has none, one can be added; the signed body bytes can't change, so this can only garble the text, not add to it. All need the address. |
| **Address guessing** | 120 random bits. Unknown addresses are rejected before anything else. | Spam to a leaked address. Fix: New Address. |
| **Stolen token** | Token is only on the phone (Keychain, this device only). Server keeps only its hash. Works only with the matching address. | Someone with both can read the ciphertext list (useless without the key) and delete or turn off. Can't decrypt. |
| **Server compromise / KV dump** | KV holds ciphertext and hashes only. No private keys anywhere on the server. | An attacker who changes the Worker code could read *new* mail in memory from then on, or insert fake messages (the server can encrypt to the public key). It can't read mail already stored. |
| **Cloudflare as processor** | It's the mail server; we can't avoid it seeing mail in transit. DPA: Cloudflare's standard. | Cloudflare's Email Routing log (31 days of from/to/subject). Cloudflare employees or legal requests could see mail in transit. Disclose it. |
| **Phishing via the Gmail confirmation** (attacker adds your Sortd address in *their* Gmail, then sends you a fake "confirm" with their real Google link and "from you@gmail.com") | Worker only marks mail from `forwarding-noreply@google.com`. The app shows the link and the "from" Gmail address only if google.com's DKIM signature proves Google sent it, and the link is `https://mail-settings.google.com/mail/vf-…`. Unproven: code only, with a warning. | A code typed into your own Gmail can't approve someone else's request, so an unproven code is harmless. If DKIM doesn't survive to the Worker (owner check 1), people get the code but no link. |
| **Mailbox flooding** | 30/min, 100 waiting, 10 MB each, bodies trimmed to 256 KB text / 768 KB HTML. | Up to ~100 MB/day per leaked address until it's reset. |
| **Harvest now, decrypt later (quantum)** | 24-hour retention limits what's there to capture. | P-256 isn't post-quantum. CryptoKit has X-Wing (ML-KEM + X25519) on iOS 26, but not in the Secure Enclave and not in `@hpke/core`. Revisit later. |
| **Lost phone / app deleted** | Key is device-only; mailbox expires after 180 days unused; mail after 24 h. | Mail keeps arriving (and expiring unread) until then. |

## Privacy page and App Store label (drafts; privacy.html not edited)

`privacy.html` says Sortd has no server. When this ships it needs a new section. Draft:

> **Forwarding inbox (optional).** If you turn on the forwarding inbox, Sortd gives your
> iPhone a private email address. Emails you forward to it go to Sortd's server, run on
> Cloudflare. The server encrypts each one to a key that only your iPhone has, and keeps
> only the encrypted copy until your iPhone downloads it, or 24 hours at most. We can't
> read it after it arrives. Before storing it, the server removes attachments and
> everything except the sender, subject, date and text.
>
> For a moment while it's being encrypted, the email is readable on the server. Cloudflare,
> which runs the mail server for us, keeps a record of each email's sender, recipient and
> subject for 31 days. We don't log any of that ourselves.
>
> Turning the inbox off deletes the address and anything waiting on the server straight
> away. An address you haven't checked for 180 days is deleted automatically.

Replace "Sortd has no server" with: "Sortd's server only holds forwarded emails, encrypted
so only your iPhone can open them, and only until your iPhone collects them."

**App Store privacy label** (conservative; the owner decides):
- Add **User Content › Emails or Text Messages**. Purpose: App Functionality. Not used for
  tracking. Apple's definition of "collect" is data we or our partners can access "for a
  period longer than what is necessary to service the transmitted request in real time".
  Our own copy fails that test (encrypted, unreadable), but Cloudflare's 31-day log of
  sender and subject doesn't. **Linked to the user: Yes** (the log contains the Gmail address).
  https://developer.apple.com/app-store/app-privacy-details/
- Nothing else changes: no account, no email address collected by the app itself.

**App Review notes:** explain the forwarding inbox, that it's optional, and give a demo
address with a few test receipts waiting.

## Cost

Prices from Cloudflare's pages on 22 Sep 2026:
- Inbound Email Routing: "Unlimited" on Free and Paid; Email Workers are billed as Workers.
  https://developers.cloudflare.com/email-service/platform/pricing/
- Workers Paid: $5/month minimum; 10M requests and 30M CPU-ms included, then $0.30/M and
  $0.02/M CPU-ms. Free plan: 10 ms CPU per invocation.
  https://developers.cloudflare.com/workers/platform/pricing/
- KV Paid: 10M reads, 1M writes, 1M deletes, 1M lists, 1 GB included; then $0.50/M reads,
  $5/M writes, deletes and lists. Free: 1,000 writes/day.
  https://developers.cloudflare.com/kv/platform/pricing/

**Use Workers Paid.** DKIM + MIME parsing + encryption of a large receipt can pass the Free
plan's 10 ms CPU limit, and KV Free stops at 1,000 writes a day.

My estimate (assumes 5 forwarded emails and 5 app opens per user per day; not measured):

| Users | Emails/month | KV writes | KV lists | Est. cost |
|---|---|---|---|---|
| 50 | 7,500 | ~8k | ~15k | $5/mo |
| 500 | 75,000 | ~80k | ~150k | $5/mo |
| 5,000 | 750,000 | ~760k | ~1.5M | ~$7.50/mo (lists over 1M: +$2.50) |

Whether an email invocation counts as a "request" isn't stated on the pricing page; the
estimate assumes it does. Rate Limiting binding pricing isn't listed either.

## Owner setup (when it's time; nothing here has been done)

1. **Workers Paid** on the Cloudflare account ($5/mo), if not already.
2. **KV namespace:** from `inbox/`: `npx wrangler kv namespace create INBOX`. Paste the id
   into `inbox/wrangler.jsonc` (replace `REPLACE_WITH_KV_NAMESPACE_ID`). Commit it.
3. **Deploy the Worker** from a clean checkout of the merged branch:
   `cd inbox && npm ci && npm test && npx wrangler deploy`. This also creates the
   `inbox.sortd.page` custom domain (HTTPS certificate is automatic).
4. **Email Routing on the subdomain:** dashboard › Compute › Email Service › Email Routing ›
   sortd.page › Settings › Subdomains › add `in` (so `in.sortd.page`). Cloudflare adds the
   MX and SPF records. https://developers.cloudflare.com/email-routing/setup/subdomains/
5. **Catch-all to the Worker:** Email Routing › `in.sortd.page` › Routing rules ›
   Catch-all address › Action "Send to a Worker" › `sortd-inbox` › enable.
   https://developers.cloudflare.com/email-routing/email-workers/enable-email-workers/
6. Don't add any other rules on `in.sortd.page`. `support@sortd.page` is unaffected
   (different domain).
7. **Wire the app** (below), build, and run the owner checks.
8. Update `privacy.html`, App Review notes and the privacy label before it ships.

## Owner checks after deploy (not possible before)

1. **DKIM reaches the Worker.** Turn on the inbox in a debug build, forward a real bank alert
   and an Apple receipt from Gmail. Check Now. They should log as purchases (the bank one
   needs DKIM). If bank alerts don't log but generic receipts do, Cloudflare is stripping
   DKIM-Signature before the Worker (the workerd issue lists it missing from `message.headers`;
   `raw` should still have it). Then see check 2.
2. **Cloudflare enforces DMARC before the Worker.** From a domain you control with
   `p=reject`, send an email with a forged From (e.g. `swaks` via a server not in that
   domain's SPF) to your inbox address. It should bounce and never reach the Worker. Only
   if it does, consider `TRUST_CLOUDFLARE_DMARC: "true"`.
3. **Gmail forwarding confirmation** shows in the app with the code and a working Confirm link.
4. **Gmail filter import:** does an imported filter keep `forwardTo`? The `forwardTo` property
   appears in lists of Gmail filter properties, but I found no Google page confirming it
   survives import. The setup page tells people to check and tick "Forward it to" if not.
   Gmail also needs the forwarding address confirmed *before* a filter can forward to it.
5. **Outlook.com "Redirect to"** keeps the original sender and DKIM (not confirmed).
   Microsoft may block forwarding to outside addresses on new consumer accounts.
6. Bounce text: send to a made-up address on `in.sortd.page`; Gmail should say it bounced.
7. Worker logs contain no addresses, senders or subjects.

## Wiring the app (after merge)

Three lines, left out on purpose so this branch doesn't touch shared files:
- Settings: `NavigationLink("Forwarding Inbox") { ForwardingInboxView() }`
- `SpendApp`'s `.task(id: scenePhase)`, after `GmailSync.syncAll`: `await ForwardingInbox.shared.syncIfOn(in: context)`
- `DataReset.deleteEverything`, before `Keychain.deleteAll()`: `await ForwardingInbox.shared.turnOff(deletePurchases: false, in: context)`
  (it's sync today; make it async or fire a `Task`), so a wiped phone doesn't leave a live mailbox.

Background App Refresh (follow-up): add `BGTaskSchedulerPermittedIdentifiers` =
`com.kameshraj.spend.inbox` to Info.plist, register a `BGAppRefreshTask` handler at launch
that calls `syncIfOn(in:)`, and reschedule it for ~1 hour. The key is usable after first
unlock, so it works in the background. Not built: it needs Info.plist and app-launch edits.

## Test plan

Automated (all passing on 22 Sep 2026):
- `cd inbox && npm test` — 58 tests in workerd with a local KV:
  HPKE (RFC 9180 vector reproduced and opened, CryptoKit ciphertext opened, wrong aad/key,
  bad keys); DKIM (RFC 8463 both signatures, relaxed whitespace, body/header tampering,
  over-signed From, missing/revoked keys, DNS failure, simple/simple, l=, rsa-sha1, expiry,
  short RSA keys, other-domain signatures, unsigned Subject, fake Subject/Content-Type added
  on top, several key records, b= blanking, DMARC policy); registration (hashes only, unique,
  180-day expiry, bad input, per-IP limit); auth (wrong token, other mailbox); unknown /
  malformed / wrong-domain addresses rejected; only ciphertext stored; 24-hour expiry;
  delete-on-fetch; mailbox isolation; DKIM domains in payload; two-From trick; DMARC flag;
  attachments dropped; HTML-only mail; size cap (including a lying rawSize); rate limit;
  100-waiting cap; turned-off mailbox rejects; errors reject instead of throwing; paging;
  Gmail confirmation detection and phishing cases; filter XML shape and escaping; setup page CSP.
- Xcode: `SpendTests/ForwardingInboxTests` — 15 tests: CryptoKit opens the RFC vector and the
  Worker's ciphertext; key storage round trip; decrypt → parse → log (NAB alert logged with
  DKIM; forged, other-domain and no-auth alerts not logged; general receipt; HTML body;
  same email twice); Gmail request validation (unsigned = code only); full turn on / sync /
  delete / turn off against a fake server; turn off waits for a check in progress; offline
  turn-off retried; paging; setup filter lists every bank the app reads.
- Full app suite on a cloned simulator: 301 tests pass (1 known issue, the existing
  grace-period test).

Manual, after deploy: the owner checks above, plus: iPhone real device (Secure Enclave key),
QR code opens the setup page on a Mac, filter download works in Safari/Chrome/Firefox,
VoiceOver on the setup screen, Dynamic Type at the largest size.

## Not verified / open

- Real Gmail and Outlook forwarding end to end (needs the deploy).
- Whether DKIM-Signature headers survive into `message.raw` (checks 1–2).
- `forwardTo` on Gmail filter import.
- iCloud Mail rules forwarding to an outside address.
- Whether Google Workspace accounts are allowed to forward (admins can block it).
- Whether the Secure Enclave key path works on a real device (simulator can't test it;
  the code path is the documented CryptoKit API).
