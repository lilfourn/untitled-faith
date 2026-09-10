import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { accountForIdentity } from "../src/accounts";
import { reconcileUsage } from "../src/reconcile-usage";
import { holdUncertainUsage, reserveUsage, usageSummary } from "../src/usage";

afterEach(() => vi.unstubAllGlobals());
describe("uncertain usage reconciliation", () => {
  it("settles verified final provider metadata without double charging on repeated runs", async () => {
    const account = await accountForIdentity(env.DB, "test-identity");
    const reservation = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000);
    await holdUncertainUsage(env.DB, reservation.id, "test-generation");
    const fetcher = vi.fn().mockResolvedValue(Response.json({ data: {
      id: "test-generation", finish_reason: "stop", total_cost: 0.002,
      native_tokens_prompt: 100, native_tokens_completion: 200,
    } }));
    vi.stubGlobal("fetch", fetcher);
    await reconcileUsage(env.DB, "test-key");
    await reconcileUsage(env.DB, "test-key");
    expect(fetcher).toHaveBeenCalledTimes(1);
    const summary = await usageSummary(env.DB, account.id);
    expect(summary.usage.costMicros).toBe(2110);
    expect(summary.usage.pendingRequests).toBe(0);
  });

  it("retains funds on missing metadata and releases a stale in-progress lock", async () => {
    const account = await accountForIdentity(env.DB, "test-identity");
    const reservation = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000, new Date(Date.now() - 360000));
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(null, { status: 404 })));
    await reconcileUsage(env.DB, "test-key");
    const row = await env.DB.prepare("SELECT status FROM usage_requests WHERE id = ?").bind(reservation.id).first();
    expect(row?.status).toBe("uncertain");
    expect((await usageSummary(env.DB, account.id)).usage.pendingRequests).toBe(1);
    expect((await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000)).funding).toBe("free");
  });
});
