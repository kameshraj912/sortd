// Request handling for the sortd-account Worker (entry point: index.ts). Spec: docs/specs/2026-09-25-account-worker.md.
//
//   POST /v1/challenge               -> 200 {"challenge":"..."}
//   POST /v1/apple/revoke            -> 204   (App Attest required)
//   POST /v1/posthog/delete-person   -> 204   (App Attest required)
//   anything else                    -> {"error":"<code>"} with the status from errors.ts
//
// JSON only. Bodies over 4 KB -> 413. No CORS: any Origin header -> 403, OPTIONS -> 405.
// Stores nothing. Logs only the route, the status and the error code: never bodies,
// headers, codes, tokens, ids or attestation bytes.

import { verifyAttestation } from "./attest";
import { revokeApple } from "./apple";
import { equalBytes, utf8 } from "./bytes";
import { ROUTES, issueChallenge, verifyChallenge, type Route } from "./challenge";
import { WorkerError } from "./errors";
import { deletePerson } from "./posthog";
import { RETRY_AFTER_SECONDS, checkLimit } from "./ratelimit";
import type { Deps, Env } from "./types";

export const MAX_BODY_BYTES = 4 * 1024;
export const MAX_ATTEST_HEADER_BYTES = 16 * 1024;
const HEX64 = /^[0-9a-f]{64}$/;
const MAX_TOKEN_CHARS = 2048;

type Path = "challenge" | Route;
const PATHS: Record<string, Path> = {
  "/v1/challenge": "challenge",
  "/v1/apple/revoke": "apple/revoke",
  "/v1/posthog/delete-person": "posthog/delete-person",
};

const BASE_HEADERS = { "cache-control": "no-store" };

function jsonResponse(obj: unknown, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...BASE_HEADERS, "content-type": "application/json", ...extra },
  });
}

function errorResponse(e: WorkerError): Response {
  const extra: Record<string, string> = {};
  if (e.status === 429) extra["retry-after"] = String(RETRY_AFTER_SECONDS);
  if (e.status === 405) extra["allow"] = "POST";
  return jsonResponse({ error: e.code }, e.status, extra);
}

function log(path: string, status: number, error?: string): void {
  console.log(JSON.stringify(error ? { route: path, status, error } : { route: path, status }));
}

/** Reads at most `max` bytes; more than that is a 413, whatever Content-Length said. */
async function readCapped(request: Request, max: number): Promise<Uint8Array> {
  const declared = request.headers.get("content-length");
  if (declared !== null && !(Number(declared) <= max)) throw new WorkerError("too_large");
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) {
      await reader.cancel().catch(() => {});
      throw new WorkerError("too_large");
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let o = 0;
  for (const c of chunks) {
    out.set(c, o);
    o += c.length;
  }
  return out;
}

function parseObject(body: Uint8Array, allowed: string[]): Record<string, unknown> {
  let v: unknown;
  try {
    v = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(body));
  } catch {
    throw new WorkerError("bad_request");
  }
  if (typeof v !== "object" || v === null || Array.isArray(v)) throw new WorkerError("bad_request");
  const obj = v as Record<string, unknown>;
  if (Object.keys(obj).some((k) => !allowed.includes(k))) throw new WorkerError("bad_request");
  return obj;
}

const nonEmpty = (v: unknown, max: number): v is string => typeof v === "string" && v.length > 0 && v.length <= max;

function need(...values: (string | undefined)[]): void {
  if (values.some((v) => !v)) throw new WorkerError("misconfigured");
}

/** Constant-time string compare (via bytes). */
function sameSecret(a: string, b: string): boolean {
  return equalBytes(utf8(a), utf8(b));
}

async function checkAttest(request: Request, env: Env, deps: Deps, route: Route, body: Uint8Array): Promise<void> {
  const isDev = env.ENV === "dev";
  // Dev bypass: only in the dev Worker, only with a configured token of real length.
  // The prod Worker ignores this header completely.
  const debug = request.headers.get("x-sortd-debug");
  if (isDev && debug && env.DEV_BYPASS_TOKEN && env.DEV_BYPASS_TOKEN.length >= 16 && sameSecret(debug, env.DEV_BYPASS_TOKEN)) {
    return;
  }
  const keyId = request.headers.get("x-attest-key-id");
  const attestation = request.headers.get("x-attest-object");
  const challenge = request.headers.get("x-attest-challenge");
  if (!keyId || !attestation || !challenge) throw new WorkerError("attest_missing");

  const now = deps.now();
  await verifyChallenge(env.CHALLENGE_KEY!, challenge, route, body, now);
  await verifyAttestation({
    keyId,
    attestation,
    challenge,
    teamId: env.APPLE_TEAM_ID!,
    bundleId: env.APPLE_CLIENT_ID!,
    allowDevelop: isDev,
    nowMs: now,
    roots: deps.attestRoots,
  });
}

