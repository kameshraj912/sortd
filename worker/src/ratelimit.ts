import type { RateLimiter } from "./types";

export const RETRY_AFTER_SECONDS = 60;

export async function checkLimit(_binding: RateLimiter | undefined, _key: string): Promise<void> {
  throw new Error("not implemented yet");
}
