// HTTP API the iPhone app talks to (https://inbox.sortd.page/api/inbox/...).
//
//   POST   /api/inbox/register        { publicKey, suite } -> { address, token }
//   GET    /api/inbox/messages        -> { messages: [{ id, enc, ct }], more, cursor }
//          (?cursor=... for the next page, so an unreadable message can't hide the rest)
//   DELETE /api/inbox/messages/:id    -> 204 (after the phone has decrypted and saved it)
//   DELETE /api/inbox                 -> 204 (turn off: mailbox and everything waiting is deleted)
//
// Auth for everything but register: "Authorization: Bearer <mailbox>.<token>".
// The server keeps only SHA-256 hashes of both halves, so a copy of the
// database can't be used to read or even name a mailbox.

import { MESSAGE_ID_RE, mailboxKey, messagePrefix } from "./email.js";
import { SUITE_NAME, importPublicKey } from "./hpke.js";
import { ADDRESS_RE, b64u, json, newLocalPart, randomBytes, sameSecret, sha256hex, tag, unb64u } from "./util.js";

/** Mailboxes nobody has checked for this long are deleted by KV itself. */
export const MAILBOX_TTL_SECONDS = 180 * 24 * 60 * 60;
/** Refresh that expiry at most once a day, so fetching isn't a write every time. */
const TOUCH_AFTER_MS = 24 * 60 * 60 * 1000;
const PAGE = 20;

const noContent = () => new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
const error = (status, message) => json({ ok: false, error: message }, status);

function log(event, fields = {}) {
  console.log(JSON.stringify({ event, ...fields }));
}

async function readJSON(request, maxBytes) {
  const text = await request.text();
  if (text.length > maxBytes) return null;
  try { return JSON.parse(text); } catch { return null; }
}

export async function register(request, env, now) {
  if (env.REGISTER_LIMIT) {
    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    const { success } = await env.REGISTER_LIMIT.limit({ key: ip });
    if (!success) return error(429, "Too many new addresses from this network. Try again in a minute.");
  }
  const body = await readJSON(request, 2048);
  if (!body || body.suite !== SUITE_NAME || typeof body.publicKey !== "string") return error(400, "Send { publicKey, suite }.");
  let pk;
  try {
    pk = unb64u(body.publicKey);
    await importPublicKey(pk);
  } catch {
    return error(400, "That public key isn't a P-256 key.");
  }

  // 120 random bits make a collision absurdly unlikely; check anyway.
  let local, addrHash;
  for (let i = 0; i < 3 && !local; i++) {
    const candidate = newLocalPart();
    const h = await sha256hex(candidate);
    if (!(await env.INBOX.get(mailboxKey(h)))) { local = candidate; addrHash = h; }
  }
  if (!local) return error(503, "Try again.");

  const token = b64u(randomBytes(32));
  const record = { v: 1, pk: b64u(pk), th: await sha256hex(token), created: now, seen: now };
  await env.INBOX.put(mailboxKey(addrHash), JSON.stringify(record), { expirationTtl: MAILBOX_TTL_SECONDS });
  log("registered", { t: tag(addrHash) });
  return json({ ok: true, address: `${local}@${env.INBOX_DOMAIN}`, token, suite: SUITE_NAME }, 201);
}

/** The mailbox for a request's bearer credential, or null. */
export async function authenticate(request, env) {
  const header = request.headers.get("authorization") || "";
  const m = header.match(/^Bearer ([a-z0-9]+)\.([A-Za-z0-9_-]{43})$/);
  if (!m || !ADDRESS_RE.test(m[1])) return null;
  const addrHash = await sha256hex(m[1]);
  const record = await env.INBOX.get(mailboxKey(addrHash), "json");
  if (!record || !sameSecret(await sha256hex(m[2]), record.th)) return null;
  return { addrHash, record };
}

async function touch(env, box, now) {
  if (now - (box.record.seen || 0) < TOUCH_AFTER_MS) return;
  const record = { ...box.record, seen: now };
  await env.INBOX.put(mailboxKey(box.addrHash), JSON.stringify(record), { expirationTtl: MAILBOX_TTL_SECONDS });
}

export async function listMessages(env, box, now, cursor) {
  await touch(env, box, now);
  const options = { prefix: messagePrefix(box.addrHash), limit: PAGE };
  if (cursor) options.cursor = cursor;
  let listed;
  try { listed = await env.INBOX.list(options); } catch { return error(400, "Bad cursor."); }
  const messages = [];
  for (const k of listed.keys) {
    const value = await env.INBOX.get(k.name, "json");
    if (!value) continue; // expired or deleted since the list
    messages.push({ id: k.name.slice(messagePrefix(box.addrHash).length), enc: value.enc, ct: value.ct });
  }
  const more = !listed.list_complete;
  return json({ ok: true, messages, more, cursor: more ? listed.cursor : null });
}

export async function deleteMessage(env, box, id) {
  if (!MESSAGE_ID_RE.test(id)) return error(400, "Bad message id.");
  await env.INBOX.delete(messagePrefix(box.addrHash) + id);
  return noContent();
}

/**
 * Turn off: the mailbox and anything waiting are deleted. KV caches reads for up
 * to about 60 seconds per location, so mail can still be accepted for a minute;
 * anything that slips in is ciphertext for a key the phone has already deleted,
 * and expires in 24 hours.
 */
export async function deleteMailbox(env, box) {
  await env.INBOX.delete(mailboxKey(box.addrHash));
  let cursor;
  do {
    const page = await env.INBOX.list({ prefix: messagePrefix(box.addrHash), cursor, limit: 1000 });
    for (const k of page.keys) await env.INBOX.delete(k.name);
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  log("deleted", { t: tag(box.addrHash) });
  return noContent();
}

export async function handleApi(request, env, now) {
  const url = new URL(request.url);
  const path = url.pathname;
  if (path === "/api/inbox/register") {
    return request.method === "POST" ? register(request, env, now) : error(405, "Use POST.");
  }
  const box = await authenticate(request, env);
  if (!box) return error(401, "Unknown mailbox or token.");
  if (env.API_LIMIT) {
    const { success } = await env.API_LIMIT.limit({ key: box.addrHash });
    if (!success) return error(429, "Slow down.");
  }
  if (path === "/api/inbox/messages" && request.method === "GET") {
    const cursor = url.searchParams.get("cursor");
    // KV cursors are opaque; KV itself refuses a bad one (caught in listMessages).
    if (cursor !== null && cursor.length > 1024) return error(400, "Bad cursor.");
    return listMessages(env, box, now, cursor || undefined);
  }
  if (path === "/api/inbox" && request.method === "DELETE") return deleteMailbox(env, box);
  const m = path.match(/^\/api\/inbox\/messages\/([^/]+)$/);
  if (m && request.method === "DELETE") return deleteMessage(env, box, m[1]);
  return error(404, "Not found.");
}
