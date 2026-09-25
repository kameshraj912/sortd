# Account Worker: revoke Apple tokens, delete PostHog persons (25 Sep 2026)

Status: **draft for Raj. Nothing is built until Raj approves this doc (hard gate).**

Serves sub-spec 4 (`2026-09-25-free-app-overhaul-4-sign-in.md`), whose gate says "the Worker's spec is approved".
Worktree: `/Users/kameshraj/Developer/Sortd/.claude/worktrees/worker-spec`. Paths read are listed at the end.

## Problem

Deleting an account in the app must do two things the phone cannot do on its own:
- **Revoke the Sign in with Apple token.** Apple's `/auth/token` and `/auth/revoke` both need a `client_secret`: a JWT signed with our Sign in with Apple private key (.p8). That key must not ship in the app.
- **Delete the PostHog person.** This needs a personal API key (`phx_`), which can read and delete data. It must not ship either.

Google needs nothing here. `GoogleAuth.revoke` already calls `oauth2.googleapis.com/revoke` from the phone, with a retry list (`GoogleAuth.swift:151-169`).

## Options

| | A. One stateless Worker (recommended) | B. Worker + KV retry queue | C. No Worker |
|---|---|---|---|
| What | Cloudflare Worker `sortd-account`: a challenge route plus two action routes. Secrets in Wrangler secrets. Stores nothing | A, plus failed calls saved in KV and retried by a Cron Trigger | Clear the phone only. Tell the user to stop using Apple ID in Settings. Delete PostHog persons by hand on request |
| Work | about 3 d (App Attest checking is most of it) | about 5 d | 0.5 d (copy only) |
| Money | $0 on the free plan; $5/mo paid plan if the CPU limit bites (see Cost) | same, plus KV (limits not read) | $0 |
| Risk | App Attest parsing in TypeScript is new code for us | **Stores Apple refresh tokens and hashes on our server.** Breaks "stores nothing" and the overview's "no server of ours holds data" | App Review: Apple says apps "should use the Sign in with Apple REST API to revoke user tokens". Rejection risk is **not verified** |
| Gives up | A retry that survives the app being deleted right after | Simplicity, and the privacy story | Automatic erasure; the PostHog person stays until Raj acts |
| Files | new `worker/` only | `worker/` + KV binding + cron | `AccountSettingsView.swift` copy |

Guideline 5.1.1(v) itself does not mention Apple token revocation. It requires in-app deletion, and it says an app "may not store credentials or tokens to social networks off of the device". Apple's account-deletion page says apps with Sign in with Apple "should" revoke via the REST API. TN3194 gives a manual fallback (delete data, send the user to revoke by hand) only for when tokens are not available. So C is a fallback, not a plan. B's KV of refresh tokens runs against the spirit of that last 5.1.1(v) sentence.

## Recommendation

**A.** It keeps "no server holds data" true, matches what Apple asks for, and costs nothing on the free plan.
The app gets a fresh Apple authorization code at delete time (re-authenticate), so no Apple token is ever stored on the phone or the server.
First step: `worker/` skeleton with `/v1/challenge` and `/v1/posthog/delete-person` and their tests. Apple and App Attest next.

## API

Host: `account.sortd.page` (a custom domain on the existing zone; open question 1). JSON in, and 204 or `{"error":"<code>"}` out. Nothing else is ever returned: no tokens, no Apple or PostHog bodies.

