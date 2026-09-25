// Every failure leaves the Worker as {"error":"<code>"} with a fixed status.
// Codes and statuses come from the spec's API section.

const STATUS: Record<string, number> = {
  too_large: 413,
  not_found: 404,
  method_not_allowed: 405,
  origin_forbidden: 403,
  bad_request: 400,
  wrong_client: 400,
  attest_missing: 401,
  attest_invalid: 401,
  challenge_expired: 401,
  rate_limited: 429,
  posthog_auth: 502,
  posthog_rejected: 502,
  apple_unavailable: 503,
  posthog_unavailable: 503,
  misconfigured: 503,
  internal: 500,
};

export class WorkerError extends Error {
  readonly code: string;
  readonly status: number;
  constructor(code: string, status?: number) {
    super(code);
    this.name = "WorkerError";
    this.code = code;
    // apple_<apple error> codes are all 502: "do not retry this input".
    this.status = status ?? STATUS[code] ?? (code.startsWith("apple_") ? 502 : 500);
  }
}

export function fail(code: string): never {
  throw new WorkerError(code);
}
