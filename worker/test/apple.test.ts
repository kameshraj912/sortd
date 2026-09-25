import { describe, expect, it } from "vitest";
import { makeClientSecret } from "../src/apple";
import { handle } from "../src/handler";
import {
  CLIENT_ID,
  KEY_ID,
  NOW,
  TEAM_ID,
  appleKey,
  attestedRequest,
  b64urlDecode,
  fakeFetch,
  json,
  makeDeps,
  makeEnv,
} from "./helpers";

const TOKEN_URL = "https://appleid.apple.com/auth/token";
const REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const REFRESH = "r.refresh-token-SECRET-value";
const CODE = "c.authorization-code-SECRET";

function appleFetch(token: unknown = json({ access_token: "a.access-SECRET", refresh_token: REFRESH, id_token: "x.y.z" }), revoke: unknown = new Response(null, { status: 200 })) {
  return fakeFetch({ "/auth/token": token as Response, "/auth/revoke": revoke as Response });
}

async function send(body: unknown, f: ReturnType<typeof fakeFetch>, envOver = {}) {
  const res = await handle(await attestedRequest("apple/revoke", body), await makeEnv(envOver), await makeDeps(f.fn));
  return { res, text: await res.text() };
}

describe("client_secret JWT", () => {
  it("is ES256 with kid, iss=team, sub=client, aud=appleid, exp-iat<=300, and verifies with the key", async () => {
    const key = await appleKey();
    const jwt = await makeClientSecret({ teamId: TEAM_ID, keyId: KEY_ID, clientId: CLIENT_ID, privateKeyPem: key.pem }, NOW);
    const [h, p, s] = jwt.split(".");
    const header = JSON.parse(new TextDecoder().decode(b64urlDecode(h!)));
    const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(p!)));
    expect(header).toEqual({ alg: "ES256", kid: KEY_ID });
    expect(claims.iss).toBe(TEAM_ID);
    expect(claims.sub).toBe(CLIENT_ID);
    expect(claims.aud).toBe("https://appleid.apple.com");
    expect(claims.iat).toBe(Math.floor(NOW / 1000));
    expect(claims.exp - claims.iat).toBeGreaterThan(0);
    expect(claims.exp - claims.iat).toBeLessThanOrEqual(300);
    const sig = b64urlDecode(s!);
    expect(sig.length).toBe(64); // JWS ES256 is raw r||s, not DER
    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key.publicKey,
      sig,
      new TextEncoder().encode(`${h}.${p}`),
    );
    expect(ok).toBe(true);
  });
});