| Route | Body (max 4 KB) | Worker does | Returns |
|---|---|---|---|
| `POST /v1/challenge` | `{"route":"apple/revoke"\|"posthog/delete-person","body_sha256":"<hex>"}` | Returns `challenge = base64url(ts ‖ route ‖ body_sha256 ‖ HMAC(CHALLENGE_KEY, …))`. Valid 120 s. No storage | 200 `{"challenge":"…"}` |
| `POST /v1/apple/revoke` | `{"client_id":"com.kameshraj.spend","authorization_code":"…"}` **or** `{"client_id":…,"refresh_token":"…"}`, exactly one | Checks `client_id` equals `APPLE_CLIENT_ID`. Mints a `client_secret` (ES256, `kid`=key id, `iss`=team id, `sub`=client id, `aud`=`https://appleid.apple.com`, `exp` = now + 300 s). With a code: `POST https://appleid.apple.com/auth/token` (`grant_type=authorization_code`) to get the refresh token. Then `POST https://appleid.apple.com/auth/revoke` with `token`, `token_type_hint=refresh_token` | 204 |
| `POST /v1/posthog/delete-person` | `{"distinct_id":"<64 lowercase hex>"}` | `POST {POSTHOG_API_HOST}/api/environments/{POSTHOG_PROJECT_ID}/persons/bulk_delete/` with `{"distinct_ids":[id],"delete_events":true}` and `Authorization: Bearer phx_…`. An unknown id counts as done | 204 |

Headers on both action routes: `X-Attest-Key-Id`, `X-Attest-Object` (base64), `X-Attest-Challenge`.

Error codes (status): `too_large` 413 · `not_found` 404 · `method_not_allowed` 405 · `origin_forbidden` 403 · `bad_request`, `wrong_client` 400 · `attest_missing`, `attest_invalid`, `challenge_expired` 401 · `rate_limited` 429 · `apple_<apple error>` (e.g. `apple_invalid_grant`) 502 · `posthog_auth` 502 · `apple_unavailable`, `posthog_unavailable`, `misconfigured` 503.
For the app: 502 means "do not retry this input" (an Apple code is single-use and lives 5 minutes). 503 and network errors mean "retry". An Apple retry needs a fresh code, so if Apple fails the app shows Apple's manual steps (TN3194) and does not queue. PostHog retries are queued by hash, like `GoogleAuth.retryPendingRevokes`.

Facts from Apple's pages: revoke returns 200 when the token "has been revoked successfully or was previously invalid", and 400 with an error JSON otherwise. The code is "single-use only and valid for five minutes". `redirect_uri` is required "if applicable"; native codes are exchanged without it (**not verified**). PostHog: the path, the `person:write` scope and the 1,000-id limit come from search summaries and the data-deletion page, **not from a page I could read in full**. PostHog's docs show both `/api/projects/…` and `/api/environments/…` forms. The builder confirms the path with a real `phx_` key before shipping. The API host (`eu.posthog.com`, not the ingest host `eu.i.posthog.com` in `Analytics.swift:279`) is **not verified**.

## Protection

- **App Attest on every action call. This is a change from the brief.** Apple's assertions need the server to keep each device's public key and counter. That is storage, so this Worker does not use them. Instead, each call makes a **fresh attested key**: `generateKey`, then `attestKey` with `clientDataHash = SHA256(challenge)`. Account deletion is rare, and Apple asks for fewer than 100 `attestKey` calls per second across all installs.
- **What the Worker checks:**
  - the `x5c` chain up to Apple's App Attest root CA;
  - the nonce extension (OID `1.2.840.113635.100.8.2`);
  - key id = SHA256 of the public key, and `credentialId` = key id;
  - counter = 0;
  - `rpIdHash` = SHA256(`APPLE_TEAM_ID + "." + APPLE_CLIENT_ID`). This is the only-our-bundle-id check.
  - `aaguid` must be `appattest` + seven zero bytes in prod. `appattestdevelop` is accepted only when `ENV=dev`.
  - The challenge's HMAC, its age (120 s or less), its route, and `body_sha256` = SHA256 of the raw body.
