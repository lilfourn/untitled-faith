import { env } from "cloudflare:workers";
import { applyD1Migrations } from "cloudflare:test";
import { beforeAll, beforeEach } from "vitest";

beforeAll(async () => {
  await applyD1Migrations(env.DB, (env as Env & { TEST_MIGRATIONS: Parameters<typeof applyD1Migrations>[1] }).TEST_MIGRATIONS);
});
beforeEach(async () => {
  await env.DB.prepare('UPDATE payment_environment SET livemode = 1 WHERE id = 1').run();
  await env.DB.batch(["stripe_events", "payment_allocations", "stripe_payments", "checkout_intents",
    "usage_resolutions", "usage_requests", "wallet_entries", "developer_entries", "contributions", "contribution_reversals", "users", "free_months"]
    .map(table => env.DB.prepare(`DELETE FROM ${table}`)));
});
