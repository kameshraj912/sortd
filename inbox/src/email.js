// Inbound mail for <random>@in.sortd.page.
//
// For each message: find the mailbox, refuse unknown ones, cap size and rate,
// check DKIM, cut the email down to what the app's parsers read (sender,
// subject, date, one body), encrypt that to the phone's public key, and store
// only the ciphertext for 24 hours. Plaintext exists only in this function's
// memory. Nothing about the message is logged except a short hash tag and a
// size bucket.

import PostalMime from "postal-mime";
import { dmarcRejectDomains, fieldName, splitMessage, toBinary, verifyDkim } from "./dkim.js";
import { resolveTxt } from "./dns.js";
import { importPublicKey, seal } from "./hpke.js";
import { ADDRESS_RE, b64u, randomBytes, sha256hex, tag, unb64u } from "./util.js";

export const LIMITS = {
  /** Bigger than any receipt; Cloudflare's own ceiling is 25 MiB. */
  maxRawBytes: 10 * 1024 * 1024,
  /** Characters of body kept. Receipts are far smaller; this stops a huge email filling storage. */
  maxText: 256 * 1024,
  maxHtml: 768 * 1024,
  maxSubject: 998,
  /** Messages waiting for the phone. At 24 h each, this also caps a day's storage per mailbox. */
  maxPending: 100,
  ttlSeconds: 24 * 60 * 60,
};

export const GMAIL_CONFIRM_SENDER = "forwarding-noreply@google.com";
const CONFIRM_URL_RE = /https:\/\/mail-settings\.google\.com\/mail\/vf-[A-Za-z0-9_\-.%]+/;

/** Messages for one mailbox live under this prefix, sorted by arrival. */
export const messagePrefix = (addrHash) => `m:${addrHash}:`;
export const mailboxKey = (addrHash) => `a:${addrHash}`;

/** A sortable, unguessable message id: base36 time + 12 random bytes. */
export function newMessageId(now) {
  return `${now.toString(36).padStart(9, "0")}-${b64u(randomBytes(12))}`;
}
export const MESSAGE_ID_RE = /^[0-9a-z]{9}-[A-Za-z0-9_-]{16}$/;

function log(event, fields = {}) {
  // Only ever: an event name, a hash tag, a size bucket, a reason code.
  console.log(JSON.stringify({ event, ...fields }));
}

function sizeBucket(n) {
  if (n < 16 * 1024) return "<16K";
  if (n < 128 * 1024) return "<128K";
  if (n < 1024 * 1024) return "<1M";
  return ">=1M";
}

