import { describe, expect, it } from "vitest";
import { blankSignature, canonBody, canonHeaderRelaxed, dmarcRejectDomains, verifyDkim } from "../src/dkim.js";
import { joinTxt } from "../src/dns.js";
import { CRLF, dkimSign, fakeDns, rsaKey } from "./helpers.js";

// RFC 8463 Appendix A.3, byte for byte: two signatures (Ed25519 and RSA) by
// football.example.com, keys from A.2. An outside test vector: it checks the
// canonicalisation and both algorithms against someone else's implementation.
const RFC8463 = CRLF(`DKIM-Signature: v=1; a=ed25519-sha256; c=relaxed/relaxed;
 d=football.example.com; i=@football.example.com;
 q=dns/txt; s=brisbane; t=1528637909; h=from : to :
 subject : date : message-id : from : subject : date;
 bh=2jUSOH9NhtVGCQWNr9BrIAPreKQjO6Sn7XIkfJVOzv8=;
 b=/gCrinpcQOoIfuHNQIbq4pgh9kyIK3AQUdt9OdqQehSwhEIug4D11Bus
 Fa3bT3FY5OsU7ZbnKELq+eXdp1Q1Dw==
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed;
 d=football.example.com; i=@football.example.com;
 q=dns/txt; s=test; t=1528637909; h=from : to : subject :
 date : message-id : from : subject : date;
 bh=2jUSOH9NhtVGCQWNr9BrIAPreKQjO6Sn7XIkfJVOzv8=;
 b=F45dVWDfMbQDGHJFlXUNB2HKfbCeLRyhDXgFpEL8GwpsRe0IeIixNTe3
 DhCVlUrSjV4BwcVcOF6+FF3Zo9Rpo1tFOeS9mPYQTnGdaSGsgeefOsk2Jz
 dA+L10TeYt9BgDfQNZtKdN1WO//KgIqXP7OdEFE4LjFYNcUxZQ4FADY+8=
From: Joe SixPack <joe@football.example.com>
To: Suzie Q <suzie@shopping.example.net>
Subject: Is dinner ready?
Date: Fri, 11 Jul 2003 21:00:37 -0700 (PDT)
Message-ID: <20030712040037.46341.5F8J@football.example.com>

Hi.

We lost the game.  Are you hungry yet?

Joe.
`);

const RFC_DNS = {
  "brisbane._domainkey.football.example.com": [joinTxt('"v=DKIM1; k=ed25519; p=11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="')],
  "test._domainkey.football.example.com": [joinTxt(
    '"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDkHlOQoBTzWR" "iGs5V6NpP3idY6Wk08a5qhdR6wy5bdOKb2jLQiY/J16JYi0Qvx/byYzCNb3W91y3FutAC" "DfzwQ/BC/e/8uBsCR+yz1Lxj+PL6lHvqMKrM3rG4hstT5QjvHO9PzoxZyVYLzBfO2EeC3" "Ip3G+2kryOTIKT+l/K4w3QIDAQAB"')],
};

const bytes = (s) => new TextEncoder().encode(s);
const verify = (raw, dns = RFC_DNS, now = Date.now()) => verifyDkim(bytes(raw), { resolve: fakeDns(dns), now });

