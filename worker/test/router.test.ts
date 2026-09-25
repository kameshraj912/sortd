import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { verifyChallenge } from "../src/challenge";
import { handle } from "../src/index";
import {
  BASE,
  CHALLENGE_KEY,
  CLIENT_ID,
  DEV_BYPASS_TOKEN,
  DISTINCT_ID,
  NOW,
  POSTHOG_API_KEY,
  attestedRequest,
  denyAll,
  fakeFetch,
  fakeLimiter,
  json,
  makeDeps,
  makeEnv,
  post,
} from "./helpers";
import type { Env } from "../src/types";

const DELETE_BODY = { distinct_id: DISTINCT_ID };

function okFetch() {
  return fakeFetch({
    "/bulk_delete/": json({}, 202),
    "/auth/token": json({ refresh_token: "r.SECRET-refresh" }),
    "/auth/revoke": new Response(null, { status: 200 }),
  });
}

async function run(req: Request, envOver: Partial<Env> = {}, f = okFetch()) {
  const res = await handle(req, await makeEnv(envOver), await makeDeps(f.fn));
  const text = await res.text();
  return { res, text, f, body: text ? JSON.parse(text) : undefined };
}

describe("routing, methods, CORS", () => {
  it("GET and OPTIONS -> 405 method_not_allowed", async () => {
    for (const method of ["GET", "OPTIONS", "PUT", "DELETE"]) {
      const { res, body } = await run(new Request(`${BASE}/v1/posthog/delete-person`, { method }));
      expect(res.status, method).toBe(405);
      expect(body).toEqual({ error: "method_not_allowed" });
    }
  });

  it("unknown path -> 404 not_found", async () => {
    for (const path of ["/", "/v1", "/v1/apple", "/v2/challenge", "/v1/challenge/"]) {
      const { res, body } = await run(post(path, "{}"));
      expect(res.status, path).toBe(404);
      expect(body).toEqual({ error: "not_found" });
    }
  });

  it("any request with an Origin header -> 403 origin_forbidden, no upstream call", async () => {
    const req = await attestedRequest("posthog/delete-person", DELETE_BODY);
    const withOrigin = new Request(req, { headers: new Headers([...req.headers, ["origin", "https://sortd.page"]]) });
    const { res, body, f } = await run(withOrigin);
    expect(res.status).toBe(403);
    expect(body).toEqual({ error: "origin_forbidden" });
    expect(f.calls).toHaveLength(0);
  });

  it("no response carries Access-Control-* headers; errors are JSON and not cached", async () => {
    const reqs = [
      new Request(`${BASE}/v1/challenge`, { method: "OPTIONS", headers: { origin: "https://evil.example" } }),
      post("/v1/challenge", JSON.stringify({ route: "apple/revoke", body_sha256: "0".repeat(64) })),
      post("/nope", "{}"),
      await attestedRequest("posthog/delete-person", DELETE_BODY),
    ];
    for (const req of reqs) {
      const { res } = await run(req);
      for (const [k] of res.headers) expect(k.startsWith("access-control-")).toBe(false);
      if (res.status >= 400) expect(res.headers.get("content-type")).toBe("application/json");
      expect(res.headers.get("cache-control")).toBe("no-store");
    }
  });

  it("ENV that is neither prod nor dev -> 503 misconfigured", async () => {
    const { res, body } = await run(await attestedRequest("posthog/delete-person", DELETE_BODY), { ENV: undefined });
    expect(res.status).toBe(503);
    expect(body).toEqual({ error: "misconfigured" });
  });
});

describe("POST /v1/challenge", () => {
  it("returns a challenge bound to route and body hash", async () => {
    const bodySha = "ab".repeat(32);
    const { res, body } = await run(post("/v1/challenge", JSON.stringify({ route: "posthog/delete-person", body_sha256: bodySha })));
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/json");
    expect(Object.keys(body)).toEqual(["challenge"]);
    expect(typeof body.challenge).toBe("string");
    // It verifies for that route only (verifyChallenge checks the body hash itself, so use the matching bytes).
    await expect(verifyChallenge(CHALLENGE_KEY, body.challenge, "apple/revoke", new Uint8Array(), NOW)).rejects.toMatchObject({ code: "attest_invalid" });
  });

  it("bad input -> 400 bad_request", async () => {
    for (const b of [
      "not json",
      JSON.stringify({ route: "apple/revoke" }),
      JSON.stringify({ route: "challenge", body_sha256: "ab".repeat(32) }),
      JSON.stringify({ route: "apple/revoke", body_sha256: "AB".repeat(32) }),
      JSON.stringify({ route: "apple/revoke", body_sha256: "ab".repeat(31) }),
      JSON.stringify({ route: "apple/revoke", body_sha256: "ab".repeat(32), x: 1 }),
    ]) {
      const { res, body } = await run(post("/v1/challenge", b));
      expect(res.status, b).toBe(400);
      expect(body).toEqual({ error: "bad_request" });
    }
  });

  it("missing CHALLENGE_KEY -> 503 misconfigured", async () => {
    const { res } = await run(post("/v1/challenge", JSON.stringify({ route: "apple/revoke", body_sha256: "ab".repeat(32) })), { CHALLENGE_KEY: undefined });
    expect(res.status).toBe(503);
  });
});

