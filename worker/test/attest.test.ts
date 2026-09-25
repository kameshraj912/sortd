import { describe, expect, it } from "vitest";
import {
  APPLE_APP_ATTEST_ROOT_PEM,
  APPLE_APP_ATTEST_ROOT_SHA256,
  parseCertificate,
  pemToDer,
  verifyAttestation,
  verifySignedBy,
  type AttestInput,
} from "../src/attest";
import { CLIENT_ID, NOW, TEAM_ID, hex, makeAttestation, makeCA, sha256, testCA, type AttestOptions } from "./helpers";

const CHALLENGE = "test-challenge-string";

async function run(opts: Partial<AttestOptions> = {}, input: Partial<AttestInput> = {}): Promise<string> {
  const att = await makeAttestation({ challenge: CHALLENGE, ...opts });
  try {
    await verifyAttestation({
      keyId: att.keyId,
      attestation: att.attestation,
      challenge: CHALLENGE,
      teamId: TEAM_ID,
      bundleId: CLIENT_ID,
      allowDevelop: false,
      nowMs: NOW,
      roots: [(await testCA()).rootDer],
      rootSha256: [(await testCA()).rootSha256],
      ...input,
    });
    return "ok";
  } catch (e) {
    return (e as { code?: string }).code ?? `threw ${String(e)}`;
  }
}

describe("App Attest attestation of a fresh key", () => {
  it("accepts a good attestation chained to the injected root", async () => {
    expect(await run()).toBe("ok");
  });

  it("rejects another bundle id (rpIdHash)", async () => {
    expect(await run({ bundleId: "com.evil.app" })).toBe("attest_invalid");
    expect(await run({ teamId: "OTHERTEAM1" })).toBe("attest_invalid");
  });

  it("rejects a chain to a different root", async () => {
    const otherCA = await makeCA("Evil");
    expect(await run({ ca: otherCA })).toBe("attest_invalid");
  });

  it("rejects when no root is configured", async () => {
    expect(await run({}, { roots: [] })).toBe("attest_invalid");
  });

  it("rejects a leaf that names the intermediate but was signed by a stranger key", async () => {
    expect(await run({ leafSignedByStranger: true })).toBe("attest_invalid");
  });

  it("rejects a leaf whose issuer name is not the intermediate's subject, even if the intermediate signed it", async () => {
    expect(await run({ leafIssuerCN: "Someone Else CA" })).toBe("attest_invalid");
  });

  it("rejects an intermediate that names the root as issuer but signed itself", async () => {
    const ca = await makeCA({ intermediateSelfSigned: true });
    expect(await run({ ca }, { roots: [ca.rootDer], rootSha256: [ca.rootSha256] })).toBe("attest_invalid");
  });

  it("rejects an intermediate without basicConstraints cA=true", async () => {
    const ca = await makeCA({ intermediateNotCA: true });
    expect(await run({ ca }, { roots: [ca.rootDer], rootSha256: [ca.rootSha256] })).toBe("attest_invalid");
  });

  it("rejects an expired intermediate, and an expired root", async () => {
    const past = new Date(NOW - 1000);
    const i = await makeCA({ intermediateNotAfter: past });
    expect(await run({ ca: i }, { roots: [i.rootDer], rootSha256: [i.rootSha256] })).toBe("attest_invalid");
    const r = await makeCA({ rootNotAfter: past });
    expect(await run({ ca: r }, { roots: [r.rootDer], rootSha256: [r.rootSha256] })).toBe("attest_invalid");
  });

  it("pins the root by SHA-256: a self-made root named 'Apple App Attestation Root CA' is not trusted", async () => {
    const impostor = await makeCA({ label: "Apple App Attestation" });
    // The chain is internally valid against the impostor root...
    expect(await run({ ca: impostor }, { roots: [impostor.rootDer], rootSha256: [impostor.rootSha256] })).toBe("ok");
    // ...but with the production pin it fails, even when the impostor DER is offered as a root.
    expect(await run({ ca: impostor }, { roots: [impostor.rootDer], rootSha256: [APPLE_APP_ATTEST_ROOT_SHA256] })).toBe("attest_invalid");
  });

  it("signature paths: P-384 intermediate signing the leaf with SHA-256 (believed Apple's, not verified) and with SHA-384", async () => {
    expect(await run({ leafHash: "SHA-256" })).toBe("ok");
    expect(await run({ leafHash: "SHA-384" })).toBe("ok");
  });

  it("rejects a leaf key that is not P-256", async () => {
    expect(await run({ leafCurve: "P-384" })).toBe("attest_invalid");
  });

  it("rejects x5c with other than exactly [leaf, intermediate]", async () => {
    expect(await run({ x5c: (l, i, r) => [l, i, r] })).toBe("attest_invalid");
    expect(await run({ x5c: (l) => [l] })).toBe("attest_invalid");
  });

  it("rejects authData without the AT (attested credential data) flag", async () => {
    expect(await run({ flags: 0x01 })).toBe("attest_invalid");
  });

  it("rejects a nonce made for another challenge", async () => {
    expect(await run({ nonceChallenge: "some-other-challenge" })).toBe("attest_invalid");
  });

  it("rejects a key id that is not SHA256 of the certified key", async () => {
    expect(await run({ wrongKeyId: true })).toBe("attest_invalid");
    expect(await run({ keyNotCertified: true })).toBe("attest_invalid");
  });

  it("rejects a credentialId that is not the key id", async () => {
    expect(await run({ wrongCredentialId: true })).toBe("attest_invalid");
  });

  it("rejects counter != 0", async () => {
    expect(await run({ counter: 1 })).toBe("attest_invalid");
  });

  it("appattestdevelop: rejected in prod, accepted when allowDevelop", async () => {
    expect(await run({ aaguid: "appattestdevelop" })).toBe("attest_invalid");
    expect(await run({ aaguid: "appattestdevelop" }, { allowDevelop: true })).toBe("ok");
  });

  it("rejects an expired leaf certificate", async () => {
    expect(await run({ leafNotAfter: new Date(NOW - 1000) })).toBe("attest_invalid");
  });

  it("rejects the wrong fmt and garbage input", async () => {
    expect(await run({ fmt: "packed" })).toBe("attest_invalid");
    expect(await run({}, { attestation: "not-base64!!" })).toBe("attest_invalid");
    expect(await run({}, { attestation: btoa("¡ÿÿ") })).toBe("attest_invalid");
    expect(await run({}, { keyId: "" })).toBe("attest_invalid");
  });

  it("the embedded Apple App Attestation Root CA parses, self-verifies, and matches the pinned SHA-256", async () => {
    const der = pemToDer(APPLE_APP_ATTEST_ROOT_PEM);
    expect(hex(await sha256(der))).toBe(APPLE_APP_ATTEST_ROOT_SHA256);
    const root = parseCertificate(der);
    expect(root.subjectCommonName).toBe("Apple App Attestation Root CA");
    expect(await verifySignedBy(root, root)).toBe(true);
  });
});