describe("DKIM against RFC 8463's signed example", () => {
  it("passes both the Ed25519 and the RSA signature", async () => {
    const r = await verify(RFC8463);
    expect(r.results.map((x) => x.result)).toEqual(["pass", "pass"]);
    expect(r.domains).toEqual(["football.example.com"]);
  });

  it("still passes when whitespace changes in transit (relaxed canonicalisation)", async () => {
    const r = await verify(RFC8463.replace("Subject: Is dinner ready?", "Subject:   Is dinner   ready?  ")
      .replace("Are you hungry yet?", "Are you hungry yet?   "));
    expect(r.results.map((x) => x.result)).toEqual(["pass", "pass"]);
  });

  it("fails when the body is changed", async () => {
    const r = await verify(RFC8463.replace("We lost the game.", "We won the game."));
    expect(r.results.map((x) => x.result)).toEqual(["body hash mismatch", "body hash mismatch"]);
    expect(r.domains).toEqual([]);
  });

  it("fails when a signed header is changed", async () => {
    const r = await verify(RFC8463.replace("Subject: Is dinner ready?", "Subject: Refund of $500"));
    expect(r.results.map((x) => x.result)).toEqual(["bad signature", "bad signature"]);
  });

  it("fails when someone adds a second From above the signed one (over-signing)", async () => {
    const r = await verify(RFC8463.replace("From: Joe", "From: Bank <alerts@dbs.com>\r\nFrom: Joe"));
    // h= lists "from" twice, so the extra From is covered and breaks the signature.
    expect(r.domains).toEqual([]);
  });

  it("fails with no key, a revoked key, or a DNS error", async () => {
    expect((await verify(RFC8463, {})).results.map((x) => x.result)).toEqual(["no key", "no key"]);
    const revoked = { "brisbane._domainkey.football.example.com": ["v=DKIM1; k=ed25519; p="] };
    expect((await verify(RFC8463, revoked)).results[0].result).toBe("key revoked");
    const broken = async () => { throw new Error("SERVFAIL"); };
    const r = await verifyDkim(bytes(RFC8463), { resolve: broken });
    expect(r.domains).toEqual([]);
    expect(r.results[0].result).toBe("key lookup failed");
  });
});

describe("DKIM rules Sortd adds", () => {
  const plain = CRLF(`From: Shop <orders@shop.example>\nTo: a@b.c\nSubject: Receipt\nDate: Sun, 20 Sep 2026 10:00:00 +0000\nMessage-ID: <1@shop.example>\n\nTotal $10.00\n`);

  it("verifies a message it signed with simple/simple too", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(plain, { domain: "shop.example", privateKey, c: "simple/simple" });
    const r = await verify(signed, { "s1._domainkey.shop.example": [record] });
    expect(r.domains).toEqual(["shop.example"]);
    // simple means exact: extra spaces now break it.
    const spaced = await verify(signed.replace("Subject: Receipt", "Subject:  Receipt"), { "s1._domainkey.shop.example": [record] });
    expect(spaced.domains).toEqual([]);
  });

  it("refuses l= (body length) signatures, since anyone could append text", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(plain, { domain: "shop.example", privateKey, extraTags: " l=5;" });
    expect((await verify(signed, { "s1._domainkey.shop.example": [record] })).results[0].result).toBe("l= refused");
  });

  it("refuses signatures that don't cover From", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(plain, { domain: "shop.example", privateKey, headers: ["subject", "date"] });
    expect((await verify(signed, { "s1._domainkey.shop.example": [record] })).results[0].result).toBe("from not signed");
  });

  it("refuses signatures that don't cover Subject (the parsers read amounts from it)", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(plain, { domain: "shop.example", privateKey, headers: ["from", "date"] });
    expect((await verify(signed, { "s1._domainkey.shop.example": [record] })).results[0].result).toBe("subject not signed");
  });

  it("an extra Subject (or Content-Type) added above a real signed email proves nothing", async () => {
    // DKIM checks the bottom-most Subject; a mail parser reads the top one.
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(plain, { domain: "shop.example", privateKey });
    const dns = { "s1._domainkey.shop.example": [record] };
    expect((await verify(signed, dns)).domains).toEqual(["shop.example"]);
    const faked = `Subject: Refund of SGD 900.00 credited to your card\r\n${signed}`;
    const r = await verify(faked, dns);
    expect(r.domains).toEqual([]);
    expect(r.results[0].result).toBe("repeated subject");
    const typed = await dkimSign(plain.replace("Subject: Receipt", "Subject: Receipt\r\nContent-Type: text/plain"), { domain: "shop.example", privateKey });
    expect((await verify(`Content-Type: text/html\r\n${typed}`, dns)).results[0].result).toBe("repeated content-type");
  });

  it("tries every key record under a selector", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(plain, { domain: "shop.example", privateKey });
    const dns = { "s1._domainkey.shop.example": ["v=DKIM1; k=ed25519; p=11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=", record] };
    expect((await verify(signed, dns)).domains).toEqual(["shop.example"]);
  });

  it("refuses rsa-sha1 and expired signatures", async () => {
    const { privateKey, record } = await rsaKey();
    const signed = await dkimSign(plain, { domain: "shop.example", privateKey });
    const sha1 = signed.replace("a=rsa-sha256", "a=rsa-sha1");
    expect((await verify(sha1, { "s1._domainkey.shop.example": [record] })).results[0].result).toBe("algorithm rsa-sha1 refused");
    const expiring = await dkimSign(plain, { domain: "shop.example", privateKey, extraTags: " x=1700000000;" });
    expect((await verify(expiring, { "s1._domainkey.shop.example": [record] })).results[0].result).toBe("expired");
  });

  it("refuses RSA keys under 1024 bits", async () => {
    const pair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 512, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
    const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
    const signed = await dkimSign(plain, { domain: "shop.example", privateKey: pair.privateKey });
    const dns = { "s1._domainkey.shop.example": [`v=DKIM1; k=rsa; p=${btoa(String.fromCharCode(...spki))}`] };
    expect((await verify(signed, dns)).results[0].result).toBe("rsa key too short");
  }, 20000);

  it("a signature from one domain says nothing about another", async () => {
    const { privateKey, record } = await rsaKey();
    // The attacker signs with their own domain but claims to be a bank in From.
    const forged = plain.replace("Shop <orders@shop.example>", "DBS <ibanking.alert@dbs.com>");
    const signed = await dkimSign(forged, { domain: "evil.example", privateKey });
    const r = await verify(signed, { "s1._domainkey.evil.example": [record] });
    expect(r.domains).toEqual(["evil.example"]); // the app then refuses it for dbs.com
  });
});

