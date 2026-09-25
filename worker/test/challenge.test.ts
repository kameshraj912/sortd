import { describe, expect, it } from "vitest";
import { CHALLENGE_TTL_MS, issueChallenge, verifyChallenge } from "../src/challenge";
import { CHALLENGE_KEY, NOW, hex, sha256 } from "./helpers";

const enc = new TextEncoder();
const body = enc.encode('{"distinct_id":"x"}');

async function codeOf(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "ok";
  } catch (e) {
    return (e as { code?: string }).code ?? `threw ${String(e)}`;
  }
}

describe("stateless challenge", () => {
  it("round-trips for the same route, body and key inside 120 s", async () => {
    const c = await issueChallenge(CHALLENGE_KEY, "posthog/delete-person", hex(await sha256(body)), NOW);
    expect(c).toMatch(/^[A-Za-z0-9_-]+$/); // base64url, safe in a header
    expect(await codeOf(verifyChallenge(CHALLENGE_KEY, c, "posthog/delete-person", body, NOW + CHALLENGE_TTL_MS))).toBe("ok");
  });

  it("is different every time (random part)", async () => {
    const h = hex(await sha256(body));
    const a = await issueChallenge(CHALLENGE_KEY, "apple/revoke", h, NOW);
    const b = await issueChallenge(CHALLENGE_KEY, "apple/revoke", h, NOW);
    expect(a).not.toBe(b);
  });

  it("121 s old -> challenge_expired", async () => {
    const c = await issueChallenge(CHALLENGE_KEY, "posthog/delete-person", hex(await sha256(body)), NOW);
    expect(await codeOf(verifyChallenge(CHALLENGE_KEY, c, "posthog/delete-person", body, NOW + 121_000))).toBe("challenge_expired");
  });

  it("from the future -> attest_invalid", async () => {
    const c = await issueChallenge(CHALLENGE_KEY, "posthog/delete-person", hex(await sha256(body)), NOW + 60_000);
    expect(await codeOf(verifyChallenge(CHALLENGE_KEY, c, "posthog/delete-person", body, NOW))).toBe("attest_invalid");
  });

  it("other route -> attest_invalid", async () => {
    const c = await issueChallenge(CHALLENGE_KEY, "apple/revoke", hex(await sha256(body)), NOW);
    expect(await codeOf(verifyChallenge(CHALLENGE_KEY, c, "posthog/delete-person", body, NOW))).toBe("attest_invalid");
  });

  it("other body -> attest_invalid", async () => {
    const c = await issueChallenge(CHALLENGE_KEY, "posthog/delete-person", hex(await sha256(body)), NOW);
    expect(await codeOf(verifyChallenge(CHALLENGE_KEY, c, "posthog/delete-person", enc.encode("{}"), NOW))).toBe("attest_invalid");
  });

  it("other key, tampered bytes or garbage -> attest_invalid", async () => {
    const c = await issueChallenge(CHALLENGE_KEY, "posthog/delete-person", hex(await sha256(body)), NOW);
    expect(await codeOf(verifyChallenge("another-key-another-key-another-key!!", c, "posthog/delete-person", body, NOW))).toBe("attest_invalid");
    const flipped = (c[10] === "A" ? "B" : "A");
    const tampered = c.slice(0, 10) + flipped + c.slice(11);
    expect(await codeOf(verifyChallenge(CHALLENGE_KEY, tampered, "posthog/delete-person", body, NOW))).toBe("attest_invalid");
    expect(await codeOf(verifyChallenge(CHALLENGE_KEY, "!!!not base64!!!", "posthog/delete-person", body, NOW))).toBe("attest_invalid");
    expect(await codeOf(verifyChallenge(CHALLENGE_KEY, "", "posthog/delete-person", body, NOW))).toBe("attest_invalid");
  });
});
