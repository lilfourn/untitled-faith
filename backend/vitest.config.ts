import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: { setupFiles: ["./test/setup.ts"], fileParallelism: false },
  plugins: [cloudflareTest({
    wrangler: { configPath: "./wrangler.jsonc" },
    miniflare: {
      bindings: {
        TEST_MIGRATIONS: await readD1Migrations("./migrations"),
        OPENROUTER_API_KEY: "test-only-upstream-key",
        // Tests explicitly opt into mocked Crossway access; never inherit the developer's real key.
        ESV_API_KEY: "",
        SESSION_SIGNING_KEY: "test-only-signing-key-at-least-32-bytes-long",
      },
    },
  })],
});