describe("canonicalisation details (RFC 6376 section 3.4)", () => {
  it("empties only the b= tag, not 'b=' inside another tag", () => {
    const sig = "DKIM-Signature: v=1; z=From:a|Subject:b=3Dx; bh=AAA=;\r\n b=abc\r\n def";
    expect(blankSignature(sig)).toBe("DKIM-Signature: v=1; z=From:a|Subject:b=3Dx; bh=AAA=;\r\n b=");
    expect(blankSignature("DKIM-Signature: b=xyz; v=1")).toBe("DKIM-Signature: b=; v=1");
  });
  it("relaxed header", () => {
    expect(canonHeaderRelaxed("SubJect:  A \r\n\t B  ")).toBe("subject:A B");
  });
  it("bodies", () => {
    expect(canonBody("", false)).toBe("\r\n");
    expect(canonBody("", true)).toBe("");
    expect(canonBody("a  b \r\n\r\n\r\n", true)).toBe("a b\r\n");
    expect(canonBody("a  b \r\n\r\n", false)).toBe("a  b \r\n");
  });
});

describe("DMARC policy (only used with TRUST_CLOUDFLARE_DMARC)", () => {
  it("trusts only a full p=reject on the From domain itself", async () => {
    const dns = fakeDns({
      "_dmarc.dbs.com": ["v=DMARC1; p=reject; rua=mailto:x@dbs.com"],
      "_dmarc.soft.example": ["v=DMARC1; p=quarantine"],
      "_dmarc.half.example": ["v=DMARC1; p=reject; pct=50"],
      "_dmarc.example.org": ["v=DMARC1; p=reject"],
    });
    expect(await dmarcRejectDomains("dbs.com", dns)).toEqual(["dbs.com"]);
    expect(await dmarcRejectDomains("soft.example", dns)).toEqual([]);
    expect(await dmarcRejectDomains("half.example", dns)).toEqual([]);
    expect(await dmarcRejectDomains("nobody.example", dns)).toEqual([]);
    // A subdomain doesn't borrow its parent's policy here (deliberately conservative).
    expect(await dmarcRejectDomains("alerts.example.org", dns)).toEqual([]);
  });
});