- **Replay** inside the 120 s window gains nothing. A used Apple code fails at Apple, and deleting the same person twice is a no-op.
- **Simulator and Macs.** App Attest is not available there: Apple says `isSupported` is `false` on Macs, and the simulator case is **not verified** from Apple's docs. The fallback is a separate dev deployment (`--env dev`, Worker `sortd-account-dev`) that accepts `X-Sortd-Debug: <DEV_BYPASS_TOKEN>`, and only when `ENV === "dev"`. The prod Worker has no such secret and ignores the header. The app sends the header only under `#if DEBUG`, and DEBUG builds point at the dev host.
- **Unsupported real device** (rare): the app cannot pass App Attest. It deletes locally and shows Apple's manual steps. Apple's advice is to "gracefully bypass the service".
- **Rate limits** use the Workers Rate Limiting binding, the same one `site/wrangler.jsonc:21` already uses. `IP_LIMIT` is 10 per 60 s per `cf-connecting-ip`, checked before any parsing. `ID_LIMIT` is 3 per 60 s per distinct id. Counters are "local to the Cloudflare location" and "eventually consistent", so they are a flood guard, not exact. Whether the free plan includes this binding is **not verified**; it works on Raj's account today. If a binding is missing, the Worker fails closed with 503, unlike the site Worker. The fallback, a Durable Object counter, is **not researched**.
- **Other rules:**
  - Bodies over 4 KB and attestation headers over 16 KB get 413. The real size of an attestation object is **not verified**.
  - Nothing logs bodies, headers, codes, tokens or ids. Workers observability is off in config. Only the route, status and error code are logged.
  - CORS is off: no `Access-Control-*` headers, OPTIONS gets 405, and any request with an `Origin` header gets 403.
- **What App Attest does not prove:** who the user is. Anyone with a genuine copy of the app who knows a hash could delete that PostHog person. Hashes appear in Sentry and support emails. The harm is lost analytics, and we accept it.

## Secrets and rotation

Wrangler secrets (`npx wrangler secret put <NAME>`, and with `--env dev` for dev; secrets are not inherited between environments): `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_CLIENT_ID`, `APPLE_PRIVATE_KEY` (.p8 PEM), `POSTHOG_API_KEY` (`phx_`, scoped to `person:write` on one project only), `POSTHOG_PROJECT_ID`, `CHALLENGE_KEY` (32 random bytes). Dev only: `DEV_BYPASS_TOKEN`. Vars: `ENV`, `POSTHOG_API_HOST`. Team and client id are public, but they are kept with the rest for one source of truth. Local values go in `worker/.env` (already gitignored by `.env`/`.env.*`; `.dev.vars` is **not** in `.gitignore`, so do not use it).

Rotation:
- **Apple:** create a new key, `secret put` `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY`, deploy, run one dev revoke, then revoke the old key in the developer portal. No JWT outlives 300 s, so nothing is cached.
- **PostHog:** create a new scoped key, put it, deploy, test, then delete the old key.
- **`CHALLENGE_KEY`:** put a new one any time. Challenges in flight fail for up to 120 s, and the app retries.

## Cost

Workers Free: 100,000 requests a day and 10 ms CPU per request; past a limit, "further operations of that type will fail with an error". Paid: $5 a month minimum, 10 M requests included. Two risks, both **not verified**:
- Whether the daily limit is shared with the site Worker, which runs on every sortd.page request.
- Whether App Attest verification fits in 10 ms. It runs X.509, CBOR and ECDSA in JavaScript and WebCrypto; this should be measured with `wrangler dev` and `wrangler tail`.

## Files

- `worker/wrangler.jsonc`: **jsonc, not toml**. Cloudflare recommends it for new projects, and `site/` already uses it. It holds `name`, `compatibility_date`, the custom domain, the `IP_LIMIT` and `ID_LIMIT` ratelimits (new `namespace_id`s, not `1001`), `observability` off, and `env.dev`.
- `worker/package.json`, `worker/tsconfig.json`, `worker/vitest.config.ts`.
- `worker/src/index.ts`: routing, size cap, Origin check, limits, error JSON.
- `worker/src/challenge.ts`, `worker/src/attest.ts`, `worker/src/apple.ts` (JWT and the two Apple calls), `worker/src/posthog.ts`.
- `worker/test/*.test.ts`: Vitest. Every upstream call goes through an injected `fetch`, so tests pass a fake, and the limiters are passed in too. Cloudflare's current runner is `@cloudflare/vitest-plugin` with Vitest 4.1 or later; `vitest-pool-workers` is marked deprecated. Attestation test fixtures: a test root CA plus a generated leaf, with the root injected.
- Libraries for CBOR and X.509 that run in `workerd`: **not verified**; the builder picks and proves them in a test.
- Deploy:
  - `cd worker && npx wrangler deploy`, and `npx wrangler deploy --env dev` for dev.
  - Only from a clean tree that matches the pushed branch, one session at a time (`CLAUDE.md` §5).
  - Separate from `site/`.
