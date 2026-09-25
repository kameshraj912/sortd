// Delete one PostHog person, and their events, by distinct id.
//
// Endpoint (spec: API): POST {POSTHOG_API_HOST}/api/environments/{project_id}/persons/bulk_delete/
//   body {"distinct_ids":[id],"delete_events":true}, Authorization: Bearer phx_... (person:write)
// Docs: https://posthog.com/docs/privacy/data-deletion and https://posthog.com/docs/api/persons
// The spec marks the exact path and the unknown-id reply as NOT VERIFIED with a real key:
// confirm with one real phx_ call before shipping.
//
// Idempotent: today bulk_delete answers 202 and drops ids it does not know. A PostHog draft
// PR (#104461) would instead answer 400 naming the unknown ids when delete_events is set;
// a 400 whose body names our id is treated as done too.
// A 404 is NOT treated as done: bulk_delete has no per-person 404, so a 404 means the
// project id or path is wrong, and hiding that would silently skip every deletion.

import { WorkerError } from "./errors";

const TIMEOUT_MS = 10_000;

export interface PostHogConfig {
  host: string;
  projectId: string;
  apiKey: string;
}

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

export async function deletePerson(distinctId: string, cfg: PostHogConfig, fetchFn: Fetch): Promise<void> {
  const url = `${cfg.host.replace(/\/+$/, "")}/api/environments/${encodeURIComponent(cfg.projectId)}/persons/bulk_delete/`;
  let res: Response;
  try {
    res = await fetchFn(url, {
      method: "POST",
      headers: { authorization: `Bearer ${cfg.apiKey}`, "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ distinct_ids: [distinctId], delete_events: true }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch {
    throw new WorkerError("posthog_unavailable");
  }

  if (res.ok) return; // 200, 202, 204
  if (res.status === 401 || res.status === 403) throw new WorkerError("posthog_auth");
  if (res.status === 404) throw new WorkerError("misconfigured");
  if (res.status === 429 || res.status >= 500) throw new WorkerError("posthog_unavailable");
  if (res.status === 400) {
    let text = "";
    try {
      text = await res.text();
    } catch {
      // ignore
    }
    if (text.includes(distinctId)) return; // "unknown distinct id": already gone
  }
  throw new WorkerError("posthog_rejected");
}
