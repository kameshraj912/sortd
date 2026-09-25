// App Attest: verify the attestation of a FRESH key, once per call (spec: Protection).
//
// We never use assertions, because those need the server to keep each device's public key
// and counter, and this Worker stores nothing. The app instead calls generateKey, then
// attestKey(keyId, clientDataHash: SHA256(challenge)), and sends the result.
//
// Steps follow Apple's "Validating apps that connect to your server", "Verify the attestation":
// https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server
//   1. x5c: leaf -> intermediate -> Apple App Attestation Root CA (pinned below).
//   2. clientDataHash = SHA256(challenge).
//   3. nonce = SHA256(authData || clientDataHash).
//   4. nonce == the leaf's extension 1.2.840.113635.100.8.2.
//   5. keyId == SHA256(leaf public key).
//   6. rpIdHash == SHA256(teamId + "." + bundleId).
//   7. counter == 0.
//   8. aaguid == "appattest" + 7 zero bytes ("appattestdevelop" only when allowed: ENV=dev).
//   9. credentialId == keyId.
// The receipt in attStmt is not used: we do not do fraud-metric risk checks.
//
// Chain checks done here: each signature (ECDSA via WebCrypto), each certificate's validity
// window at "now", issuer name == parent's subject name, and basicConstraints cA=true on the
// intermediate. Not done: revocation (Apple publishes no CRL/OCSP for this CA that the docs
// ask servers to check), name constraints, key usage, policy mapping. The root is pinned, so
// nothing from the request can add a trust anchor.
//
// Only WebCrypto and the small DER and CBOR readers below. No libraries.

import { b64decode, concat, equalBytes, pemToDer, sha256, utf8 } from "./bytes";
import { WorkerError } from "./errors";

export { pemToDer };

/**
 * Apple App Attestation Root CA.
 * From https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
 * (Apple PKI: https://www.apple.com/certificateauthority/private/).
 * Valid 18 Mar 2020 to 15 Mar 2045. SHA-256 fingerprint
 * 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32
 * A test checks that it parses and that its self-signature verifies.
 */
export const APPLE_APP_ATTEST_ROOT_PEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

export interface AttestInput {
  /** Base64 key id, as the app's DCAppAttestService gives it. */
  keyId: string;
  /** Base64 CBOR attestation object. */
  attestation: string;
  /** The challenge string; clientDataHash = SHA256(UTF-8 of it). */
  challenge: string;
  teamId: string;
  bundleId: string;
  /** Accept the "appattestdevelop" environment (ENV=dev only). */
  allowDevelop: boolean;
  nowMs: number;
  /** DER of the pinned root(s). */
  roots: Uint8Array[];
}

const OID_NONCE = "1.2.840.113635.100.8.2";
const OID_BASIC_CONSTRAINTS = "2.5.29.19";
const OID_CN = "2.5.4.3";
const OID_EC_PUBLIC_KEY = "1.2.840.10045.2.1";
const CURVES: Record<string, { name: "P-256" | "P-384"; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const SIG_HASH: Record<string, "SHA-256" | "SHA-384" | "SHA-512"> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
  "1.2.840.10045.4.3.4": "SHA-512",
};
const AAGUID_PROD = concat(utf8("appattest"), new Uint8Array(7));
const AAGUID_DEV = utf8("appattestdevelop");

const invalid = (): never => {
  throw new WorkerError("attest_invalid");
};

// ---------------- DER reader ----------------

interface Tlv {
  tag: number;
  /** The whole element, header included. */
  raw: Uint8Array;
  content: Uint8Array;
}

function readTlv(buf: Uint8Array, off: number): { tlv: Tlv; next: number } {
  if (off + 2 > buf.length) throw new Error("der: truncated");
  const tag = buf[off]!;
  if ((tag & 0x1f) === 0x1f) throw new Error("der: high tag numbers not supported");
  let len = buf[off + 1]!;
  let hdr = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 3) throw new Error("der: bad length");
    len = 0;
    for (let i = 0; i < n; i++) len = (len << 8) | buf[off + 2 + i]!;
    hdr += n;
  }
  const end = off + hdr + len;
  if (end > buf.length) throw new Error("der: overrun");
  return { tlv: { tag, raw: buf.subarray(off, end), content: buf.subarray(off + hdr, end) }, next: end };
}

