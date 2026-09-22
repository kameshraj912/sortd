import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index.js";
import { LIMITS, gmailConfirmation, handleEmail } from "../src/email.js";
import { filterXml, gmailQuery } from "../src/filters.js";
import { open } from "../src/hpke.js";
import { sha256hex, unb64u } from "../src/util.js";
import { CRLF, NAB_ALERT, dkimSign, fakeDns, fakeMessage, limiter, newMailbox, rsaKey } from "./helpers.js";

const BASE = "https://inbox.sortd.page";
const noDns = fakeDns({});
const deliver = (to, raw, e = env, deps = { resolve: noDns }) => {
  const msg = fakeMessage(to, raw);
  return handleEmail(msg, e, deps).then((outcome) => ({ outcome, msg }));
};

/** What the phone does: list, open each with its private key, return the payloads. */
async function phoneFetch(box) {
  const res = await worker.fetch(new Request(`${BASE}/api/inbox/messages`, { headers: box.auth }), env);
  const { messages } = await res.json();
  const out = [];
  for (const m of messages) {
    const pt = await open(box.keys.pair.privateKey, unb64u(m.enc), unb64u(m.ct), new TextEncoder().encode(m.id));
    out.push({ id: m.id, payload: JSON.parse(new TextDecoder().decode(pt)) });
  }
  return out;
}

