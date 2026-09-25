// Stateless challenge: an HMAC-signed blob, so the Worker stores nothing.
//
//   challenge = base64url( version(1) | issuedAtMs(8, big-endian) | route(1) | random(16)
//                          | body_sha256(32) | HMAC-SHA256(CHALLENGE_KEY, all of the above)(32) )
//
// The app asks for one per call (POST /v1/challenge with the route and SHA256 of the exact
// body it will send), attests a fresh key with clientDataHash = SHA256(UTF-8 of this string),
// then sends the challenge back in X-Attest-Challenge. It is valid for 120 s (spec: Protection).
// Replay inside the window gains nothing: an Apple code is single-use and a PostHog delete
// is idempotent.

import { concat, equalBytes, fromHex, b64decode, b64urlEncode, sha256, utf8 } from "./bytes";
import { WorkerError } from "./errors";

export const ROUTES = ["apple/revoke", "posthog/delete-person"] as const;
export type Route = (typeof ROUTES)[number];
export const CHALLENGE_TTL_MS = 120_000;
/** Clock skew allowed between Cloudflare locations. */
const FUTURE_SKEW_MS = 5_000;
const VERSION = 1;
const SIGNED_LEN = 1 + 8 + 1 + 16 + 32;
const TOTAL_LEN = SIGNED_LEN + 32;

const routeByte = (r: Route) => ROUTES.indexOf(r) + 1;

async function hmacKey(key: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", utf8(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function issueChallenge(key: string, route: Route, bodySha256Hex: string, nowMs: number): Promise<string> {
  const bodyHash = fromHex(bodySha256Hex);
  if (!bodyHash || bodyHash.length !== 32) throw new WorkerError("bad_request");
  const ts = new Uint8Array(8);
  new DataView(ts.buffer).setBigUint64(0, BigInt(Math.floor(nowMs)));
  const signed = concat(Uint8Array.of(VERSION), ts, Uint8Array.of(routeByte(route)), crypto.getRandomValues(new Uint8Array(16)), bodyHash);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(key), signed));
  return b64urlEncode(concat(signed, mac));
}

/**
 * Checks the HMAC first (so a forged timestamp means nothing), then age, route and body.
 * Throws challenge_expired when only the age is wrong, attest_invalid for anything else.
 */
export async function verifyChallenge(key: string, challenge: string, route: Route, body: Uint8Array, nowMs: number): Promise<void> {
  const raw = challenge.length <= 200 ? b64decode(challenge) : null;
  if (!raw || raw.length !== TOTAL_LEN || raw[0] !== VERSION) throw new WorkerError("attest_invalid");
  const signed = raw.subarray(0, SIGNED_LEN);
  const mac = raw.subarray(SIGNED_LEN);
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(key), mac, signed);
  if (!ok) throw new WorkerError("attest_invalid");

  const issuedAt = Number(new DataView(raw.buffer, raw.byteOffset + 1, 8).getBigUint64(0));
  if (issuedAt > nowMs + FUTURE_SKEW_MS) throw new WorkerError("attest_invalid");
  if (nowMs - issuedAt > CHALLENGE_TTL_MS) throw new WorkerError("challenge_expired");
  if (raw[9] !== routeByte(route)) throw new WorkerError("attest_invalid");
  const bodyHash = raw.subarray(26, 58);
  if (!equalBytes(bodyHash, await sha256(body))) throw new WorkerError("attest_invalid");
}