function readOne(buf: Uint8Array, tag?: number): Tlv {
  const { tlv, next } = readTlv(buf, 0);
  if (next !== buf.length) throw new Error("der: trailing bytes");
  if (tag !== undefined && tlv.tag !== tag) throw new Error("der: unexpected tag");
  return tlv;
}

function children(t: Tlv): Tlv[] {
  const out: Tlv[] = [];
  let off = 0;
  while (off < t.content.length) {
    const { tlv, next } = readTlv(t.content, off);
    out.push(tlv);
    off = next;
  }
  return out;
}

function expectTag(t: Tlv | undefined, tag: number): Tlv {
  if (!t || t.tag !== tag) throw new Error("der: unexpected tag");
  return t;
}

function oidString(t: Tlv): string {
  expectTag(t, 0x06);
  const b = t.content;
  if (b.length === 0) throw new Error("der: empty oid");
  const arcs: number[] = [];
  let v = 0;
  for (let i = 0; i < b.length; i++) {
    v = v * 128 + (b[i]! & 0x7f);
    if (!(b[i]! & 0x80)) {
      if (arcs.length === 0) arcs.push(v < 80 ? Math.floor(v / 40) : 2, v < 80 ? v % 40 : v - 80);
      else arcs.push(v);
      v = 0;
    }
  }
  return arcs.join(".");
}

function bitStringBytes(t: Tlv): Uint8Array {
  expectTag(t, 0x03);
  if (t.content[0] !== 0) throw new Error("der: unused bits");
  return t.content.subarray(1);
}

function parseTime(t: Tlv): number {
  const s = new TextDecoder().decode(t.content);
  let m: RegExpMatchArray | null;
  if (t.tag === 0x17 && (m = s.match(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/))) {
    const yy = Number(m[1]);
    return Date.UTC(yy < 50 ? 2000 + yy : 1900 + yy, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
  }
  if (t.tag === 0x18 && (m = s.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/))) {
    return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
  }
  throw new Error("der: bad time");
}

// ---------------- X.509 ----------------

export interface Certificate {
  tbs: Uint8Array;
  subject: Uint8Array;
  issuer: Uint8Array;
  subjectCommonName: string;
  notBefore: number;
  notAfter: number;
  sigHash: "SHA-256" | "SHA-384" | "SHA-512";
  /** DER ECDSA signature from the certificate. */
  signature: Uint8Array;
  spki: Uint8Array;
  curve: { name: "P-256" | "P-384"; size: number };
  /** The EC point from the SPKI (uncompressed, 0x04 || X || Y). */
  publicKey: Uint8Array;
  isCA: boolean;
  extensions: Map<string, Uint8Array>;
}

export function parseCertificate(der: Uint8Array): Certificate {
  const cert = readOne(der, 0x30);
  const [tbsT, sigAlgT, sigT] = children(cert);
  const tbsSeq = expectTag(tbsT, 0x30);
  const sigHash = SIG_HASH[oidString(children(expectTag(sigAlgT, 0x30))[0]!)];
  if (!sigHash) throw new Error("x509: unsupported signature algorithm");
  const signature = bitStringBytes(expectTag(sigT, 0x03));

  const f = children(tbsSeq);
  let i = 0;
  if (f[0]?.tag === 0xa0) i++; // version
  i++; // serial
  const innerAlg = SIG_HASH[oidString(children(expectTag(f[i++], 0x30))[0]!)];
  if (innerAlg !== sigHash) throw new Error("x509: algorithm mismatch");
  const issuer = expectTag(f[i++], 0x30);
  const validity = children(expectTag(f[i++], 0x30));
  const subject = expectTag(f[i++], 0x30);
  const spkiT = expectTag(f[i++], 0x30);

  const [algT, keyT] = children(spkiT);
  const alg = children(expectTag(algT, 0x30));
  if (oidString(alg[0]!) !== OID_EC_PUBLIC_KEY) throw new Error("x509: not an EC key");
  const curve = CURVES[oidString(alg[1]!)];
  if (!curve) throw new Error("x509: unsupported curve");
  const publicKey = bitStringBytes(expectTag(keyT, 0x03));

  const extensions = new Map<string, Uint8Array>();
  for (; i < f.length; i++) {
    if (f[i]!.tag !== 0xa3) continue;
    const list = readOne(f[i]!.content, 0x30);
    for (const ext of children(list)) {
      const parts = children(expectTag(ext, 0x30));
      const id = oidString(parts[0]!);
      const value = expectTag(parts[parts.length - 1], 0x04).content;
      if (extensions.has(id)) throw new Error("x509: duplicate extension");
      extensions.set(id, value);
    }
  }

  let isCA = false;
  const bc = extensions.get(OID_BASIC_CONSTRAINTS);
  if (bc) {
    const first = children(readOne(bc, 0x30))[0];
    isCA = first?.tag === 0x01 && first.content[0] !== 0;
  }

  let subjectCommonName = "";
  for (const rdn of children(subject)) {
    for (const atv of children(rdn)) {
      const [type, value] = children(atv);
      if (type && value && oidString(type) === OID_CN) subjectCommonName = new TextDecoder().decode(value.content);
    }
  }

  return {
    tbs: tbsSeq.raw,
    subject: subject.raw,
    issuer: issuer.raw,
    subjectCommonName,
    notBefore: parseTime(validity[0]!),
    notAfter: parseTime(validity[1]!),
    sigHash,
    signature,
    spki: spkiT.raw,
    curve,
    publicKey,
    isCA,
    extensions,
  };
}