describe("incoming mail", () => {
  it("refuses unknown, malformed and other-domain addresses", async () => {
    for (const to of ["abcdefghijkmnpqrstuvwxyz2@in.sortd.page", "abcdefghijkmnpqrstuvwxy2@in.sortd.page", "short@in.sortd.page", "support@sortd.page"]) {
      const { outcome, msg } = await deliver(to, NAB_ALERT);
      expect(outcome).toBe("rejected:unknown");
      expect(msg.rejected).toBe("No such mailbox");
    }
    const box = await newMailbox();
    const { outcome } = await deliver(`${box.local}@elsewhere.example`, NAB_ALERT);
    expect(outcome).toBe("rejected:unknown");
  });

  it("stores only ciphertext, which the phone's key opens to the parsed email", async () => {
    const box = await newMailbox();
    const { outcome, msg } = await deliver(box.address.toUpperCase(), NAB_ALERT); // addresses are case-insensitive
    expect(outcome).toBe("stored");
    expect(msg.rejected).toBeNull();

    const h = await sha256hex(box.local);
    const { keys } = await env.INBOX.list({ prefix: `m:${h}:` });
    expect(keys).toHaveLength(1);
    const stored = await env.INBOX.get(keys[0].name);
    for (const secret of ["WOOLWORTHS", "58.30", "nab.com.au", "Transaction alert", "raj@gmail.com", box.local]) {
      expect(stored).not.toContain(secret);
      expect(keys[0].name).not.toContain(secret);
    }

    const [{ payload }] = await phoneFetch(box);
    expect(payload).toMatchObject({
      v: 1,
      kind: "mail",
      from: "NAB <alerts@nab.com.au>",
      subject: "Transaction alert",
      messageId: "<alert-58-30@nab.com.au>",
      date: "2026-09-20T01:30:00.000Z",
      auth: { dkim: [], dmarc: [] }, // unsigned: proves nothing
    });
    expect(payload.text).toContain("A purchase of $58.30 was made at WOOLWORTHS 3342");
    expect(payload).not.toHaveProperty("to");
  });

  it("keeps messages for 24 hours at most", async () => {
    const box = await newMailbox();
    await deliver(box.address, NAB_ALERT);
    const { keys } = await env.INBOX.list({ prefix: `m:${await sha256hex(box.local)}:` });
    expect(Math.abs(keys[0].expiration - (Date.now() / 1000 + 24 * 3600))).toBeLessThan(120);
  });

  it("the phone deletes each message after reading it", async () => {
    const box = await newMailbox();
    await deliver(box.address, NAB_ALERT);
    await deliver(box.address, NAB_ALERT.replace("58.30", "12.00"));
    const got = await phoneFetch(box);
    expect(got).toHaveLength(2);
    for (const m of got) {
      const res = await worker.fetch(new Request(`${BASE}/api/inbox/messages/${m.id}`, { method: "DELETE", headers: box.auth }), env);
      expect(res.status).toBe(204);
    }
    expect(await phoneFetch(box)).toEqual([]);
    expect((await env.INBOX.list({ prefix: `m:${await sha256hex(box.local)}:` })).keys).toEqual([]);
  });

  it("one mailbox can't read or delete another's mail", async () => {
    const a = await newMailbox();
    const b = await newMailbox();
    await deliver(a.address, NAB_ALERT);
    expect(await phoneFetch(b)).toEqual([]);
    const [m] = await phoneFetch(a);
    await worker.fetch(new Request(`${BASE}/api/inbox/messages/${m.id}`, { method: "DELETE", headers: b.auth }), env);
    expect(await phoneFetch(a)).toHaveLength(1);
  });

  it("records which domains DKIM proves, so the app can trust a real bank alert", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(NAB_ALERT, { domain: "nab.com.au", privateKey });
    const box = await newMailbox();
    const dns = fakeDns({ "s1._domainkey.nab.com.au": [record] });
    expect((await deliver(box.address, signed, env, { resolve: dns })).outcome).toBe("stored");
    const [{ payload }] = await phoneFetch(box);
    expect(payload.auth.dkim).toEqual(["nab.com.au"]);
  });

  it("two From headers prove nothing, even with a valid signature", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(NAB_ALERT, { domain: "nab.com.au", privateKey });
    const tricked = signed.replace("From: NAB", "From: Someone <x@evil.example>\r\nFrom: NAB");
    const box = await newMailbox();
    await deliver(box.address, tricked, env, { resolve: fakeDns({ "s1._domainkey.nab.com.au": [record] }) });
    const [{ payload }] = await phoneFetch(box);
    expect(payload.auth.dkim).toEqual([]);
  });

  it("a fake Subject added on top of a real signed bank email proves nothing", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(NAB_ALERT, { domain: "nab.com.au", privateKey });
    const faked = `Subject: Refund of $900.00 to your card ending 1234\r\n${signed}`;
    const box = await newMailbox();
    const dns = fakeDns({ "s1._domainkey.nab.com.au": [record], "_dmarc.nab.com.au": ["v=DMARC1; p=reject"] });
    await deliver(box.address, faked, { ...env, TRUST_CLOUDFLARE_DMARC: "true" }, { resolve: dns });
    const [{ payload }] = await phoneFetch(box);
    expect(payload.subject).toContain("Refund of $900.00"); // what a parser would read...
    expect(payload.auth).toEqual({ dkim: [], dmarc: [] }); // ...so nothing is proven
  });

  it("uses DMARC p=reject only when TRUST_CLOUDFLARE_DMARC is on", async () => {
    const dns = fakeDns({ "_dmarc.nab.com.au": ["v=DMARC1; p=reject"] });
    const off = await newMailbox();
    await deliver(off.address, NAB_ALERT, env, { resolve: dns });
    expect((await phoneFetch(off))[0].payload.auth.dmarc).toEqual([]);
    const on = await newMailbox();
    await deliver(on.address, NAB_ALERT, { ...env, TRUST_CLOUDFLARE_DMARC: "true" }, { resolve: dns });
    expect((await phoneFetch(on))[0].payload.auth.dmarc).toEqual(["nab.com.au"]);
  });

  it("drops attachments and keeps only one body", async () => {
    const raw = CRLF(`From: Shop <orders@shop.example>
To: a@b.c
Subject: Your receipt
Date: Sun, 20 Sep 2026 10:00:00 +0000
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="b1"

--b1
Content-Type: multipart/alternative; boundary="b2"

--b2
Content-Type: text/plain; charset=utf-8

Total $10.00
--b2
Content-Type: text/html; charset=utf-8

<p>Total <b>$10.00</b></p>
--b2--
--b1
Content-Type: application/pdf; name="invoice.pdf"
Content-Disposition: attachment; filename="invoice.pdf"
Content-Transfer-Encoding: base64

JVBERi0xLjQKU0VDUkVUIFBERiBDT05URU5UCg==
--b1--
`);
    const box = await newMailbox();
    await deliver(box.address, raw);
    const [{ payload }] = await phoneFetch(box);
    expect(payload.text.trim()).toBe("Total $10.00");
    expect(payload).not.toHaveProperty("html");
    expect(JSON.stringify(payload)).not.toContain("invoice.pdf");
    expect(JSON.stringify(payload)).not.toContain("JVBER");
  });

  it("sends the HTML when there's no plain text part", async () => {
    const raw = CRLF(`From: Shop <orders@shop.example>\nSubject: Receipt\nContent-Type: text/html; charset=utf-8\n\n<p>Total <b>$10.00</b></p>\n`);
    const box = await newMailbox();
    await deliver(box.address, raw);
    const [{ payload }] = await phoneFetch(box);
    expect(payload.html).toContain("<b>$10.00</b>");
    expect(payload).not.toHaveProperty("text");
  });

  it("refuses mail over the size cap", async () => {
    const box = await newMailbox();
    const msg = fakeMessage(box.address, NAB_ALERT);
    msg.rawSize = LIMITS.maxRawBytes + 1;
    expect(await handleEmail(msg, env, { resolve: noDns })).toBe("rejected:too-large");
    // And if rawSize lies, the stream read stops at the cap anyway.
    const big = fakeMessage(box.address, NAB_ALERT + "x".repeat(LIMITS.maxRawBytes));
    big.rawSize = 10;
    expect(await handleEmail(big, env, { resolve: noDns })).toBe("rejected:too-large");
  });

  it("is rate limited per address", async () => {
    const box = await newMailbox();
    const e = { ...env, MAIL_LIMIT: limiter(2) };
    expect((await deliver(box.address, NAB_ALERT, e)).outcome).toBe("stored");
    expect((await deliver(box.address, NAB_ALERT, e)).outcome).toBe("stored");
    const third = await deliver(box.address, NAB_ALERT, e);
    expect(third.outcome).toBe("rejected:rate");
    expect(third.msg.rejected).toMatch(/Too many messages/);
  });

  it("refuses mail once 100 messages are waiting", async () => {
    const box = await newMailbox();
    const h = await sha256hex(box.local);
    for (let i = 0; i < LIMITS.maxPending; i++) {
      await env.INBOX.put(`m:${h}:${String(i).padStart(9, "0")}-AAAAAAAAAAAAAAAA`, "{}");
    }
    expect((await deliver(box.address, NAB_ALERT)).outcome).toBe("rejected:full");
  });

  it("refuses mail after the mailbox is turned off", async () => {
    const box = await newMailbox();
    await worker.fetch(new Request(`${BASE}/api/inbox`, { method: "DELETE", headers: box.auth }), env);
    expect((await deliver(box.address, NAB_ALERT)).outcome).toBe("rejected:unknown");
  });

  it("the email() entry point rejects instead of throwing", async () => {
    const msg = fakeMessage("abcdefghijkmnpqrstuvwxy2@in.sortd.page", NAB_ALERT);
    await worker.email(msg, { ...env, INBOX: { get() { throw new Error("KV down"); } } });
    expect(msg.rejected).toMatch(/couldn't take/);
  });
});

