// Small helpers shared by the API and the email handler. No I/O here.

const enc = new TextEncoder();

/** Bytes -> base64url, no padding. */
export function b64u(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** base64url (or plain base64) -> bytes. Throws on bad input. */
export function unb64u(text) {
  const s = String(text).replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(s + "===".slice((s.length + 3) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function hex(bytes) {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256(data) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", typeof data === "string" ? enc.encode(data) : data));
}

export async function sha256hex(data) {
  return hex(await sha256(data));
}

export function randomBytes(n) {
  return crypto.getRandomValues(new Uint8Array(n));
}

// Lowercase letters and digits minus the look-alikes (0, 1, l, o). Exactly 32
// symbols, so each character is 5 random bits with no modulo bias.
export const ADDRESS_ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789";
export const ADDRESS_LENGTH = 24; // 24 x 5 = 120 random bits
export const ADDRESS_RE = new RegExp(`^[${ADDRESS_ALPHABET}]{${ADDRESS_LENGTH}}$`);

/** A new random mailbox name (the part before the @). */
export function newLocalPart() {
  const bytes = randomBytes(ADDRESS_LENGTH);
  let s = "";
  for (const b of bytes) s += ADDRESS_ALPHABET[b & 31];
  return s;
}

/** Constant-time compare of two equal-length strings (hex digests). */
export function sameSecret(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  const x = enc.encode(a), y = enc.encode(b);
  if (crypto.subtle.timingSafeEqual) return crypto.subtle.timingSafeEqual(x, y);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

/** The first 8 hex characters of a hash: enough to tell log lines apart, useless for finding a person. */
export function tag(hashHex) {
  return String(hashHex || "").slice(0, 8);
}

export function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra },
  });
}