/** X.509 ECDSA signatures are DER SEQUENCE { r, s }; WebCrypto wants fixed-size r || s. */
function derSigToRaw(sig: Uint8Array, size: number): Uint8Array {
  const [r, s] = children(readOne(sig, 0x30));
  const fix = (t: Tlv | undefined) => {
    let v = expectTag(t, 0x02).content;
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    if (v.length > size) throw new Error("ecdsa: integer too long");
    const out = new Uint8Array(size);
    out.set(v, size - v.length);
    return out;
  };
  return concat(fix(r), fix(s));
}

/** True when `parent`'s key made `child`'s signature. */
export async function verifySignedBy(child: Certificate, parent: Certificate): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey("spki", parent.spki, { name: "ECDSA", namedCurve: parent.curve.name }, false, ["verify"]);
    return await crypto.subtle.verify({ name: "ECDSA", hash: child.sigHash }, key, derSigToRaw(child.signature, parent.curve.size), child.tbs);
  } catch {
    return false;
  }
}

const inDate = (c: Certificate, now: number) => c.notBefore <= now && now <= c.notAfter;

async function chainIsValid(leaf: Certificate, intermediate: Certificate, roots: Certificate[], now: number): Promise<boolean> {
  if (!inDate(leaf, now) || !inDate(intermediate, now)) return false;
  if (!intermediate.isCA) return false;
  if (!equalBytes(leaf.issuer, intermediate.subject)) return false;
  if (!(await verifySignedBy(leaf, intermediate))) return false;
  for (const root of roots) {
    if (!inDate(root, now) || !equalBytes(intermediate.issuer, root.subject)) continue;
    if (await verifySignedBy(intermediate, root)) return true;
  }
  return false;
}

// ---------------- CBOR reader (definite lengths only; enough for an attestation object) ----------------

type Cbor = number | string | boolean | null | Uint8Array | Cbor[] | Map<Cbor, Cbor>;

function decodeCbor(buf: Uint8Array): Cbor {
  let off = 0;
  const need = (n: number) => {
    if (off + n > buf.length) throw new Error("cbor: truncated");
  };
  const arg = (info: number): number => {
    if (info < 24) return info;
    const n = info === 24 ? 1 : info === 25 ? 2 : info === 26 ? 4 : info === 27 ? 8 : 0;
    if (!n) throw new Error("cbor: unsupported length");
    need(n);
    let v = 0;
    for (let i = 0; i < n; i++) v = v * 256 + buf[off++]!;
    if (!Number.isSafeInteger(v)) throw new Error("cbor: too big");
    return v;
  };
  const item = (depth: number): Cbor => {
    if (depth > 8) throw new Error("cbor: too deep");
    need(1);
    const b = buf[off++]!;
    const major = b >> 5;
    const info = b & 0x1f;
    switch (major) {
      case 0:
        return arg(info);
      case 1:
        return -1 - arg(info);
      case 2:
      case 3: {
        const n = arg(info);
        need(n);
        const bytes = buf.slice(off, off + n);
        off += n;
        return major === 2 ? bytes : new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
      }
      case 4: {
        const n = arg(info);
        if (n > buf.length) throw new Error("cbor: bad count");
        const out: Cbor[] = [];
        for (let i = 0; i < n; i++) out.push(item(depth + 1));
        return out;
      }
      case 5: {
        const n = arg(info);
        if (n > buf.length) throw new Error("cbor: bad count");
        const out = new Map<Cbor, Cbor>();
        for (let i = 0; i < n; i++) {
          const k = item(depth + 1);
          out.set(k, item(depth + 1));
        }
        return out;
      }
      case 6:
        arg(info);
        return item(depth + 1);
      default:
        if (info === 20) return false;
        if (info === 21) return true;
        if (info === 22) return null;
        throw new Error("cbor: unsupported simple value");
    }
  };
  const v = item(0);
  if (off !== buf.length) throw new Error("cbor: trailing bytes");
  return v;
}

