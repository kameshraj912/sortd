export interface PostHogConfig {
  host: string;
  projectId: string;
  apiKey: string;
}

export async function deletePerson(
  _distinctId: string,
  _cfg: PostHogConfig,
  _fetch: (input: string, init?: RequestInit) => Promise<Response>,
): Promise<void> {
  throw new Error("not implemented yet");
}