- App side, owned by sub-spec 4 and not this doc: `WorkerRevoker` in `Spend/Services/AccountStore.swift` (not on this branch yet; built to the spec's `revoke(account)` / `deletePerson(hash)`), the App Attest entitlement, and the host URLs in xcconfig.

## Risks

- **Hash is per install, not per account.** `Analytics.signedIn` salts with a random value kept in UserDefaults (`Analytics.swift:227-236`). So:
  - two phones make two PostHog persons, and this Worker deletes only this phone's;
  - Delete All Data wipes the defaults, and `preserveConsent` does not keep the salt. The app must work out the hash **before** any wipe, and queue it in the Keychain.
  - This also contradicts sub-spec 4's test "the hash for account A is the same on two installs". That is for the router to settle.
- **Reusing a deleted distinct id** can "lead to unexpected results" (PostHog). The app should make a new salt after an account delete.
- **PostHog may change its unknown-id reply.** Today `bulk_delete` returns 202 and drops unknown ids. A draft PR, not merged, would return 400 naming them when `delete_events` is set. `posthog.ts` treats a 400 that names our id as done, and a test covers it.
- **Data loss:** none. The Worker stores nothing and deletes only the one PostHog person it is given.
- **App Review:** the review notes must say that deletion revokes the Apple token through our endpoint.
- **Privacy label:** the Worker sees the IP, an Apple code and a hash in transit, and keeps none of them. No label change beyond sub-spec 2's User ID, which is **not verified** against Apple's "collect" definition for data that is only passed through. Cloudflare's own edge logs of IPs are outside our config.
- **Migration:** none; there is no SwiftData change.
- **How we would notice:** `wrangler tail` error codes, the PostHog person count, and a support email saying "Sortd still shows in my Apple ID".

## Test plan (Vitest, `worker/test/`)

- Valid attest + valid code → 204. `/auth/token` called once, `/auth/revoke` called once with the refresh token and `token_type_hint=refresh_token`.
- Valid attest + `refresh_token` → 204. `/auth/token` never called, revoke called once.
- Missing attest headers → 401 `attest_missing`, and no upstream fetch at all.
- Attestation for another bundle id (wrong `rpIdHash`) → 401 `attest_invalid`.
- `appattestdevelop` aaguid when `ENV=prod` → 401. When `ENV=dev` → accepted.
- Challenge 121 s old → 401 `challenge_expired`.
- Challenge made for the other route, or for a different body → 401.
- `X-Sortd-Debug` with the right token when `ENV=prod` → 401, and upstream is never called. When `ENV=dev` → proceeds.
- IP limiter says no → 429 `rate_limited`. Attestation is never parsed and upstream never called.
- Fourth delete for the same id within the window → 429.
- Limiter binding missing when `ENV=prod` → 503 `misconfigured`.
- `/auth/token` 400 `invalid_grant` → 502 `{"error":"apple_invalid_grant"}`, and revoke is never called.
- `/auth/revoke` 400 `invalid_client` → 502 `apple_invalid_client`.
- Apple 500 or a timeout → 503 `apple_unavailable`.
- `client_id` other than the configured one → 400 `wrong_client`, with no upstream call.
- Both a code and a refresh token, or neither → 400.
- A 5 KB body → 413.
- `distinct_id` that is not 64 lowercase hex → 400.
- PostHog 202 → 204. The call carries `distinct_ids:[id]`, `delete_events:true` and the bearer key.
- Same id twice (fake returns 202, then 202 with nothing matched, or a 400 naming the id) → 204 both times.
- PostHog 401 or 403 → 502 `posthog_auth`. PostHog 5xx → 503.
- `client_secret` has header `alg=ES256`, `kid`; claims `iss`, `sub`, `aud=https://appleid.apple.com`, `exp - iat ≤ 300`; and it verifies with the test public key.
- GET or OPTIONS → 405. Unknown path → 404. A request with an `Origin` header → 403. No response carries `Access-Control-Allow-Origin`.
- A console spy sees no code, token, id or attestation bytes during any test.
- No response body ever contains an Apple token.

`ui-driver`: nothing new from the Worker; the account screen's error copy belongs to sub-spec 4.

Real device only:
- App Attest from a DEBUG build against dev (`appattestdevelop`), then TestFlight against prod. Whether TestFlight uses the production aaguid is **not verified**.
- A real Apple delete, then check Settings › Apple Account › Sign in with Apple no longer lists Sortd.
- The PostHog person is gone in the UI.
- CPU time per call from `wrangler tail`.

## Gate

- Raj approves this doc.
- Raj, in the paid developer account: creates the Sign in with Apple key (downloads the .p8 once), enables App Attest on the App ID, and runs `wrangler secret put` for each secret. No agent sees the values.
- Raj creates the scoped PostHog personal key.
- The sub-spec 4 builder uses these error codes.

## Open questions (default if Raj says nothing)

1. **Host:** `account.sortd.page`.
2. **Who builds the Worker.** `test-writer` may only write `SpendTests/`. Default: the router widens the brief to `worker/test/`, and `swift-builder` builds `worker/`.
3. **CI:** add a `worker` job that runs `npm ci && npx vitest run`. Default: yes.
4. **Dev PostHog:** the dev Worker points at a separate "Sortd Dev" project.
5. **Free or paid plan:** start free; move to $5/mo if CPU or the shared daily limit bites.
6. **Sentry user data** (2b's `setUser`): not deleted by this Worker. Default: it ages out under Sentry's retention (length **not verified**), and the policy says so.
7. **Per-install hash** (Risks): settle in sub-spec 4 before its build.

## Sources (all read 25 Sep 2026)

- Apple: [Revoke tokens](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens), [Generate and validate tokens](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens), [Creating a client secret](https://developer.apple.com/documentation/accountorganizationaldatasharing/creating-a-client-secret), [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple). These were read through the `developer.apple.com/tutorials/data/…json` form, because the HTML pages did not render.
- Apple: [App Review Guidelines 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/), [Offering account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
- Apple App Attest: [Validating apps that connect to your server](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server), [Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity), [isSupported](https://developer.apple.com/documentation/devicecheck/dcappattestservice/issupported), [Preparing to use App Attest](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service).
- PostHog: [Data deletion](https://posthog.com/docs/privacy/data-deletion). [Persons API](https://posthog.com/docs/api/persons) and [Persons-2](https://posthog.com/docs/api/persons-2) loaded truncated, so the endpoint details are **not verified**. PRs [#104461](https://github.com/PostHog/posthog/pull/104461) (draft), [#95840](https://github.com/PostHog/posthog/pull/95840) (closed), [#101908](https://github.com/PostHog/posthog/pull/101908) (merged 17 Sep 2026).
- Cloudflare: [Rate limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [Limits](https://developers.cloudflare.com/workers/platform/limits/), [Pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [Configuration](https://developers.cloudflare.com/workers/wrangler/configuration/), [Vitest](https://developers.cloudflare.com/workers/testing/vitest-integration/) and [first test](https://developers.cloudflare.com/workers/testing/vitest-integration/write-your-first-test/). Durable Objects were not read.

**Paths read (this worktree):**
- `CLAUDE.md`, `HANDOVER.md`, `docs/AgentPipeline.md`.
- `docs/specs/2026-09-25-free-app-overhaul-overview.md`, `…-2-analytics.md`, `…-4-sign-in.md`.
- `Spend/Services/GoogleAuth.swift`, `Spend/Services/Analytics.swift`.
- `site/wrangler.jsonc`, `site/worker/index.js:45-69`, `.gitignore`, `.claude/agents/test-writer.md`.
- The pbxproj bundle id and team lines. `Spend/Services/AccountStore.swift` does not exist on this branch.
