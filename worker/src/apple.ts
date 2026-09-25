export interface AppleConfig {
  teamId: string;
  keyId: string;
  clientId: string;
  privateKeyPem: string;
}

export async function makeClientSecret(_cfg: AppleConfig, _nowMs: number): Promise<string> {
  throw new Error("not implemented yet");
}

export async function revokeApple(
  _grant: { authorization_code: string } | { refresh_token: string },
  _cfg: AppleConfig,
  _fetch: (input: string, init?: RequestInit) => Promise<Response>,
  _nowMs: number,
): Promise<void> {
  throw new Error("not implemented yet");
}