/** "Name <a@b.com>" from postal-mime's address object; "" for groups or nothing. */
function formatFrom(from) {
  if (!from || !from.address) return "";
  const name = (from.name || "").replace(/[\r\n<>"]/g, " ").trim();
  return name ? `${name} <${from.address}>` : from.address;
}

function domainOf(address) {
  const at = String(address || "").lastIndexOf("@");
  return at < 0 ? "" : address.slice(at + 1).toLowerCase().trim();
}

/** Gmail's "confirm forwarding" email, or null. The app double-checks the link's host. */
export function gmailConfirmation(email) {
  const sender = (email.from && email.from.address || "").toLowerCase();
  if (sender !== GMAIL_CONFIRM_SENDER) return null;
  const subject = email.subject || "";
  if (!/forwarding confirmation/i.test(subject)) return null;
  const code = (subject.match(/\(#(\d{6,12})\)/) || (email.text || "").match(/confirmation code:?\s*(\d{6,12})/i) || [])[1] || null;
  const url = ((email.text || "").match(CONFIRM_URL_RE) || (email.html || "").match(CONFIRM_URL_RE) || [])[0] || null;
  if (!code && !url) return null;
  return { code, url };
}

/**
 * What the phone gets, before encryption. Only what the parsers need:
 * no attachments, no other headers, no recipients.
 */
export function buildPayload(email, auth, receivedAt) {
  const text = (email.text || "").trim() ? email.text : "";
  const body = text
    ? { text: text.slice(0, LIMITS.maxText) }
    : { html: (email.html || "").slice(0, LIMITS.maxHtml) };
  const date = email.date && !Number.isNaN(Date.parse(email.date)) ? new Date(email.date).toISOString() : new Date(receivedAt).toISOString();
  const confirm = gmailConfirmation(email);
  return {
    v: 1,
    kind: confirm ? "gmail-forwarding-confirmation" : "mail",
    messageId: email.messageId ? String(email.messageId).slice(0, 998) : null,
    from: formatFrom(email.from),
    subject: (email.subject || "").slice(0, LIMITS.maxSubject),
    date,
    receivedAt: new Date(receivedAt).toISOString(),
    ...body,
    auth,
    ...(confirm ? { confirm } : {}),
  };
}

async function readAll(stream, max) {
  const reader = stream.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) { reader.cancel().catch(() => {}); return null; }
    chunks.push(value);
  }
  const out = new Uint8Array(size);
  let at = 0;
  for (const c of chunks) { out.set(c, at); at += c.byteLength; }
  return out;
}

/**
 * The email() entry point. `deps` lets tests swap the clock and DNS.
 * Returns a short outcome string (for tests); the real effect is KV writes or setReject.
 */
export async function handleEmail(message, env, deps = {}) {
  const now = deps.now ? deps.now() : Date.now();
  const resolve = deps.resolve || ((name) => resolveTxt(name));
  const reject = (reason, code, fields = {}) => {
    message.setReject(reason);
    log("rejected", { code, ...fields });
    return `rejected:${code}`;
  };

  const to = String(message.to || "").toLowerCase().trim();
  const at = to.lastIndexOf("@");
  const local = at < 0 ? "" : to.slice(0, at);
  const domain = at < 0 ? "" : to.slice(at + 1);
  if (domain !== String(env.INBOX_DOMAIN || "").toLowerCase() || !ADDRESS_RE.test(local)) {
    return reject("No such mailbox", "unknown");
  }
  const addrHash = await sha256hex(local);
  const box = await env.INBOX.get(mailboxKey(addrHash), "json");
  if (!box || !box.pk) return reject("No such mailbox", "unknown");
  const t = tag(addrHash);

  if (typeof message.rawSize === "number" && message.rawSize > LIMITS.maxRawBytes) {
    return reject("Message too large for Sortd (10 MB limit)", "too-large", { t });
  }
  if (env.MAIL_LIMIT) {
    const { success } = await env.MAIL_LIMIT.limit({ key: addrHash });
    if (!success) return reject("Too many messages to this Sortd address. Try again later.", "rate", { t });
  }
  const waiting = await env.INBOX.list({ prefix: messagePrefix(addrHash), limit: LIMITS.maxPending });
  if (waiting.keys.length >= LIMITS.maxPending) {
    return reject("This Sortd inbox is full. Open Sortd on your iPhone to empty it.", "full", { t });
  }

  const raw = await readAll(message.raw, LIMITS.maxRawBytes);
  if (!raw) return reject("Message too large for Sortd (10 MB limit)", "too-large", { t });

  let email;
  try {
    email = await PostalMime.parse(raw, { attachmentEncoding: "arraybuffer", maxNestingDepth: 50 });
  } catch {
    return reject("Sortd couldn't read this message", "unparseable", { t });
  }

  // Which domains provably sent this. Two or more From headers make the sender
  // ambiguous (the parsers could read one while the signature covers another),
  // so such a message proves nothing.
  const { fields } = splitMessage(toBinary(raw.subarray(0, Math.min(raw.length, 256 * 1024))));
  const fromCount = fields.filter((f) => fieldName(f) === "from").length;
  let dkim = [];
  let dmarc = [];
  if (fromCount === 1 && email.from && email.from.address) {
    try { dkim = (await verifyDkim(raw, { resolve, now })).domains; } catch { dkim = []; }
    if (env.TRUST_CLOUDFLARE_DMARC === "true") dmarc = await dmarcRejectDomains(domainOf(email.from.address), resolve);
  }

  const payload = buildPayload(email, { dkim, dmarc }, now);
  const plaintext = new TextEncoder().encode(JSON.stringify(payload));
  const id = newMessageId(now);
  let sealed;
  try {
    const pk = await importPublicKey(unb64u(box.pk));
    sealed = await seal(pk, plaintext, new TextEncoder().encode(id));
  } catch {
    return reject("Sortd couldn't store this message", "seal", { t });
  }
  await env.INBOX.put(
    messagePrefix(addrHash) + id,
    JSON.stringify({ v: 1, enc: b64u(sealed.enc), ct: b64u(sealed.ct) }),
    { expirationTtl: LIMITS.ttlSeconds },
  );
  log("stored", { t, size: sizeBucket(raw.length), kind: payload.kind === "mail" ? "mail" : "confirm", dkim: dkim.length > 0 });
  return "stored";
}
