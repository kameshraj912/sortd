# sortd-account Worker

Deleting an account in Sortd has two steps the phone can't do by itself:

- **Revoke the Sign in with Apple token.** This needs our Apple private key (.p8).
- **Delete the PostHog person.** This needs a PostHog personal API key.

Neither key can ship in the app. This Worker holds them as Wrangler secrets and does those two calls. It stores nothing.

Spec: `docs/specs/2026-09-25-account-worker.md` (approved 25 Sep 2026).

## The JSON contract (for the Swift side)

Host: `https://account.sortd.page` (prod). The dev Worker runs on workers.dev as `sortd-account-dev`.

Every reply is either:

- a success: `200` with JSON (challenge only), or `204` with no body, or
- `{"error":"<code>"}` with the status in the table below.

Nothing else is ever returned: no tokens, and no Apple or PostHog bodies.

Every request must:

- be `POST`;
- have a body of 4 KB or less;
- have **no** `Origin` header.

### 1. `POST /v1/challenge`

Request body. `body_sha256` is the lowercase hex SHA-256 of the **exact bytes** you will send as the action body:

```json
{"route": "posthog/delete-person", "body_sha256": "<64 lowercase hex>"}
```

`route` is `"apple/revoke"` or `"posthog/delete-person"`. Any other key gives 400.

Reply `200`:

```json
{"challenge": "<base64url string, about 120 chars>"}
```

The challenge is good for **120 seconds**, for that route and that body only. The Worker keeps no copy: it checks its own HMAC when the challenge comes back.

### 2. App Attest, once per call

1. `let keyId = try await DCAppAttestService.shared.generateKey()`
2. `let clientDataHash = SHA256(Data(challenge.utf8))`. Hash the challenge **string's UTF-8 bytes**, not the base64url-decoded bytes.
3. `let attestation = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)`

Then send these headers on the action call:

| Header | Value |
|---|---|
| `X-Attest-Key-Id` | `keyId`, exactly as `generateKey()` returned it (standard base64) |
| `X-Attest-Object` | `attestation.base64EncodedString()` |
| `X-Attest-Challenge` | the challenge string from step 1 |

All three together must be 16 KB or less. The key is used once, then thrown away. The Worker never asks for assertions, because assertions need the server to store each key.

### 3. `POST /v1/apple/revoke`

Send exactly one of the two:

```json
{"client_id": "com.kameshraj.spend", "authorization_code": "<fresh code from ASAuthorizationAppleIDCredential>"}
```

```json
{"client_id": "com.kameshraj.spend", "refresh_token": "<refresh token>"}
```

- `client_id` must equal the `APPLE_CLIENT_ID` secret, or you get 400 `wrong_client`.
- Having both fields, or neither, or any other key, gives 400 `bad_request`.
- With a code, the Worker calls `/auth/token` to get a refresh token, then `/auth/revoke`. With a refresh token it only calls `/auth/revoke`.
- Success is `204`.

An Apple code works **once** and lasts **5 minutes**. Get a new one (re-authenticate) right before the delete.

### 4. `POST /v1/posthog/delete-person`

```json
{"distinct_id": "<64 lowercase hex>"}
```

- The Worker calls PostHog's `bulk_delete` with `delete_events: true`.
- An id PostHog doesn't know counts as done, so a repeat call is safe.
- Success is `204`.

### Error codes

| Status | Codes | What the app should do |
|---|---|---|
| 400 | `bad_request`, `wrong_client` | Bug in the app. Don't retry. |
| 401 | `attest_missing`, `attest_invalid`, `challenge_expired` | Get a new challenge and a new attested key, then try once more. |
| 403 | `origin_forbidden` | Don't send `Origin`. |
| 404 / 405 | `not_found`, `method_not_allowed` | Bug in the app. |
| 413 | `too_large` | Bug in the app. |
| 429 | `rate_limited` (with `Retry-After: 60`) | Wait, then retry. |
| 502 | `apple_<apple error>` (e.g. `apple_invalid_grant`, `apple_invalid_client`), `apple_rejected`, `apple_bad_response`, `posthog_auth`, `posthog_rejected` | Don't retry this input. For Apple, show the manual steps (TN3194). |
| 503 | `apple_unavailable`, `posthog_unavailable`, `misconfigured` | Retry later. PostHog retries can be queued by hash. An Apple retry needs a fresh code. |
| 500 | `internal` | A bug in the Worker. Retry later. |

Network errors mean the same as 503.

### Rate limits

- **Per IP:** 10 requests per 60 s. This is checked before anything is read.
- **Per `distinct_id`:** 3 deletes per 60 s. This is checked after App Attest passes.

These are Cloudflare's rate-limiting binding: approximate, per location. If a binding is missing, every call gets 503 `misconfigured`.

## Dev bypass (`ENV=dev` only)

App Attest doesn't work on the simulator or on Macs. So DEBUG builds talk to the **dev** Worker, and send:

```
X-Sortd-Debug: <DEV_BYPASS_TOKEN>
```

in place of the three `X-Attest-*` headers. This skips App Attest and the challenge.

It works only when both are true:

- `ENV` is `"dev"` (set in `wrangler.jsonc` under `env.dev`);
- `DEV_BYPASS_TOKEN` is set on the dev Worker and is 16+ characters.

The dev Worker also accepts the `appattestdevelop` App Attest environment. The prod Worker ignores the header and only accepts `appattest`.

## Secrets

Secrets never go in `wrangler.jsonc` or git. Set each one yourself. Wrangler asks for the value.

```sh
cd worker
npx wrangler secret put APPLE_TEAM_ID          # 10-char Team ID
npx wrangler secret put APPLE_CLIENT_ID        # com.kameshraj.spend
npx wrangler secret put APPLE_KEY_ID           # 10-char Key ID of the Sign in with Apple key
npx wrangler secret put APPLE_PRIVATE_KEY < ~/path/to/AuthKey_XXXXXXXXXX.p8
npx wrangler secret put POSTHOG_API_KEY        # phx_... personal key
npx wrangler secret put POSTHOG_PROJECT_ID     # the number in the PostHog project URL
openssl rand -base64 32 | npx wrangler secret put CHALLENGE_KEY
```

For dev, run the same commands with `--env dev`. Secrets are not shared between environments. Also set:

```sh
openssl rand -base64 24 | npx wrangler secret put DEV_BYPASS_TOKEN --env dev
```

Put the same token in the app's DEBUG xcconfig. Never put it in the prod Worker.

Vars in `wrangler.jsonc` (these are not secret): `ENV` (`prod`/`dev`) and `POSTHOG_API_HOST` (`https://us.posthog.com`: the Sortd project is on the US cloud; **not verified** with a real key).

For local `wrangler dev`, pass test values with `--var NAME:value`. Or put them in `worker/.env`, which is gitignored. Don't use `.dev.vars`: it is **not** in `.gitignore`.

**Rotation:** put the new value, deploy, test one dev call, then delete the old key at Apple or PostHog. If you change `CHALLENGE_KEY`, challenges already issued fail for up to 120 s.

## Test, run, deploy

```sh
cd worker
npm ci
npm test                 # Vitest, all upstream calls faked
npm run typecheck        # tsc --noEmit
npx wrangler deploy --dry-run   # bundles, needs no secrets or login
npx wrangler dev --env dev --var CHALLENGE_KEY:local-test-key-0123456789abcdef
```

Deploy **prod**:

```sh
cd worker && npx wrangler deploy
```

This targets the top-level (prod) config. Wrangler warns that several environments exist. `--env=""` says "prod" explicitly.

Deploy **dev**:

```sh
cd worker && npx wrangler deploy --env dev
```

Rules for deploying:

- One session deploys at a time.
- Deploy only from a clean tree that matches the pushed branch. `wrangler deploy` uploads what is on disk.
- This Worker deploys separately from `site/`.

CI: `.github/workflows/worker.yml` runs install, type-check and tests on Linux for any change under `worker/`.

## What Raj must create

**Apple Developer account** (needs the paid membership):

1. **Keys** → new key → tick **Sign in with Apple** → configure it for the primary App ID `com.kameshraj.spend`. Download the `.p8`. You can only download it once. Note the **Key ID**.
2. Your **Team ID**, from Membership details.
3. On the App ID `com.kameshraj.spend`, turn on **App Attest**. Then add the App Attest entitlement to the app. That belongs to sub-spec 4, not to this folder.
4. Run the `wrangler secret put` commands above.

**PostHog:**

1. Personal API keys → new key, scoped to **person write** (`person:write`) on the Sortd project only.
2. The **project ID** (the number in the project URL).
3. Make one real delete with a test distinct id. This confirms the `api/environments/<id>/persons/bulk_delete/` path and the reply to an unknown id. The spec marks both **not verified**.

**Cloudflare:**

- The custom domain `account.sortd.page` is attached by `wrangler deploy` (`routes` in `wrangler.jsonc`), on the existing `sortd.page` zone.

## Not verified

- **Real App Attest objects.** The tests use a fake CA. The Apple root in `src/attest.ts` is pinned by SHA-256. It parses, and its self-signature verifies in a test. But no real device attestation has been checked yet: that needs a device or TestFlight. Whether Apple's leaf is signed with SHA-256 or SHA-384 is also not verified. Both are tested.
- **PostHog's unknown-id 400.** Only `{"type":"validation_error","attr":"distinct_ids", …}` with our id in a list counts as "already gone". The real field names are not verified.
- **Workers runtime.** Tests run on Node. `wrangler dev` (workerd) was smoke-tested for routing, 405, 403, 413, 429, the challenge route and the dev bypass. The App Attest crypto was not exercised in workerd.
- **CPU time** per attestation on the free plan's 10 ms limit.
- **Apple without `redirect_uri`** for native codes.
- **The PostHog path, scope and host.**
