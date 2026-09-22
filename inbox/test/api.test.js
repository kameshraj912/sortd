import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index.js";
import { MAILBOX_TTL_SECONDS } from "../src/api.js";
import { ADDRESS_RE, sha256hex } from "../src/util.js";
import { limiter, newMailbox, phoneKeys } from "./helpers.js";

const BASE = "https://inbox.sortd.page";
const call = (path, init = {}, e = env) => worker.fetch(new Request(BASE + path, init), e);
const register = (body, e = env, headers = {}) =>
  call("/api/inbox/register", { method: "POST", body: JSON.stringify(body), headers: { "cf-connecting-ip": "203.0.113.9", ...headers } }, e);

describe("POST /api/inbox/register", () => {
  it("gives a random address on in.sortd.page and a token, and stores only hashes", async () => {
    const box = await newMailbox();
    expect(box.ok).toBe(true);
    expect(box.address).toMatch(/@in\.sortd\.page$/);
    expect(ADDRESS_RE.test(box.local)).toBe(true);
    expect(box.token).toMatch(/^[A-Za-z0-9_-]{43}$/);

    const { keys } = await env.INBOX.list();
    const names = keys.map((k) => k.name).join(" ");
    expect(names).not.toContain(box.local);
    const key = `a:${await sha256hex(box.local)}`;
    const stored = await env.INBOX.get(key, "json");
    expect(stored.th).toBe(await sha256hex(box.token));
    expect(JSON.stringify(stored)).not.toContain(box.token);
    expect(stored.pk).toBe(box.keys.publicKeyB64u);
  });

  it("two registrations never share an address", async () => {
    const a = await newMailbox();
    const b = await newMailbox();
    expect(a.address).not.toBe(b.address);
    expect(a.token).not.toBe(b.token);
  });

  it("expires mailboxes nobody checks (180 days)", async () => {
    const box = await newMailbox();
    const { keys } = await env.INBOX.list({ prefix: `a:${await sha256hex(box.local)}` });
    const expected = Date.now() / 1000 + MAILBOX_TTL_SECONDS;
    expect(Math.abs(keys[0].expiration - expected)).toBeLessThan(120);
  });

  it("refuses bad keys, other suites and junk", async () => {
    const keys = await phoneKeys();
    expect((await register({ publicKey: keys.publicKeyB64u, suite: "X25519_SHA256_ChachaPoly" })).status).toBe(400);
    expect((await register({ publicKey: "AAAA", suite: "P256_SHA256_AES_GCM_256" })).status).toBe(400);
    expect((await register({ suite: "P256_SHA256_AES_GCM_256" })).status).toBe(400);
    const junk = await call("/api/inbox/register", { method: "POST", body: "not json" });
    expect(junk.status).toBe(400);
    expect((await call("/api/inbox/register")).status).toBe(405);
  });

  it("is rate limited per IP", async () => {
    const keys = await phoneKeys();
    const e = { ...env, REGISTER_LIMIT: limiter(2) };
    const body = { publicKey: keys.publicKeyB64u, suite: "P256_SHA256_AES_GCM_256" };
    expect((await register(body, e)).status).toBe(201);
    expect((await register(body, e)).status).toBe(201);
    expect((await register(body, e)).status).toBe(429);
  });
});

describe("the authenticated API", () => {
  it("needs the right token for the right mailbox", async () => {
    const a = await newMailbox();
    const b = await newMailbox();
    expect((await call("/api/inbox/messages")).status).toBe(401);
    expect((await call("/api/inbox/messages", { headers: { authorization: `Bearer ${a.local}.${b.token}` } })).status).toBe(401);
    expect((await call("/api/inbox/messages", { headers: { authorization: `Bearer ${a.local}` } })).status).toBe(401);
    expect((await call("/api/inbox/messages", { headers: a.auth })).status).toBe(200);
  });

  it("lists nothing for a new mailbox", async () => {
    const a = await newMailbox();
    const body = await (await call("/api/inbox/messages", { headers: a.auth })).json();
    expect(body).toEqual({ ok: true, messages: [], more: false });
  });

  it("turning off deletes the mailbox, its messages, and the token stops working", async () => {
    const a = await newMailbox();
    const h = await sha256hex(a.local);
    await env.INBOX.put(`m:${h}:000000000-AAAAAAAAAAAAAAAA`, JSON.stringify({ v: 1, enc: "x", ct: "y" }));
    expect((await call("/api/inbox", { method: "DELETE", headers: a.auth })).status).toBe(204);
    expect(await env.INBOX.get(`a:${h}`)).toBeNull();
    expect((await env.INBOX.list({ prefix: `m:${h}:` })).keys).toEqual([]);
    expect((await call("/api/inbox/messages", { headers: a.auth })).status).toBe(401);
  });

  it("rejects malformed message ids on delete", async () => {
    const a = await newMailbox();
    const res = await call("/api/inbox/messages/..%2F..%2Fa", { method: "DELETE", headers: a.auth });
    expect(res.status).toBe(400);
  });

  it("is rate limited per mailbox", async () => {
    const a = await newMailbox();
    const e = { ...env, API_LIMIT: limiter(1) };
    expect((await call("/api/inbox/messages", { headers: a.auth }, e)).status).toBe(200);
    expect((await call("/api/inbox/messages", { headers: a.auth }, e)).status).toBe(429);
  });
});

describe("setup page", () => {
  it("serves the page with a strict CSP and no address in it", async () => {
    const res = await call("/setup");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    const html = await res.text();
    expect(html).toContain("Import filters");
    expect(html).toContain("Redirect to");
    const js = await (await call("/setup.js")).text();
    expect(js).toContain("forwardTo");
    expect(js).toContain('new RegExp("^[abcdefghijkmnpqrstuvwxyz23456789]{24}@in\\\\.sortd\\\\.page$")');
  });

  it("unknown paths are 404, / goes to /setup", async () => {
    expect((await call("/nope")).status).toBe(404);
    const root = await call("/");
    expect(root.status).toBe(302);
    expect(root.headers.get("location")).toBe(`${BASE}/setup`);
  });
});