async function route(request: Request, env: Env, deps: Deps, path: Path): Promise<Response> {
  if (request.method !== "POST") throw new WorkerError("method_not_allowed");
  if (request.headers.has("origin")) throw new WorkerError("origin_forbidden");
  if (env.ENV !== "prod" && env.ENV !== "dev") throw new WorkerError("misconfigured");
  if (!env.IP_LIMIT || !env.ID_LIMIT) throw new WorkerError("misconfigured");

  // Flood guard first, before any parsing or crypto.
  await checkLimit(env.IP_LIMIT, `ip:${request.headers.get("cf-connecting-ip") ?? "unknown"}`);

  const attestHeaderBytes = ["x-attest-key-id", "x-attest-object", "x-attest-challenge"].reduce(
    (n, h) => n + (request.headers.get(h)?.length ?? 0),
    0,
  );
  if (attestHeaderBytes > MAX_ATTEST_HEADER_BYTES) throw new WorkerError("too_large");
  const body = await readCapped(request, MAX_BODY_BYTES);

  if (path === "challenge") {
    need(env.CHALLENGE_KEY);
    const obj = parseObject(body, ["route", "body_sha256"]);
    const r = obj.route;
    const sha = obj.body_sha256;
    if (typeof r !== "string" || !(ROUTES as readonly string[]).includes(r)) throw new WorkerError("bad_request");
    if (typeof sha !== "string" || !HEX64.test(sha)) throw new WorkerError("bad_request");
    const challenge = await issueChallenge(env.CHALLENGE_KEY!, r as Route, sha, deps.now());
    return jsonResponse({ challenge }, 200);
  }

  need(env.CHALLENGE_KEY, env.APPLE_TEAM_ID, env.APPLE_CLIENT_ID);
  if (path === "apple/revoke") need(env.APPLE_KEY_ID, env.APPLE_PRIVATE_KEY);
  else need(env.POSTHOG_API_HOST, env.POSTHOG_PROJECT_ID, env.POSTHOG_API_KEY);

  await checkAttest(request, env, deps, path, body);

  if (path === "posthog/delete-person") {
    const obj = parseObject(body, ["distinct_id"]);
    const id = obj.distinct_id;
    if (typeof id !== "string" || !HEX64.test(id)) throw new WorkerError("bad_request");
    await checkLimit(env.ID_LIMIT, `id:${id}`);
    await deletePerson(id, { host: env.POSTHOG_API_HOST!, projectId: env.POSTHOG_PROJECT_ID!, apiKey: env.POSTHOG_API_KEY! }, deps.fetch);
    return new Response(null, { status: 204, headers: BASE_HEADERS });
  }

  // apple/revoke
  const obj = parseObject(body, ["client_id", "authorization_code", "refresh_token"]);
  if (!nonEmpty(obj.client_id, 256)) throw new WorkerError("bad_request");
  const hasCode = "authorization_code" in obj;
  const hasRefresh = "refresh_token" in obj;
  if (hasCode === hasRefresh) throw new WorkerError("bad_request"); // exactly one
  const token = hasCode ? obj.authorization_code : obj.refresh_token;
  if (!nonEmpty(token, MAX_TOKEN_CHARS)) throw new WorkerError("bad_request");
  if (!sameSecret(obj.client_id, env.APPLE_CLIENT_ID!)) throw new WorkerError("wrong_client");
  await revokeApple(
    hasCode ? { authorization_code: token } : { refresh_token: token },
    { teamId: env.APPLE_TEAM_ID!, keyId: env.APPLE_KEY_ID!, clientId: env.APPLE_CLIENT_ID!, privateKeyPem: env.APPLE_PRIVATE_KEY! },
    deps.fetch,
    deps.now(),
  );
  return new Response(null, { status: 204, headers: BASE_HEADERS });
}

export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  const pathname = new URL(request.url).pathname;
  const path = PATHS[pathname];
  const logPath = path ? pathname : "unknown";
  let res: Response;
  try {
    if (!path) throw new WorkerError("not_found");
    res = await route(request, env, deps, path);
    log(logPath, res.status);
  } catch (e) {
    const err = e instanceof WorkerError ? e : new WorkerError("internal");
    if (!(e instanceof WorkerError)) console.log(JSON.stringify({ route: logPath, unexpected: e instanceof Error ? e.name : "unknown" }));
    res = errorResponse(err);
    log(logPath, err.status, err.code);
  }
  return res;
}
