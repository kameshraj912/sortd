// DKIM verification (RFC 6376, with RFC 8301 and RFC 8463), done in the Worker
// because Cloudflare Email Routing does not hand Workers any SPF/DKIM/DMARC
// verdicts (checked 22 Sep 2026: cloudflare/workerd issue #6740, no
// Authentication-Results header reaches the Worker).
//
// What it answers: "which domains provably signed this exact message?" The app
// then only lets a bank's parser read an email if that bank's domain is in the
// answer. A forged "DBS" alert sent straight to someone's address has no valid
// dbs.com signature, so it is read as an ordinary receipt at most, and can
// never mark anything as refunded.
//
// Deliberately strict:
//   - rsa-sha256 (key >= 1024 bits) and ed25519-sha256 only. rsa-sha1 is refused (RFC 8301).
//   - Signatures with l= (body length) are refused: they let anyone append text.
//   - h= must cover From.
//   - At most MAX_SIGNATURES signatures are tried, one DNS lookup each.

import { resolveTxt as defaultResolve } from "./dns.js";

const MAX_SIGNATURES = 5;
const MIN_RSA_BITS = 1024;

/** Bytes -> "binary string" (one char per byte, 0-255). Keeps bytes exact. */
export function toBinary(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return s;
}

function fromBinary(s) {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
  return out;
}

/** Splits a message into raw header fields (folding kept) and the body. Bare LFs become CRLF. */
export function splitMessage(bin) {
  const text = bin.replace(/\r?\n/g, "\r\n");
  let cut = text.indexOf("\r\n\r\n");
  let head, body;
  if (text.startsWith("\r\n")) { head = ""; body = text.slice(2); }
  else if (cut < 0) { head = text; body = ""; }
  else { head = text.slice(0, cut); body = text.slice(cut + 4); }
  const fields = [];
  for (const line of head.split("\r\n")) {
    if (!line) continue;
    if ((line[0] === " " || line[0] === "\t") && fields.length) fields[fields.length - 1] += "\r\n" + line;
    else fields.push(line);
  }
  return { fields, body };
}

export function fieldName(field) {
  const i = field.indexOf(":");
  return (i < 0 ? field : field.slice(0, i)).trim().toLowerCase();
}

function fieldValue(field) {
  const i = field.indexOf(":");
  return i < 0 ? "" : field.slice(i + 1);
}

/** "v=1; a=rsa-sha256; ..." -> Map. Null if malformed or a tag repeats. */
export function parseTags(value) {
  const tags = new Map();
  for (const part of value.split(";")) {
    const p = part.trim();
    if (!p) continue;
    const eq = p.indexOf("=");
    if (eq < 1) return null;
    const name = p.slice(0, eq).trim();
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(name) || tags.has(name)) return null;
    tags.set(name, p.slice(eq + 1).trim());
  }
  return tags;
}

export function canonHeaderRelaxed(field) {
  const name = fieldName(field);
  const value = fieldValue(field).replace(/\r\n/g, "").replace(/[ \t]+/g, " ").trim();
  return `${name}:${value}`;
}

export function canonBody(body, relaxed) {
  let lines = body.split("\r\n");
  if (relaxed) lines = lines.map((l) => l.replace(/[ \t]+/g, " ").replace(/ $/, ""));
  while (lines.length && lines[lines.length - 1] === "") lines.pop();
  if (!lines.length) return relaxed ? "" : "\r\n";
  return lines.join("\r\n") + "\r\n";
}

/** The header block the signature covers, in h= order (bottom-up for repeats), then the signature field itself with b= emptied. */
export function signedHeaderData(fields, sigField, names, relaxed) {
  const used = new Set();
  let out = "";
  for (const raw of names) {
    const name = raw.trim().toLowerCase();
    for (let i = fields.length - 1; i >= 0; i--) {
      if (used.has(i) || fieldName(fields[i]) !== name) continue;
      used.add(i);
      out += (relaxed ? canonHeaderRelaxed(fields[i]) : fields[i]) + "\r\n";
      break;
    }
    // A name with no (unused) instance adds nothing: that's how over-signing works.
  }
  const blanked = blankSignature(sigField);
  out += relaxed ? canonHeaderRelaxed(blanked) : blanked;
  return out;
}

/**
 * The DKIM-Signature field with the b= tag's value (and the whitespace around
 * it) removed, everything else byte for byte. Works tag by tag, so "b=" inside
 * another tag's value (z= can hold copied headers) is left alone.
 */
export function blankSignature(sigField) {
  const colon = sigField.indexOf(":");
  const parts = sigField.slice(colon + 1).split(";");
  for (let i = 0; i < parts.length; i++) {
    const m = parts[i].match(/^([ \t\r\n]*b[ \t\r\n]*=)/);
    if (m) { parts[i] = m[1]; break; }
  }
  return sigField.slice(0, colon + 1) + parts.join(";");
}

