// Shared types. Secrets and vars come from wrangler (see wrangler.jsonc and README.md).

/** The Workers Rate Limiting binding (same shape as site/wrangler.jsonc's BETA_LIMIT). */
export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  // vars
  ENV?: string; // "prod" or "dev"; anything else fails closed
  POSTHOG_API_HOST?: string;
  // secrets (npx wrangler secret put <NAME>)
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_CLIENT_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  POSTHOG_API_KEY?: string;
  POSTHOG_PROJECT_ID?: string;
  CHALLENGE_KEY?: string;
  DEV_BYPASS_TOKEN?: string; // dev environment only
  // ratelimits
  IP_LIMIT?: RateLimiter;
  ID_LIMIT?: RateLimiter;
}

/** Things tests swap out: every upstream call, the clock, and the App Attest root. */
export interface Deps {
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
  /** Milliseconds since the epoch. */
  now: () => number;
  /** DER bytes of the trusted App Attest root certificate(s). */
  attestRoots: Uint8Array[];
  /** SHA-256 (lowercase hex) of each root allowed. A root not listed here is ignored. */
  attestRootSha256: string[];
}