describe("Gmail's forwarding confirmation", () => {
  const confirmation = CRLF(`From: Gmail Team <forwarding-noreply@google.com>
To: x@in.sortd.page
Subject: (#123456789) Gmail Forwarding Confirmation - Receive Mail from raj@gmail.com
Date: Sun, 20 Sep 2026 10:00:00 +0000
Content-Type: text/plain; charset=utf-8

raj@gmail.com has requested to automatically forward mail to your email address.
Confirmation code: 123456789

To allow raj@gmail.com to automatically forward mail to your address, please click the link below to confirm the request:

https://mail-settings.google.com/mail/vf-%5BANGjdJ9example%5D-abcDEF_123

If you click the link and it appears to be broken, please copy and paste it into a new browser window.
`);

  it("is stored encrypted like any mail, marked so the app shows 'Tap to confirm'", async () => {
    const box = await newMailbox();
    expect((await deliver(box.address, confirmation)).outcome).toBe("stored");
    const [{ payload }] = await phoneFetch(box);
    expect(payload.kind).toBe("gmail-forwarding-confirmation");
    expect(payload.confirm).toEqual({
      code: "123456789",
      url: "https://mail-settings.google.com/mail/vf-%5BANGjdJ9example%5D-abcDEF_123",
    });
  });

  it("only from forwarding-noreply@google.com, and only Google's link", () => {
    const email = (from, text) => ({ from: { address: from }, subject: "(#123456789) Gmail Forwarding Confirmation - Receive Mail from a@b.c", text });
    expect(gmailConfirmation(email("someone@evil.example", "https://mail-settings.google.com/mail/vf-x"))).toBeNull();
    const phish = gmailConfirmation(email("forwarding-noreply@google.com", "click https://evil.example/mail/vf-x"));
    expect(phish).toEqual({ code: "123456789", url: null });
    expect(gmailConfirmation({ from: { address: "forwarding-noreply@google.com" }, subject: "Security alert", text: "" })).toBeNull();
  });
});

describe("Gmail filter file", () => {
  it("has the Atom shape Gmail exports, with hasTheWord and forwardTo, escaped", () => {
    const xml = filterXml("abcdefghijkmnpqrstuvwxyz@in.sortd.page", gmailQuery());
    expect(xml).toMatch(/^<\?xml version='1.0' encoding='UTF-8'\?>\n<feed xmlns='http:\/\/www.w3.org\/2005\/Atom' xmlns:apps='http:\/\/schemas.google.com\/apps\/2006'>/);
    expect(xml).toContain("<category term='filter'></category>");
    expect(xml).toContain("<apps:property name='forwardTo' value='abcdefghijkmnpqrstuvwxyz@in.sortd.page'/>");
    expect(xml).toContain("&quot;order confirmation&quot;");
    expect(xml).not.toMatch(/value='[^']*"[^']*'/); // no raw quotes inside attributes
    expect(filterXml("a'b<c>&", "q")).toContain("value='a&apos;b&lt;c&gt;&amp;'");
  });

  it("asks for every bank and receipt sender", () => {
    const q = gmailQuery();
    for (const d of ["nab.com.au", "dbs.com", "uob.com.sg", "cimb.com", "doordash.com", "email.apple.com", "stripe.com"]) {
      expect(q).toContain(d);
    }
  });
});
