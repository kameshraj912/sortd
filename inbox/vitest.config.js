// Tests run inside workerd (the real Workers runtime) with a local, throwaway KV.
// Nothing talks to Cloudflare. DNS lookups are faked in the tests.
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
    }),
  ],
});
