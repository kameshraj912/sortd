export const ROUTES = ["apple/revoke", "posthog/delete-person"] as const;
export type Route = (typeof ROUTES)[number];
export const CHALLENGE_TTL_MS = 120_000;

export async function issueChallenge(_key: string, _route: Route, _bodySha256Hex: string, _nowMs: number): Promise<string> {
  throw new Error("not implemented yet");
}

export async function verifyChallenge(_key: string, _challenge: string, _route: Route, _body: Uint8Array, _nowMs: number): Promise<void> {
  throw new Error("not implemented yet");
}