// ---------------- the check ----------------

export async function verifyAttestation(input: AttestInput): Promise<void> {
  try {
    await verify(input);
  } catch (e) {
    if (e instanceof WorkerError) throw e;
    invalid(); // any parse failure is an invalid attestation
  }
}

async function verify(input: AttestInput): Promise<void> {
  const keyId = b64decode(input.keyId);
  const objBytes = b64decode(input.attestation);
  if (!keyId || keyId.length !== 32 || !objBytes || objBytes.length === 0) invalid();

  const obj = decodeCbor(objBytes!);
  if (!(obj instanceof Map) || obj.get("fmt") !== "apple-appattest") invalid();
  const attStmt = (obj as Map<Cbor, Cbor>).get("attStmt");
  const authData = (obj as Map<Cbor, Cbor>).get("authData");
  if (!(attStmt instanceof Map) || !(authData instanceof Uint8Array)) invalid();
  const x5c = (attStmt as Map<Cbor, Cbor>).get("x5c");
  if (!Array.isArray(x5c) || x5c.length !== 2 || !x5c.every((c) => c instanceof Uint8Array)) invalid();
  const [leafDer, intermediateDer] = x5c as Uint8Array[];
  const ad = authData as Uint8Array;

  // 1. Certificate chain to the pinned root.
  const leaf = parseCertificate(leafDer!);
  const intermediate = parseCertificate(intermediateDer!);
  const roots = input.roots.map(parseCertificate);
  if (roots.length === 0) invalid();
  if (!(await chainIsValid(leaf, intermediate, roots, input.nowMs))) invalid();
  if (leaf.curve.name !== "P-256" || leaf.publicKey.length !== 65) invalid();

  // 2-4. Nonce.
  const clientDataHash = await sha256(utf8(input.challenge));
  const nonce = await sha256(concat(ad, clientDataHash));
  const ext = leaf.extensions.get(OID_NONCE);
  if (!ext) invalid();
  const tagged = children(readOne(ext!, 0x30)).find((t) => t.tag === 0xa1);
  if (!tagged) invalid();
  const certNonce = readOne(tagged!.content, 0x04).content;
  if (!equalBytes(certNonce, nonce)) invalid();

  // 5. keyId == SHA256(public key).
  if (!equalBytes(keyId!, await sha256(leaf.publicKey))) invalid();

  // authData: rpIdHash(32) flags(1) signCount(4) aaguid(16) credIdLen(2) credId(n) credentialPublicKey
  if (ad.length < 55) invalid();
  // 6. rpIdHash == SHA256(App ID).
  if (!equalBytes(ad.subarray(0, 32), await sha256(utf8(`${input.teamId}.${input.bundleId}`)))) invalid();
  // Attested credential data must be present (AT flag).
  if (!(ad[32]! & 0x40)) invalid();
  // 7. counter == 0.
  if (new DataView(ad.buffer, ad.byteOffset + 33, 4).getUint32(0) !== 0) invalid();
  // 8. aaguid.
  const aaguid = ad.subarray(37, 53);
  const aaguidOk = equalBytes(aaguid, AAGUID_PROD) || (input.allowDevelop && equalBytes(aaguid, AAGUID_DEV));
  if (!aaguidOk) invalid();
  // 9. credentialId == keyId.
  const credLen = (ad[53]! << 8) | ad[54]!;
  if (ad.length < 55 + credLen) invalid();
  if (!equalBytes(ad.subarray(55, 55 + credLen), keyId!)) invalid();
}
