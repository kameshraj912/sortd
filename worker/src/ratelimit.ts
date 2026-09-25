// Flood guards on the Workers Rate Limiting binding (same binding type as the site's
// BETA_LIMIT in site/wrangler.jsonc). Counters are per Cloudflare location and eventually
// consistent: a flood guard, not an exact quota.
//
// Unlike the site Worker, a missing binding fails closed (503 misconfigured): this Worker
// holds keys that can revoke and delete, so it must not run unguarded.
// https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/

import { WorkerError } from "./errors";
import type { RateLimiter } from "./types";

export const RETRY_AFTER_SECONDS = 60;

export async function checkLimit(binding: RateLimiter | undefined, key: string): Promise<void> {
  if (!binding) throw new WorkerError("misconfigured");
  let success: boolean;
  try {
    ({ success } = await binding.limit({ key }));
  } catch {
    throw new WorkerError("misconfigured");
  }
  if (!success) throw new WorkerError("rate_limited");
}
