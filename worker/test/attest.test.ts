import { describe, expect, it } from "vitest";
import {
  APPLE_APP_ATTEST_ROOT_PEM,
  parseCertificate,
  pemToDer,
  verifyAttestation,
  verifySignedBy,
  type AttestInput,
} from "../src/attest";
import { CLIENT_ID, NOW, TEAM_ID, makeAttestation, makeCA, testCA, type AttestOptions } from "./helpers";

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

  it("the embedded Apple App Attestation Root CA parses and its self-signature verifies", async () => {
    const root = parseCertificate(pemToDer(APPLE_APP_ATTEST_ROOT_PEM));
    expect(root.subjectCommonName).toBe("Apple App Attestation Root CA");
    expect(await verifySignedBy(root, root)).toBe(true);
  });
});