function b64(text) {
  const s = text.replace(/[\s]/g, "");
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(s)) throw new Error("bad base64");
  const bin = atob(s);
  return fromBinary(bin);
}

const DOMAIN_RE = /^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;
const SELECTOR_RE = /^[a-z0-9](?:[a-z0-9._-]{0,62})$/i;

async function publicKey(selector, domain, algorithm, resolve) {
  const records = await resolve(`${selector}._domainkey.${domain}`);
  let mismatch = false;
  for (const r of records) {
    const tags = parseTags(r);
    if (!tags || !tags.has("p")) continue;
    if (tags.has("v") && tags.get("v") !== "DKIM1") continue;
    const k = (tags.get("k") || "rsa").toLowerCase();
    const p = tags.get("p").replace(/\s/g, "");
    if (!p) return { error: "key revoked" };
    if (tags.has("h") && !tags.get("h").split(":").map((x) => x.trim()).includes("sha256")) return { error: "key forbids sha256" };
    const flags = (tags.get("t") || "").split(":").map((x) => x.trim());
    if (algorithm === "rsa-sha256" && k === "rsa") {
      const key = await crypto.subtle.importKey("spki", b64(p), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
      if ((key.algorithm.modulusLength || 0) < MIN_RSA_BITS) return { error: "rsa key too short" };
      return { key, strict: flags.includes("s") };
    }
    if (algorithm === "ed25519-sha256" && k === "ed25519") {
      const raw = b64(p);
      if (raw.length !== 32) return { error: "bad ed25519 key" };
      const key = await crypto.subtle.importKey("raw", raw, { name: "Ed25519" }, false, ["verify"]);
      return { key, strict: flags.includes("s") };
    }
    mismatch = true; // e.g. an ed25519 and an rsa record under one selector: try the next one
  }
  return { error: mismatch ? "key type mismatch" : "no key" };
}

/** Checks one DKIM-Signature field. Returns { domain, selector, result } where result is "pass" or a reason. */
export async function verifyOne(sigField, fields, body, { resolve, now }) {
  const tags = parseTags(fieldValue(sigField).replace(/\r\n/g, ""));
  const out = (result, domain = "", selector = "") => ({ domain, selector, result });
  if (!tags) return out("malformed");
  for (const t of ["v", "a", "b", "bh", "d", "h", "s"]) if (!tags.has(t)) return out(`missing ${t}`);
  const domain = tags.get("d").toLowerCase().replace(/\.$/, "");
  const selector = tags.get("s").toLowerCase();
  if (tags.get("v") !== "1") return out("bad version", domain, selector);
  if (!DOMAIN_RE.test(domain) || !SELECTOR_RE.test(selector)) return out("bad d or s", domain, selector);
  const algorithm = tags.get("a").toLowerCase();
  if (algorithm !== "rsa-sha256" && algorithm !== "ed25519-sha256") return out(`algorithm ${algorithm} refused`, domain, selector);
  if (tags.has("l")) return out("l= refused", domain, selector);
  if (tags.has("q") && !tags.get("q").split(":").some((q) => q.trim() === "dns/txt")) return out("bad q", domain, selector);
  const names = tags.get("h").split(":").map((x) => x.trim().toLowerCase()).filter(Boolean);
  if (!names.includes("from")) return out("from not signed", domain, selector);
  // The parsers read amounts and "refund" from the subject, so an unsigned subject proves nothing useful.
  if (!names.includes("subject")) return out("subject not signed", domain, selector);
  let identity = null;
  if (tags.has("i")) {
    const i = tags.get("i").toLowerCase();
    identity = i.slice(i.lastIndexOf("@") + 1);
    if (identity !== domain && !identity.endsWith("." + domain)) return out("i not in d", domain, selector);
  }
  if (tags.has("x")) {
    const x = Number(tags.get("x"));
    if (!Number.isFinite(x) || x * 1000 < now) return out("expired", domain, selector);
  }
  const [hc = "simple", bc = "simple"] = (tags.get("c") || "simple/simple").toLowerCase().split("/");
  if (![hc, bc].every((c) => c === "simple" || c === "relaxed")) return out("bad c", domain, selector);

  let bodyHash, signature;
  try { bodyHash = b64(tags.get("bh")); signature = b64(tags.get("b")); } catch { return out("bad base64", domain, selector); }
  const actual = new Uint8Array(await crypto.subtle.digest("SHA-256", fromBinary(canonBody(body, bc === "relaxed"))));
  if (actual.length !== bodyHash.length || actual.some((b, i) => b !== bodyHash[i])) return out("body hash mismatch", domain, selector);

  let found;
  try { found = await publicKey(selector, domain, algorithm, resolve); } catch { return out("key lookup failed", domain, selector); }
  if (found.error) return out(found.error, domain, selector);
  if (found.strict && identity && identity !== domain) return out("i not equal d (t=s)", domain, selector);

  const data = fromBinary(signedHeaderData(fields, sigField, names, hc === "relaxed"));
  let ok = false;
  try {
    if (algorithm === "rsa-sha256") {
      ok = await crypto.subtle.verify({ name: "RSASSA-PKCS1-v1_5" }, found.key, signature, data);
    } else {
      // RFC 8463: Ed25519 signs the SHA-256 hash of the header data, not the data itself.
      const digest = await crypto.subtle.digest("SHA-256", data);
      ok = await crypto.subtle.verify({ name: "Ed25519" }, found.key, signature, digest);
    }
  } catch { ok = false; }
  return out(ok ? "pass" : "bad signature", domain, selector);
}

/**
 * Headers that must appear at most once. DKIM checks the bottom-most copy of a
 * signed header, but a mail parser reads the top one; a second copy added above
 * a real signed email would be read, unsigned, as the subject (or sender, or
 * body type). So any repeat makes the whole message prove nothing.
 */
export const SINGLE_HEADERS = ["from", "sender", "subject", "date", "message-id", "mime-version", "content-type", "content-transfer-encoding"];

function repeatedIn(fields) {
  const counts = new Map();
  for (const f of fields) counts.set(fieldName(f), (counts.get(fieldName(f)) || 0) + 1);
  return SINGLE_HEADERS.find((h) => (counts.get(h) || 0) > 1) || null;
}

/** The first SINGLE_HEADERS name that appears more than once in a raw message, or null. */
export function repeatedHeader(rawBytes) {
  return repeatedIn(splitMessage(toBinary(rawBytes)).fields);
}

/**
 * Verifies every DKIM signature on a raw message (bytes).
 * Returns { domains: [...domains with a passing signature], results: [...] }.
 * `domains` is empty when a SINGLE_HEADERS header is repeated.
 */
export async function verifyDkim(rawBytes, { resolve = defaultResolve, now = Date.now() } = {}) {
  const { fields, body } = splitMessage(toBinary(rawBytes));
  const repeated = repeatedIn(fields);
  if (repeated) return { domains: [], results: [{ domain: "", selector: "", result: `repeated ${repeated}` }] };
  const sigs = fields.filter((f) => fieldName(f) === "dkim-signature").slice(0, MAX_SIGNATURES);
  const results = [];
  for (const sig of sigs) results.push(await verifyOne(sig, fields, body, { resolve, now }));
  const domains = [...new Set(results.filter((r) => r.result === "pass").map((r) => r.domain))];
  return { domains, results };
}

// ---------------------------------------------------------------------------
// DMARC policy lookup. Only used when TRUST_CLOUDFLARE_DMARC is "true" (off by
// default). Cloudflare Email Routing says it rejects mail that fails the
// sender's DMARC policy before any Worker runs, so if the From domain publishes
// p=reject, a message that reached us was authenticated for that domain by
// Cloudflare. Turn it on only after checking that on the live setup (see
// docs/ForwardingInbox.md, "Owner checks after deploy").

/**
 * The DMARC policy published at _dmarc.<domain> itself: { policy, pct } or null.
 * Deliberately does not walk up to a parent (organizational) domain: without the
 * public suffix list we can't be sure we'd pick the same record Cloudflare did,
 * and a wrong guess here would mean trusting a forgery.
 */
export async function dmarcPolicy(domain, resolve = defaultResolve) {
  const records = (await resolve(`_dmarc.${domain.toLowerCase()}`)).filter((r) => /^v=DMARC1\s*(;|$)/i.test(r.trim()));
  if (records.length !== 1) return null; // none, or ambiguous (RFC 7489 says ignore)
  const tags = parseTags(records[0]);
  if (!tags) return null;
  const pct = tags.has("pct") ? Number(tags.get("pct")) : 100;
  return { policy: (tags.get("p") || "").toLowerCase(), pct };
}

/** [domain] if the From domain's DMARC policy is a full p=reject, else []. */
export async function dmarcRejectDomains(fromDomain, resolve = defaultResolve) {
  if (!fromDomain || !DOMAIN_RE.test(fromDomain)) return [];
  try {
    const p = await dmarcPolicy(fromDomain, resolve);
    return p && p.policy === "reject" && p.pct === 100 ? [fromDomain] : [];
  } catch {
    return [];
  }
}

