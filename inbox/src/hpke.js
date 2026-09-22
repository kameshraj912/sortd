// HPKE (RFC 9180), base mode, the one suite the iPhone app speaks:
//   DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM
// = CryptoKit's HPKE.Ciphersuite.P256_SHA256_AES_GCM_256.
//
// P-256 rather than X25519 because the iPhone keeps the private key inside the
// Secure Enclave, which only does P-256. Everything here is plain WebCrypto.
import { Aes256Gcm, CipherSuite, DhkemP256HkdfSha256, HkdfSha256 } from "@hpke/core";

export const SUITE_NAME = "P256_SHA256_AES_GCM_256";
/** Binds every ciphertext to this protocol and version. The app uses the same bytes. */
export const INFO = new TextEncoder().encode("sortd-inbox/v1");

export const suite = new CipherSuite({ kem: new DhkemP256HkdfSha256(), kdf: new HkdfSha256(), aead: new Aes256Gcm() });

/**
 * Checks a public key from the app: 65 bytes, uncompressed (0x04), and a real
 * point on P-256 (WebCrypto refuses points that aren't on the curve).
 */
export async function importPublicKey(raw) {
  if (!(raw instanceof Uint8Array) || raw.length !== 65 || raw[0] !== 0x04) throw new Error("bad key");
  return suite.kem.deserializePublicKey(raw);
}

/** Encrypts `plaintext` to the app's key. `aad` is authenticated but not encrypted. */
export async function seal(publicKey, plaintext, aad, { info = INFO, ekm } = {}) {
  const params = { recipientPublicKey: publicKey, info };
  if (ekm) params.ekm = ekm; // tests only: a fixed ephemeral key, to reproduce RFC 9180 vectors
  const { enc, ct } = await suite.seal(params, plaintext, aad);
  return { enc: new Uint8Array(enc), ct: new Uint8Array(ct) };
}

/** Only tests use this: the server never holds a private key. */
export async function open(privateKey, enc, ct, aad, info = INFO) {
  return new Uint8Array(await suite.open({ recipientKey: privateKey, enc, info }, ct, aad));
}
