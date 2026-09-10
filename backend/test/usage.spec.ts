import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { accountForIdentity, beginAccountDeletion, cancelAccountDeletion, deleteAccountData, requireAccount } from "../src/accounts";
import { creditContribution, reverseContribution } from "../src/contributions";
import { holdUncertainUsage, releaseUsage, reserveUsage, settleUsage, usageSummary } from "../src/usage";

const now = new Date("2026-09-09T12:00:00Z");
const bill = { costMicros: 2000, promptTokens: 100, completionTokens: 200 };
const reserve = (id: string, at = now) => reserveUsage(env.DB, id, crypto.randomUUID(), 10000, at);
const newAccount = () => accountForIdentity(env.DB, crypto.randomUUID());
async function fund(id: string, transactionID = crypto.randomUUID()) {
  const payment = { provider: "app_store" as const, transactionID, userID: id, grossMicros: 5_000_000, feeMicros: 750_000 };
  await creditContribution(env.DB, payment);
  return payment;
}

describe("persistent accounts, quotas, and personal funding", () => {
  it("keeps the streamed generation ID when a later settlement failure has no ID", async () => {
    const account = await newAccount();
    const reservation = await reserve(account.id);
    await env.DB.prepare("UPDATE usage_requests SET generation_id = ? WHERE id = ?")
      .bind("streamed-generation", reservation.id).run();
    await holdUncertainUsage(env.DB, reservation.id);
    expect(await env.DB.prepare("SELECT status, generation_id FROM usage_requests WHERE id = ?").bind(reservation.id).first())
      .toEqual({ status: "uncertain", generation_id: "streamed-generation" });
  });
  it("shows a normalized remaining percentage and increases it when the user adds funding", async () => {
    const account = await newAccount();
    expect((await usageSummary(env.DB, account.id, now)).remainingPercent).toBe(100);
    for (let i = 0; i < 3; i++) await settleUsage(env.DB, (await reserve(account.id)).id, bill);
    expect((await usageSummary(env.DB, account.id, now)).remainingPercent).toBe(90);
    await fund(account.id);
    const percent = (await usageSummary(env.DB, account.id, now)).remainingPercent;
    expect(percent).toBeGreaterThan(90);
    expect(percent).toBeLessThanOrEqual(100);
  });
  it("does not grant credit when a refund notification arrives before the purchase notification", async () => {
    const account = await newAccount();
    const transactionID = crypto.randomUUID();
    await reverseContribution(env.DB, "app_store", transactionID);
    await expect(fund(account.id, transactionID)).rejects.toThrow("contribution_reversed");
    expect((await requireAccount(env.DB, account.id)).paid_balance_micros).toBe(0);
  });

  it("locks deletion against new requests and payments and can recover from a failed Apple revocation", async () => {
    const account = await newAccount();
    await beginAccountDeletion(env.DB, account.id);
    await expect(reserve(account.id)).rejects.toMatchObject({ status: 401 });
    await expect(fund(account.id)).rejects.toThrow("account_missing");
    await cancelAccountDeletion(env.DB, account.id);
    expect((await reserve(account.id)).funding).toBe("free");
    await expect(beginAccountDeletion(env.DB, account.id)).rejects.toMatchObject({ status: 409 });
  });
  it("creates one stable account for repeated verified Apple identities", async () => {
    const accounts = await Promise.all(Array.from({ length: 5 }, () => accountForIdentity(env.DB, "same-verified-identity")));
    expect(new Set(accounts.map(account => account.id)).size).toBe(1);
    expect(new Set(accounts.map(account => account.app_account_token)).size).toBe(1);
  });

  it("enforces five daily free requests, then consumes only personal funding", async () => {
    const account = await newAccount();
    for (let i = 0; i < 5; i++) await settleUsage(env.DB, (await reserve(account.id)).id, bill);
    await expect(reserve(account.id)).rejects.toMatchObject({ status: 402, code: "daily_free_limit" });
    const beforeFunding = await usageSummary(env.DB, account.id, now);
    expect(beforeFunding.free).toMatchObject({ remainingToday: 0, remainingThisMonth: 25,
      resetsAt: '2026-09-10T00:00:00.000Z' });
    expect(beforeFunding.remainingPercent).toBe(83);
    await fund(account.id);
    const paid = await reserve(account.id);
    expect(paid.funding).toBe("paid");
    expect((await requireAccount(env.DB, account.id)).paid_reserved_micros).toBe(10000);
    await settleUsage(env.DB, paid.id, bill);
    const summary = await usageSummary(env.DB, account.id, now);
    expect(summary.free.usedThisMonth).toBe(5);
    expect(summary.funding.availableMicros).toBe(4_248_000);
    expect(summary.usage.promptTokens).toBe(600);
    expect(summary.usage.completionTokens).toBe(1200);
  });

  it("resets the free allowance by UTC month while paid funding carries forward", async () => {
    const account = await newAccount();
    await fund(account.id);
    for (let day = 1; day <= 6; day++) {
      const date = new Date(`2026-09-0${day}T12:00:00Z`);
      for (let i = 0; i < 5; i++) await settleUsage(env.DB, (await reserve(account.id, date)).id, bill);
    }
    expect((await reserve(account.id, new Date("2026-09-30T23:59:59Z"))).funding).toBe("paid");
    const pending = await env.DB.prepare("SELECT id FROM usage_requests WHERE status = 'reserved'").first<{ id: string }>();
    await releaseUsage(env.DB, pending!.id);
    const next = await reserve(account.id, new Date("2026-10-01T00:00:00Z"));
    expect(next.funding).toBe("free");
    expect((await usageSummary(env.DB, account.id, new Date("2026-10-01"))).free.usedThisMonth).toBe(1);
    expect((await requireAccount(env.DB, account.id)).paid_balance_micros).toBe(4_250_000);
  });

  it("identifies the monthly limit even when a new day has free daily slots", async () => {
    const account = await newAccount();
    for (let day = 1; day <= 6; day++) {
      for (let question = 0; question < 5; question++) {
        await settleUsage(env.DB, (await reserve(account.id, new Date(`2026-09-0${day}T12:00:00Z`))).id, bill);
      }
    }
    await expect(reserve(account.id, new Date('2026-09-07T12:00:00Z')))
      .rejects.toMatchObject({ status: 402, code: 'monthly_free_limit' });
  });

  it("atomically rejects concurrent requests for the same account", async () => {
    const account = await newAccount();
    const attempts = await Promise.allSettled(Array.from({ length: 8 }, () => reserve(account.id)));
    expect(attempts.filter(result => result.status === "fulfilled")).toHaveLength(1);
    const summary = await usageSummary(env.DB, account.id, now);
    expect(summary.free.usedThisMonth).toBe(1);
  });

  it("cannot overspend the shared free pool across different accounts", async () => {
    await env.DB.prepare("INSERT INTO free_months(month, budget_micros) VALUES ('2026-09', 10000)").run();
    const accounts = await Promise.all(Array.from({ length: 8 }, newAccount));
    const attempts = await Promise.allSettled(accounts.map(account => reserve(account.id)));
    expect(attempts.filter(result => result.status === "fulfilled")).toHaveLength(1);
    const pool = await env.DB.prepare("SELECT reserved_micros FROM free_months WHERE month = '2026-09'").first();
    expect(pool?.reserved_micros).toBe(10000);
  });

  it("deduplicates requests and never bills twice when settlement is repeated", async () => {
    const account = await newAccount();
    await fund(account.id);
    await env.DB.prepare("INSERT INTO free_months(month, budget_micros) VALUES ('2026-09', 0)").run();
    const key = crypto.randomUUID();
    const request = await reserveUsage(env.DB, account.id, key, 10000, now);
    await settleUsage(env.DB, request.id, bill);
    await settleUsage(env.DB, request.id, bill);
    await expect(reserveUsage(env.DB, account.id, key, 10000, now)).rejects.toMatchObject({ code: "request_already_processed" });
    expect((await requireAccount(env.DB, account.id)).paid_balance_micros).toBe(4_248_000);
  });

  it("releases unbilled failures but holds uncertain provider charges", async () => {
    const account = await newAccount();
    const request = await reserve(account.id);
    await releaseUsage(env.DB, request.id);
    expect((await usageSummary(env.DB, account.id, now)).free.usedThisMonth).toBe(0);
    const uncertain = await reserve(account.id);
    await holdUncertainUsage(env.DB, uncertain.id, "generation-123");
    const pool = await env.DB.prepare("SELECT reserved_micros FROM free_months WHERE month = '2026-09'").first();
    expect(pool?.reserved_micros).toBe(10000);
    await settleUsage(env.DB, uncertain.id, bill);
    expect((await usageSummary(env.DB, account.id, now)).usage.pendingRequests).toBe(0);
  });

  it("credits net funding once and rejects attempts to reuse another user's payment", async () => {
    const first = await newAccount();
    const second = await newAccount();
    const payment = await fund(first.id);
    await creditContribution(env.DB, payment);
    await expect(creditContribution(env.DB, { ...payment, userID: second.id })).rejects.toMatchObject({ code: "contribution_conflict" });
    expect((await requireAccount(env.DB, first.id)).paid_balance_micros).toBe(4_250_000);
    expect((await requireAccount(env.DB, second.id)).paid_balance_micros).toBe(0);
  });

  it("reverses refunds once, even when the user has already spent the funding", async () => {
    const account = await newAccount();
    const payment = await fund(account.id);
    await env.DB.prepare("INSERT INTO free_months(month, budget_micros) VALUES ('2026-09', 0)").run();
    await settleUsage(env.DB, (await reserve(account.id)).id, bill);
    await reverseContribution(env.DB, payment.provider, payment.transactionID);
    await reverseContribution(env.DB, payment.provider, payment.transactionID);
    expect((await requireAccount(env.DB, account.id)).paid_balance_micros).toBe(-2000);
    await expect(reserve(account.id)).rejects.toMatchObject({ code: "free_pool_exhausted" });
  });

  it("deletes an empty account, invalidates access, and unlinks settled accounting", async () => {
    const account = await newAccount();
    await settleUsage(env.DB, (await reserve(account.id)).id, bill);
    await deleteAccountData(env.DB, account.id);
    await expect(requireAccount(env.DB, account.id)).rejects.toMatchObject({ status: 401 });
    expect((await env.DB.prepare("SELECT user_id FROM usage_requests").first())?.user_id).toBeNull();
    expect((await env.DB.prepare("SELECT spent_micros FROM free_months").first())?.spent_micros).toBe(2000);
  });
});