describe("POST /v1/apple/revoke", () => {
  it("valid attest + code -> 204; /auth/token once, /auth/revoke once with the refresh token", async () => {
    const f = appleFetch();
    const { res, text } = await send({ client_id: CLIENT_ID, authorization_code: CODE }, f);
    expect(res.status).toBe(204);
    expect(text).toBe("");
    expect(f.to("/auth/token")).toHaveLength(1);
    expect(f.to("/auth/revoke")).toHaveLength(1);

    const tokenCall = f.to("/auth/token")[0]!;
    expect(tokenCall.url).toBe(TOKEN_URL);
    expect(tokenCall.method).toBe("POST");
    const tp = new URLSearchParams(tokenCall.body);
    expect(tp.get("grant_type")).toBe("authorization_code");
    expect(tp.get("code")).toBe(CODE);
    expect(tp.get("client_id")).toBe(CLIENT_ID);
    expect(tp.get("client_secret")?.split(".")).toHaveLength(3);

    const revokeCall = f.to("/auth/revoke")[0]!;
    expect(revokeCall.url).toBe(REVOKE_URL);
    const rp = new URLSearchParams(revokeCall.body);
    expect(rp.get("token")).toBe(REFRESH);
    expect(rp.get("token_type_hint")).toBe("refresh_token");
    expect(rp.get("client_id")).toBe(CLIENT_ID);
    expect(revokeCall.headers.get("content-type")).toBe("application/x-www-form-urlencoded");
  });

  it("valid attest + refresh_token -> 204; /auth/token never called", async () => {
    const f = appleFetch();
    const { res } = await send({ client_id: CLIENT_ID, refresh_token: REFRESH }, f);
    expect(res.status).toBe(204);
    expect(f.to("/auth/token")).toHaveLength(0);
    expect(f.to("/auth/revoke")).toHaveLength(1);
    expect(new URLSearchParams(f.to("/auth/revoke")[0]!.body).get("token")).toBe(REFRESH);
  });

  it("/auth/token 400 invalid_grant -> 502 apple_invalid_grant, revoke never called", async () => {
    const f = appleFetch(json({ error: "invalid_grant" }, 400));
    const { res, text } = await send({ client_id: CLIENT_ID, authorization_code: CODE }, f);
    expect(res.status).toBe(502);
    expect(JSON.parse(text)).toEqual({ error: "apple_invalid_grant" });
    expect(f.to("/auth/revoke")).toHaveLength(0);
  });

  it("/auth/revoke 400 invalid_client -> 502 apple_invalid_client", async () => {
    const f = appleFetch(undefined, json({ error: "invalid_client" }, 400));
    const { res, text } = await send({ client_id: CLIENT_ID, refresh_token: REFRESH }, f);
    expect(res.status).toBe(502);
    expect(JSON.parse(text)).toEqual({ error: "apple_invalid_client" });
  });

  it("Apple 4xx with no usable error -> 502 apple_rejected (Apple's text is never echoed)", async () => {
    const f = appleFetch(new Response("<html>Bad Request: SECRET-ish</html>", { status: 400 }));
    const { res, text } = await send({ client_id: CLIENT_ID, authorization_code: CODE }, f);
    expect(res.status).toBe(502);
    expect(JSON.parse(text)).toEqual({ error: "apple_rejected" });
  });

  it("Apple 500 or a network error/timeout -> 503 apple_unavailable", async () => {
    const f1 = appleFetch(new Response("oops", { status: 500 }));
    const r1 = await send({ client_id: CLIENT_ID, authorization_code: CODE }, f1);
    expect(r1.res.status).toBe(503);
    expect(JSON.parse(r1.text)).toEqual({ error: "apple_unavailable" });

    const f2 = fakeFetch({ "/auth/revoke": new DOMException("timed out", "TimeoutError") as unknown as Error });
    const r2 = await send({ client_id: CLIENT_ID, refresh_token: REFRESH }, f2);
    expect(r2.res.status).toBe(503);
    expect(JSON.parse(r2.text)).toEqual({ error: "apple_unavailable" });
  });

  it("client_id other than the configured one -> 400 wrong_client, no upstream call", async () => {
    const f = appleFetch();
    const { res, text } = await send({ client_id: "com.other.app", authorization_code: CODE }, f);
    expect(res.status).toBe(400);
    expect(JSON.parse(text)).toEqual({ error: "wrong_client" });
    expect(f.calls).toHaveLength(0);
  });

  it("both a code and a refresh token, or neither, or extra fields -> 400 bad_request", async () => {
    for (const body of [
      { client_id: CLIENT_ID, authorization_code: CODE, refresh_token: REFRESH },
      { client_id: CLIENT_ID },
      { client_id: CLIENT_ID, authorization_code: "" },
      { client_id: CLIENT_ID, authorization_code: 42 },
      { client_id: CLIENT_ID, authorization_code: CODE, extra: 1 },
      [1, 2],
    ]) {
      const f = appleFetch();
      const { res, text } = await send(body, f);
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(JSON.parse(text)).toEqual({ error: "bad_request" });
      expect(f.calls).toHaveLength(0);
    }
  });

  it("no response body ever contains an Apple token or code", async () => {
    for (const f of [appleFetch(), appleFetch(undefined, json({ error: "invalid_request" }, 400))]) {
      const { text } = await send({ client_id: CLIENT_ID, authorization_code: CODE }, f);
      expect(text).not.toContain("SECRET");
    }
  });

  it("missing Apple secrets -> 503 misconfigured, no upstream call", async () => {
    const f = appleFetch();
    const { res, text } = await send({ client_id: CLIENT_ID, authorization_code: CODE }, f, { APPLE_PRIVATE_KEY: undefined });
    expect(res.status).toBe(503);
    expect(JSON.parse(text)).toEqual({ error: "misconfigured" });
    expect(f.calls).toHaveLength(0);
  });
});