describe("size caps", () => {
  it("a 5 KB body -> 413 too_large (with or without Content-Length)", async () => {
    const big = JSON.stringify({ distinct_id: "a".repeat(5 * 1024) });
    const { res, body, f } = await run(post("/v1/posthog/delete-person", big));
    expect(res.status).toBe(413);
    expect(body).toEqual({ error: "too_large" });
    expect(f.calls).toHaveLength(0);

    const withLen = post("/v1/challenge", big, { "content-length": String(big.length) });
    expect((await run(withLen)).res.status).toBe(413);
  });

  it("attestation headers over 16 KB -> 413", async () => {
    const req = await attestedRequest("posthog/delete-person", DELETE_BODY);
    const h = new Headers(req.headers);
    h.set("x-attest-object", "A".repeat(17 * 1024));
    const { res, body } = await run(new Request(req, { headers: h }));
    expect(res.status).toBe(413);
    expect(body).toEqual({ error: "too_large" });
  });
});

describe("rate limits", () => {
  it("IP limiter says no -> 429 rate_limited with Retry-After; attestation never parsed, upstream never called", async () => {
    const req = post("/v1/posthog/delete-person", JSON.stringify(DELETE_BODY), {
      "x-attest-key-id": "garbage",
      "x-attest-object": "garbage",
      "x-attest-challenge": "garbage",
    });
    const { res, body, f } = await run(req, { IP_LIMIT: denyAll });
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe("60");
    expect(body).toEqual({ error: "rate_limited" });
    expect(f.calls).toHaveLength(0);
  });

  it("IP limiter is keyed by cf-connecting-ip and also guards /v1/challenge", async () => {
    const ip = fakeLimiter(1);
    const env = await makeEnv({ IP_LIMIT: ip });
    const deps = await makeDeps(okFetch().fn);
    const mk = () => post("/v1/challenge", JSON.stringify({ route: "apple/revoke", body_sha256: "ab".repeat(32) }));
    expect((await handle(mk(), env, deps)).status).toBe(200);
    expect((await handle(mk(), env, deps)).status).toBe(429);
    expect(ip.keys).toEqual(["ip:203.0.113.7", "ip:203.0.113.7"]);
  });

  it("limiter binding missing in prod -> 503 misconfigured (fails closed)", async () => {
    for (const over of [{ IP_LIMIT: undefined }, { ID_LIMIT: undefined }]) {
      const { res, body, f } = await run(await attestedRequest("posthog/delete-person", DELETE_BODY), over);
      expect(res.status).toBe(503);
      expect(body).toEqual({ error: "misconfigured" });
      expect(f.calls).toHaveLength(0);
    }
  });
});

