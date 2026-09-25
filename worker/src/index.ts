// sortd-account Worker entry point. Spec: docs/specs/2026-09-25-account-worker.md.
// workerd only allows handlers as exports of the main module, so this file exports
// nothing but the default handler. The logic lives in handler.ts.

import { APPLE_APP_ATTEST_ROOT_PEM } from "./attest";
import { pemToDer } from "./bytes";
import { handle } from "./handler";
import type { Env } from "./types";

let roots: Uint8Array[] | undefined;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    roots ??= [pemToDer(APPLE_APP_ATTEST_ROOT_PEM)];
    return handle(request, env, { fetch: (input, init) => fetch(input, init), now: () => Date.now(), attestRoots: roots });
  },
} satisfies ExportedHandler<Env>;
