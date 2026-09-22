// Test helpers: fake inbound messages, fake DNS, fake rate limiters, and a
// small DKIM signer for making "real bank" test mail. The signer reuses the
// verifier's canonicalisation, so on its own it would prove nothing; the RFC
// 8463 vector in dkim.test.js is what shows that canonicalisation is right.
import { env } from "cloudflare:workers";
import worker from "../src/index.js";
import { canonBody, splitMessage, signedHeaderData, toBinary } from "../src/dkim.js";
import { suite } from "../src/hpke.js";
import { b64u } from "../src/util.js";

export const CRLF = (s) => s.replace(/\r?\n/g, "\r\n");

export function fakeMessage(to, raw) {
  const bytes = typeof raw === "string" ? new TextEncoder().encode(raw) : raw;
  return {
    to,
    from: "user+caf_=forwarded@gmail.com", // the envelope sender Gmail uses when forwarding
    rawSize: bytes.length,
    raw: new Response(bytes).body,
    headers: new Headers(),
    rejected: null,
    setReject(reason) { this.rejected = reason; },
  };
}

/** Fake DNS: { "name": ["txt record", ...] }. Unknown names have no records. */
export function fakeDns(records) {
  const asked = [];
  const resolve = async (name) => { asked.push(name); return records[name] || []; };
  resolve.asked = asked;
  return resolve;
}

export function limiter(allow) {
  let calls = 0;
  return { calls: () => calls, limit: async () => { calls++; return { success: calls <= allow }; } };
}

/** A fresh P-256 key pair standing in for the phone. */
export async function phoneKeys() {
  const pair = await suite.kem.generateKeyPair();
  const pub = new Uint8Array(await suite.kem.serializePublicKey(pair.publicKey));
  return { pair, publicKeyB64u: b64u(pub) };
}

/** Signs `raw` (CRLF text) with rsa-sha256, relaxed/relaxed by default. Returns the message with the DKIM-Signature on top. */
export async function dkimSign(raw, { domain, selector = "s1", privateKey, headers = ["from", "to", "subject", "date", "message-id"], c = "relaxed/relaxed", extraTags = "" }) {
  const { fields, body } = splitMessage(toBinary(new TextEncoder().encode(raw)));
  const [hc, bc] = c.split("/");
  const bh = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonBody(body, bc === "relaxed"))))));
  const sig = `DKIM-Signature: v=1; a=rsa-sha256; c=${c}; d=${domain}; s=${selector};${extraTags} h=${headers.join(":")}; bh=${bh}; b=`;
  const data = signedHeaderData(fields, sig, headers, hc === "relaxed");
  const bytes = Uint8Array.from(data, (ch) => ch.charCodeAt(0));
  const s = new Uint8Array(await crypto.subtle.sign({ name: "RSASSA-PKCS1-v1_5" }, privateKey, bytes));
  return `${sig}${btoa(String.fromCharCode(...s))}\r\n${raw}`;
}

export async function rsaKey() {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  );
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  return { privateKey: pair.privateKey, record: `v=DKIM1; k=rsa; p=${btoa(String.fromCharCode(...spki))}` };
}

export const NAB_ALERT = CRLF(`From: NAB <alerts@nab.com.au>
To: raj@gmail.com
Subject: Transaction alert
Date: Sun, 20 Sep 2026 11:30:00 +1000
Message-ID: <alert-58-30@nab.com.au>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

A purchase of $58.30 was made at WOOLWORTHS 3342 on your card ending 1234.
`);

/** Registers a mailbox through the real API, the way the app does. (The real per-IP limit is left out: tests make many.) */
export async function newMailbox(e = { ...env, REGISTER_LIMIT: undefined }) {
  const keys = await phoneKeys();
  const res = await worker.fetch(new Request("https://inbox.sortd.page/api/inbox/register", {
    method: "POST",
    body: JSON.stringify({ publicKey: keys.publicKeyB64u, suite: "P256_SHA256_AES_GCM_256" }),
  }), e);
  const body = await res.json();
  const local = body.address.split("@")[0];
  return { ...body, keys, local, auth: { authorization: `Bearer ${local}.${body.token}` } };
}
