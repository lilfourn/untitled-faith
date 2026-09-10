import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { accountForIdentity, requireAccount } from "../src/accounts";
import { creditContribution, reverseContribution } from "../src/contributions";

async function payment(share = 300) {
  const user = await accountForIdentity(env.DB, crypto.randomUUID());
  return { provider: "app_store" as const, transactionID: crypto.randomUUID(), userID: user.id,
    grossMicros: 10_000_000, feeMicros: 1_500_000, developerShareBasisPoints: share };
}

describe("optional developer thanks", () => {
  it("allocates the developer share inside the total after accounting for payment fees", async () => {
    const contribution = await payment();
    await creditContribution(env.DB, contribution);
    expect((await requireAccount(env.DB, contribution.userID)).paid_balance_micros).toBe(8_200_000);
    const developer = await env.DB.prepare("SELECT SUM(delta_micros) AS total FROM developer_entries").first();
    expect(developer?.total).toBe(300_000);
    expect(8_200_000 + 300_000 + contribution.feeMicros).toBe(contribution.grossMicros);
  });

  it("leaves all net proceeds for usage when the user chooses zero", async () => {
    const contribution = await payment(0);
    await creditContribution(env.DB, contribution);
    expect((await requireAccount(env.DB, contribution.userID)).paid_balance_micros).toBe(8_500_000);
    expect((await env.DB.prepare("SELECT COUNT(*) AS count FROM developer_entries").first())?.count).toBe(0);
  });

  it("rounds the split to cents and reverses both balances once on refund", async () => {
    const contribution = { ...await payment(300), grossMicros: 12_340_000, feeMicros: 1_851_000 };
    await creditContribution(env.DB, contribution);
    await creditContribution(env.DB, contribution);
    expect((await env.DB.prepare("SELECT SUM(delta_micros) AS total FROM developer_entries").first())?.total).toBe(370_000);
    await reverseContribution(env.DB, contribution.provider, contribution.transactionID);
    await reverseContribution(env.DB, contribution.provider, contribution.transactionID);
    expect((await requireAccount(env.DB, contribution.userID)).paid_balance_micros).toBe(0);
    expect((await env.DB.prepare("SELECT SUM(delta_micros) AS total FROM developer_entries").first())?.total).toBe(0);
  });

  it("rejects invalid percentages and prevents changing the split on a credited payment", async () => {
    const contribution = await payment();
    for (const value of [-1, 301, 1.5, Number.NaN]) {
      await expect(creditContribution(env.DB, { ...contribution, developerShareBasisPoints: value }))
        .rejects.toMatchObject({ code: "invalid_contribution" });
    }
    await creditContribution(env.DB, contribution);
    await expect(creditContribution(env.DB, { ...contribution, developerShareBasisPoints: 0 }))
      .rejects.toMatchObject({ code: "contribution_conflict" });
    expect((await requireAccount(env.DB, contribution.userID)).paid_balance_micros).toBe(8_200_000);
  });
});
