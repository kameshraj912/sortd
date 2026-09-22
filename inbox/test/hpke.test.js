import { describe, expect, it } from "vitest";
import { importPublicKey, open, seal, suite } from "../src/hpke.js";
import { unb64u } from "../src/util.js";
import rfc from "./fixtures/hpke-rfc9180-p256-sha256-aes256gcm.json";
import jsToSwift from "./fixtures/js-to-swift.json";
import swiftToJs from "./fixtures/swift-to-js.json";

const fromHex = (h) => new Uint8Array(h.match(/../g).map((b) => parseInt(b, 16)));
const toHex = (u) => [...u].map((b) => b.toString(16).padStart(2, "0")).join("");
const utf8 = (s) => new TextEncoder().encode(s);

describe("HPKE P256_SHA256_AES_GCM_256", () => {
  it("reproduces the official RFC 9180 test vector exactly", async () => {
    const pk = await importPublicKey(fromHex(rfc.pkRm));
    const { enc, ct } = await seal(pk, fromHex(rfc.encryption.pt), fromHex(rfc.encryption.aad), {
      info: fromHex(rfc.info), ekm: fromHex(rfc.ikmE),
    });
    expect(toHex(enc)).toBe(rfc.enc);
    expect(toHex(ct)).toBe(rfc.encryption.ct);
  });

  it("opens the official RFC 9180 test vector", async () => {
    const sk = await suite.kem.deserializePrivateKey(fromHex(rfc.skRm));
    const pt = await open(sk, fromHex(rfc.enc), fromHex(rfc.encryption.ct), fromHex(rfc.encryption.aad), fromHex(rfc.info));
    expect(toHex(pt)).toBe(rfc.encryption.pt);
  });

  it("opens a message sealed by Apple CryptoKit (Swift -> JS interop)", async () => {
    const sk = await suite.kem.deserializePrivateKey(fromHex(jsToSwift.recipientPrivateKeyHex));
    const pt = await open(sk, unb64u(swiftToJs.enc), unb64u(swiftToJs.ct), utf8(swiftToJs.id));
    expect(new TextDecoder().decode(pt)).toBe(swiftToJs.plaintext);
  });

  it("the JS -> Swift fixture is current: the Worker's seal() still produces it", async () => {
    const sk = await suite.kem.deserializePrivateKey(fromHex(jsToSwift.recipientPrivateKeyHex));
    const pt = await open(sk, unb64u(jsToSwift.enc), unb64u(jsToSwift.ct), utf8(jsToSwift.id));
    expect(JSON.parse(new TextDecoder().decode(pt))).toEqual(jsToSwift.payload);
  });

  it("round-trips, and a wrong message id (aad) or key fails", async () => {
    const pair = await suite.kem.generateKeyPair();
    const raw = new Uint8Array(await suite.kem.serializePublicKey(pair.publicKey));
    const pk = await importPublicKey(raw);
    const { enc, ct } = await seal(pk, utf8("hello"), utf8("id-1"));
    expect(new TextDecoder().decode(await open(pair.privateKey, enc, ct, utf8("id-1")))).toBe("hello");
    await expect(open(pair.privateKey, enc, ct, utf8("id-2"))).rejects.toThrow();
    const other = await suite.kem.generateKeyPair();
    await expect(open(other.privateKey, enc, ct, utf8("id-1"))).rejects.toThrow();
    // Each seal uses a fresh ephemeral key: same input, different output.
    const again = await seal(pk, utf8("hello"), utf8("id-1"));
    expect(toHex(again.enc)).not.toBe(toHex(enc));
  });

  it("refuses public keys that aren't uncompressed P-256 points", async () => {
    const good = fromHex(rfc.pkRm);
    await expect(importPublicKey(good.subarray(0, 33))).rejects.toThrow();
    const compressed = new Uint8Array(65); compressed.set(good); compressed[0] = 0x02;
    await expect(importPublicKey(compressed)).rejects.toThrow();
    const offCurve = new Uint8Array(good); offCurve[64] ^= 1;
    await expect(importPublicKey(offCurve)).rejects.toThrow();
  });
});
