import { defineConfig } from "vitest/config";

// Plain Vitest on Node. Node has the same WebCrypto, fetch, Request and Response the
// Worker uses. Every upstream call goes through an injected fetch and the rate limiters
// are passed in as fakes, so no test touches the network.
// (@cloudflare/vitest-pool-workers is deprecated; see the spec's Files section.)
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});
