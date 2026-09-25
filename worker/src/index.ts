import type { Deps, Env } from "./types";

export async function handle(_request: Request, _env: Env, _deps: Deps): Promise<Response> {
  throw new Error("not implemented yet");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env, { fetch: (i, init) => fetch(i, init), now: () => Date.now(), attestRoots: [] });
  },
};
