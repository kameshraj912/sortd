// Writes test/fixtures/js-to-swift.json: a message sealed by the Worker's own
// seal() code, for SpendTests/ForwardingInboxTests.swift to open with CryptoKit.
// Deterministic (fixed recipient key and fixed ephemeral key), so running it
// again gives the same file. Run: npm run vector
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { importPublicKey, seal, suite, INFO, SUITE_NAME } from "../src/hpke.js";
import { b64u, hex, sha256 } from "../src/util.js";

// RFC 9180 DeriveKeyPair from a fixed seed: a test-only key, never used for real mail.
const pair = await suite.kem.deriveKeyPair(await sha256("sortd-inbox interop test recipient v1"));
const recipientSk = new Uint8Array(await suite.kem.serializePrivateKey(pair.privateKey));
const pkRaw = new Uint8Array(await suite.kem.serializePublicKey(pair.publicKey));
const pk = await importPublicKey(pkRaw);

const id = "mfq2x9a1b-interopVector001";
const payload = {
  v: 1,
  kind: "mail",
  messageId: "<alert-58-30@nab.com.au>",
  from: "NAB <alerts@nab.com.au>",
  subject: "Transaction alert",
  date: "2026-09-20T01:30:00.000Z",
  receivedAt: "2026-09-20T01:30:05.000Z",
  text: "A purchase of $58.30 was made at WOOLWORTHS 3342 on your card ending 1234.",
  auth: { dkim: ["nab.com.au"], dmarc: [] },
};
const plaintext = new TextEncoder().encode(JSON.stringify(payload));
const ekm = await sha256("sortd-inbox interop test ephemeral v1");
const { enc, ct } = await seal(pk, plaintext, new TextEncoder().encode(id), { ekm });

const out = {
  note: "Made by inbox/scripts/make-vector.mjs with the Worker's seal(). Test key only.",
  suite: SUITE_NAME,
  info: new TextDecoder().decode(INFO),
  recipientPrivateKeyHex: hex(recipientSk),
  recipientPublicKeyB64u: b64u(pkRaw),
  id,
  enc: b64u(enc),
  ct: b64u(ct),
  payload,
};
const path = fileURLToPath(new URL("../test/fixtures/js-to-swift.json", import.meta.url));
writeFileSync(path, JSON.stringify(out, null, 2) + "\n");
console.log(`wrote ${path}`);
