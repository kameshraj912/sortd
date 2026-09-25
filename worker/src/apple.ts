// Sign in with Apple token revocation.
//
// Apple docs (read 25 Sep 2026, see the spec's Sources):
//   client_secret JWT: https://developer.apple.com/documentation/accountorganizationaldatasharing/creating-a-client-secret
//   POST /auth/token:  https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens
//   POST /auth/revoke: https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens
//   Account deletion:  https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
//
// The app sends a FRESH authorization code (it re-authenticates at delete time), or a refresh
// token. With a code we exchange it for a refresh token, then revoke that. Nothing is stored
// and no token ever goes back in a response. redirect_uri is left out: native-app codes are
// exchanged without it (the spec marks this "not verified").

import { b64urlEncode, pemToDer, utf8 } from "./bytes";
import { WorkerError } from "./errors";

const APPLE = "https://appleid.apple.com";
const TOKEN_URL = `${APPLE}/auth/token`;
const REVOKE_URL = `${APPLE}/auth/revoke`;
const JWT_LIFETIME_S = 300;
const TIMEOUT_MS = 10_000;

export interface AppleConfig {
  teamId: string;
  keyId: string;
  clientId: string;
  /** The .p8 file's contents (PKCS#8 PEM, P-256). */
  privateKeyPem: string;
}

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

/** ES256 JWT: header {alg, kid}; claims {iss: team id, iat, exp <= iat + 300, aud, sub: client id}. */
export async function makeClientSecret(cfg: AppleConfig, nowMs: number): Promise<string> {
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey("pkcs8", pemToDer(cfg.privateKeyPem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  } catch {
    throw new WorkerError("misconfigured");
  }
  const iat = Math.floor(nowMs / 1000);
  const header = b64urlEncode(utf8(JSON.stringify({ alg: "ES256", kid: cfg.keyId })));
  const claims = b64urlEncode(
    utf8(JSON.stringify({ iss: cfg.teamId, iat, exp: iat + JWT_LIFETIME_S, aud: APPLE, sub: cfg.clientId })),
  );
  const input = `${header}.${claims}`;
  // WebCrypto returns ECDSA as raw r || s (64 bytes), which is exactly JWS ES256.
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(input)));
  return `${input}.${b64urlEncode(sig)}`;
}

/** Apple's error JSON is {"error":"invalid_grant"} etc. Only a short snake_case word is passed on. */
async function appleError(res: Response): Promise<WorkerError> {
  if (res.status >= 500 || res.status === 429) return new WorkerError("apple_unavailable");
  let code = "";
  try {
    const body = (await res.json()) as { error?: unknown };
    if (typeof body?.error === "string" && /^[a-z_]{1,40}$/.test(body.error)) code = body.error;
  } catch {
    // not JSON
  }
  return new WorkerError(code ? `apple_${code}` : "apple_rejected");
}

async function postForm(fetchFn: Fetch, url: string, form: Record<string, string>): Promise<Response> {
  try {
    return await fetchFn(url, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: new URLSearchParams(form).toString(),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch {
    throw new WorkerError("apple_unavailable"); // network error or timeout: retryable
  }
}

export async function revokeApple(
  grant: { authorization_code: string } | { refresh_token: string },
  cfg: AppleConfig,
  fetchFn: Fetch,
  nowMs: number,
): Promise<void> {
  const clientSecret = await makeClientSecret(cfg, nowMs);
  let token: string;
  let hint = "refresh_token";

  if ("authorization_code" in grant) {
    const res = await postForm(fetchFn, TOKEN_URL, {
      client_id: cfg.clientId,
      client_secret: clientSecret,
      code: grant.authorization_code,
      grant_type: "authorization_code",
    });
    if (!res.ok) throw await appleError(res);
    let body: { refresh_token?: unknown; access_token?: unknown };
    try {
      body = (await res.json()) as typeof body;
    } catch {
      throw new WorkerError("apple_bad_response");
    }
    if (typeof body.refresh_token === "string" && body.refresh_token) token = body.refresh_token;
    else if (typeof body.access_token === "string" && body.access_token) {
      // Apple revoke also takes an access token; use it if no refresh token came back.
      token = body.access_token;
      hint = "access_token";
    } else throw new WorkerError("apple_bad_response");
  } else {
    token = grant.refresh_token;
  }

  // Apple: 200 when the token "has been revoked successfully or was previously invalid".
  const res = await postForm(fetchFn, REVOKE_URL, {
    client_id: cfg.clientId,
    client_secret: clientSecret,
    token,
    token_type_hint: hint,
  });
  if (!res.ok) throw await appleError(res);
}
