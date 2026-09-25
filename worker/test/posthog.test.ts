import { describe, expect, it } from "vitest";
import { handle } from "../src/handler";
import { DISTINCT_ID, POSTHOG_API_KEY, attestedRequest, fakeFetch, fakeLimiter, json, makeDeps, makeEnv } from "./helpers";

const BULK = "https://eu.posthog.test/api/environments/12345/persons/bulk_delete/";

async function send(f: ReturnType<typeof fakeFetch>, body: unknown = { distinct_id: DISTINCT_ID }, env?: Awaited<ReturnType<typeof makeEnv>>) {
  const res = await handle(await attestedRequest("posthog/delete-person", body), env ?? (await makeEnv()), await makeDeps(f.fn));
  return { res, text: await res.text() };
}

describe("POST /v1/posthog/delete-person", () => {
  it("PostHog 202 -> 204; one bulk_delete call with distinct_ids:[id], delete_events:true and the bearer key", async () => {
    const f = fakeFetch({ "/bulk_delete/": json({}, 202) });
    const { res, text } = await send(f);
    expect(res.status).toBe(204);
    expect(text).toBe("");
    expect(f.calls).toHaveLength(1);
    const c = f.calls[0]!;
    expect(c.url).toBe(BULK);
    expect(c.method).toBe("POST");
    expect(c.headers.get("authorization")).toBe(`Bearer ${POSTHOG_API_KEY}`);
    expect(c.headers.get("content-type")).toBe("application/json");
    expect(JSON.parse(c.body)).toEqual({ distinct_ids: [DISTINCT_ID], delete_events: true });
  });

  it("idempotent: same id twice (202, then 202 with nothing matched) -> 204 both times", async () => {
    const f = fakeFetch({ "/bulk_delete/": [json({}, 202), json({}, 202)] });
    const env = await makeEnv();
    expect((await send(f, undefined, env)).res.status).toBe(204);
    expect((await send(f, undefined, env)).res.status).toBe(204);
  });

  it("idempotent: a validation_error about distinct_ids that lists our id -> 204", async () => {
    const f = fakeFetch({
      "/bulk_delete/": json({ type: "validation_error", code: "invalid_input", attr: "distinct_ids", detail: "Unknown distinct_ids", distinct_ids: [DISTINCT_ID] }, 400),
    });
    expect((await send(f)).res.status).toBe(204);
  });

  it("a 400 that merely echoes our id in another shape -> 502 posthog_rejected", async () => {
    for (const reply of [
      new Response(`bad request for ${DISTINCT_ID}`, { status: 400 }),
      json({ detail: `Unknown distinct_ids: ${DISTINCT_ID}` }, 400),
      json({ type: "validation_error", detail: `Unknown distinct_ids: ${DISTINCT_ID}` }, 400),
      json({ type: "validation_error", attr: "delete_events", ids: [DISTINCT_ID] }, 400),
      json({ type: "validation_error", attr: "distinct_ids", ids: [`x${DISTINCT_ID}`] }, 400),
    ]) {
      const f = fakeFetch({ "/bulk_delete/": reply });
      const { res, text } = await send(f);
      expect(res.status).toBe(502);
      expect(JSON.parse(text)).toEqual({ error: "posthog_rejected" });
    }
  });

  it("a 400 that does not name our id -> 502 posthog_rejected", async () => {
    const f = fakeFetch({ "/bulk_delete/": json({ detail: "something else" }, 400) });
    const { res, text } = await send(f);
    expect(res.status).toBe(502);
    expect(JSON.parse(text)).toEqual({ error: "posthog_rejected" });
  });

  it("PostHog 401 or 403 -> 502 posthog_auth", async () => {
    for (const status of [401, 403]) {
      const f = fakeFetch({ "/bulk_delete/": json({ detail: "nope" }, status) });
      const { res, text } = await send(f);
      expect(res.status).toBe(502);
      expect(JSON.parse(text)).toEqual({ error: "posthog_auth" });
    }
  });

  it("PostHog 404 (wrong project or path) -> 503 misconfigured, not a silent success", async () => {
    const f = fakeFetch({ "/bulk_delete/": json({ detail: "Not found." }, 404) });
    const { res, text } = await send(f);
    expect(res.status).toBe(503);
    expect(JSON.parse(text)).toEqual({ error: "misconfigured" });
  });

  it("PostHog 5xx, 429 or a network error -> 503 posthog_unavailable", async () => {
    for (const reply of [new Response("x", { status: 500 }), new Response("x", { status: 429 }), new TypeError("network")]) {
      const f = fakeFetch({ "/bulk_delete/": reply as Response });
      const { res, text } = await send(f);
      expect(res.status).toBe(503);
      expect(JSON.parse(text)).toEqual({ error: "posthog_unavailable" });
    }
  });

  it("distinct_id that is not 64 lowercase hex -> 400 bad_request, no upstream call", async () => {
    for (const id of [DISTINCT_ID.toUpperCase(), DISTINCT_ID.slice(1), `${DISTINCT_ID}0`, "user@example.com", 7, null]) {
      const f = fakeFetch({ "/bulk_delete/": json({}, 202) });
      const { res, text } = await send(f, { distinct_id: id });
      expect(res.status, String(id)).toBe(400);
      expect(JSON.parse(text)).toEqual({ error: "bad_request" });
      expect(f.calls).toHaveLength(0);
    }
  });

  it("fourth delete for the same id within the window -> 429 with Retry-After", async () => {
    const f = fakeFetch({ "/bulk_delete/": json({}, 202) });
    const env = await makeEnv({ ID_LIMIT: fakeLimiter(3), IP_LIMIT: fakeLimiter(100) });
    for (let i = 0; i < 3; i++) expect((await send(f, undefined, env)).res.status).toBe(204);
    const { res, text } = await send(f, undefined, env);
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe("60");
    expect(JSON.parse(text)).toEqual({ error: "rate_limited" });
    expect(f.calls).toHaveLength(3);
  });
});