describe("App Attest on the action routes", () => {
  it("missing attest headers -> 401 attest_missing, and no upstream fetch at all", async () => {
    for (const route of ["posthog/delete-person", "apple/revoke"] as const) {
      const body = route === "apple/revoke" ? { client_id: CLIENT_ID, authorization_code: "c.x" } : DELETE_BODY;
      const { res, body: out, f } = await run(post(`/v1/${route}`, JSON.stringify(body)));
      expect(res.status).toBe(401);
      expect(out).toEqual({ error: "attest_missing" });
      expect(f.calls).toHaveLength(0);
    }
  });

  it("attestation for another bundle id -> 401 attest_invalid, Apple never called", async () => {
    const req = await attestedRequest("apple/revoke", { client_id: CLIENT_ID, authorization_code: "c.x" }, { bundleId: "com.evil.app" });
    const { res, body, f } = await run(req);
    expect(res.status).toBe(401);
    expect(body).toEqual({ error: "attest_invalid" });
    expect(f.calls).toHaveLength(0);
  });

  it("challenge 121 s old -> 401 challenge_expired", async () => {
    const req = await attestedRequest("posthog/delete-person", DELETE_BODY, { challengeAtMs: NOW - 121_000 });
    const { res, body, f } = await run(req);
    expect(res.status).toBe(401);
    expect(body).toEqual({ error: "challenge_expired" });
    expect(f.calls).toHaveLength(0);
  });

  it("challenge made for the other route, or for a different body -> 401", async () => {
    const r1 = await attestedRequest("posthog/delete-person", DELETE_BODY, { challengeRoute: "apple/revoke" });
    const r2 = await attestedRequest("posthog/delete-person", DELETE_BODY, { challengeBody: JSON.stringify({ distinct_id: "b".repeat(64) }) });
    for (const req of [r1, r2]) {
      const { res, body, f } = await run(req);
      expect(res.status).toBe(401);
      expect(body).toEqual({ error: "attest_invalid" });
      expect(f.calls).toHaveLength(0);
    }
  });

  it("appattestdevelop: 401 when ENV=prod, accepted when ENV=dev", async () => {
    const mk = () => attestedRequest("posthog/delete-person", DELETE_BODY, { aaguid: "appattestdevelop" });
    expect((await run(await mk())).res.status).toBe(401);
    expect((await run(await mk(), { ENV: "dev" })).res.status).toBe(204);
  });

  it("X-Sortd-Debug with the right token: ignored in prod (401, no upstream); accepted in dev", async () => {
    const mk = () => post("/v1/posthog/delete-person", JSON.stringify(DELETE_BODY), { "x-sortd-debug": DEV_BYPASS_TOKEN });
    const prod = await run(mk(), { DEV_BYPASS_TOKEN });
    expect(prod.res.status).toBe(401);
    expect(prod.f.calls).toHaveLength(0);

    const dev = await run(mk(), { ENV: "dev", DEV_BYPASS_TOKEN });
    expect(dev.res.status).toBe(204);
    expect(dev.f.calls).toHaveLength(1);
  });

  it("X-Sortd-Debug in dev with a wrong token, or with no token configured -> 401", async () => {
    const mk = (t: string) => post("/v1/posthog/delete-person", JSON.stringify(DELETE_BODY), { "x-sortd-debug": t });
    expect((await run(mk("wrong"), { ENV: "dev", DEV_BYPASS_TOKEN })).res.status).toBe(401);
    expect((await run(mk(""), { ENV: "dev", DEV_BYPASS_TOKEN: undefined })).res.status).toBe(401);
    expect((await run(mk("undefined"), { ENV: "dev", DEV_BYPASS_TOKEN: undefined })).res.status).toBe(401);
  });
});

describe("logging", () => {
  const lines: string[] = [];
  beforeEach(() => {
    lines.length = 0;
    for (const level of ["log", "info", "warn", "error", "debug"] as const) {
      vi.spyOn(console, level).mockImplementation((...args: unknown[]) => {
        lines.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a) ?? String(a))).join(" "));
      });
    }
  });
  afterEach(() => vi.restoreAllMocks());

  it("never logs codes, tokens, ids, keys or attestation bytes; logs route, status and code", async () => {
    const code = "c.authorization-code-SECRET";
    const appleReq = await attestedRequest("apple/revoke", { client_id: CLIENT_ID, authorization_code: code });
    const attObj = appleReq.headers.get("x-attest-object")!;
    const keyId = appleReq.headers.get("x-attest-key-id")!;
    const f = fakeFetch({
      "/auth/token": json({ refresh_token: "r.SECRET-refresh" }),
      "/auth/revoke": json({ error: "invalid_client" }, 400),
      "/bulk_delete/": json({ detail: `unknown ${DISTINCT_ID}` }, 500),
    });
    await run(appleReq, {}, f);
    await run(await attestedRequest("posthog/delete-person", DELETE_BODY), {}, f);
    await run(post("/v1/posthog/delete-person", JSON.stringify(DELETE_BODY)), {}, f);

    const all = lines.join("\n");
    expect(lines.length).toBeGreaterThan(0);
    for (const secret of [code, "SECRET", DISTINCT_ID, POSTHOG_API_KEY, attObj.slice(0, 40), keyId, CHALLENGE_KEY]) {
      expect(all).not.toContain(secret);
    }
    expect(all).toContain("apple_invalid_client");
    expect(all).toContain("/v1/apple/revoke");
  });
});
