import { env } from 'cloudflare:workers';
import { afterEach, expect, it, vi } from 'vitest';
import { accountForIdentity, beginAccountDeletion } from '../src/accounts';
import { holdUncertainUsage, reserveUsage, settleUsage, usageSummary } from '../src/usage';
import { reconcileUsage } from '../src/reconcile-usage';

afterEach(() => vi.unstubAllGlobals());

it('releases a stale reservation only when its checkpoint proves inference never started', async () => {
  const account = await accountForIdentity(env.DB, 'pre-dispatch');
  const request = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000, new Date(Date.now() - 360000));
  const fetcher = vi.fn();
  vi.stubGlobal('fetch', fetcher);
  await reconcileUsage(env.DB, 'test-key');
  expect(fetcher).not.toHaveBeenCalled();
  expect(await env.DB.prepare('SELECT status FROM usage_requests WHERE id = ?').bind(request.id).first())
    .toEqual({ status: 'released' });
  expect((await usageSummary(env.DB, account.id)).free.usedThisMonth).toBe(0);
  await expect(beginAccountDeletion(env.DB, account.id)).resolves.toBe(true);
});

it('escalates an old request without a provider ID without inventing a zero cost', async () => {
  const account = await accountForIdentity(env.DB, 'missing-id');
  const request = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000, new Date(Date.now() - 25 * 3600000));
  await env.DB.prepare("UPDATE usage_requests SET inference_stage = 'review' WHERE id = ?").bind(request.id).run();
  await holdUncertainUsage(env.DB, request.id);
  const fetcher = vi.fn();
  vi.stubGlobal('fetch', fetcher);
  await reconcileUsage(env.DB, 'test-key');
  const row = await env.DB.prepare('SELECT status, needs_review_at, reconciliation_error FROM usage_requests WHERE id = ?').bind(request.id).first();
  expect(row).toMatchObject({ status: 'uncertain', reconciliation_error: 'missing_generation_id' });
  expect(row?.needs_review_at).toEqual(expect.any(Number));
  expect(fetcher).not.toHaveBeenCalled();
  await expect(beginAccountDeletion(env.DB, account.id)).rejects.toMatchObject({ status: 409 });
});

it('escalates repeated missing provider metadata and still accepts later verified settlement', async () => {
  const account = await accountForIdentity(env.DB, 'provider-404');
  const request = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000);
  await holdUncertainUsage(env.DB, request.id, 'missing-generation');
  vi.stubGlobal('fetch', vi.fn().mockImplementation(() => Promise.resolve(new Response(null, { status: 404 }))));
  for (let attempt = 0; attempt < 8; attempt++) await reconcileUsage(env.DB, 'test-key');
  expect((await usageSummary(env.DB, account.id)).usage.requestsNeedingReview).toBe(1);
  await settleUsage(env.DB, request.id, { costMicros: 100, promptTokens: 1, completionTokens: 2 });
  expect((await usageSummary(env.DB, account.id)).usage.requestsNeedingReview).toBe(0);
});

async function resolveRequest(id: string, kind: 'verified' | 'write_off', cost: number) {
  return env.DB.prepare(`INSERT INTO usage_resolutions
    (request_id, kind, provider_cost_micros, prompt_tokens, completion_tokens, reason, operator, created_at)
    VALUES (?, ?, ?, 0, 0, 'Verified support evidence', 'test-operator', ?)`)
    .bind(id, kind, cost, Date.now()).run();
}

it('atomically audits a resolution, adds checkpointed review cost once, and unlocks deletion', async () => {
  const account = await accountForIdentity(env.DB, 'audited-resolution');
  const request = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000);
  await env.DB.prepare('UPDATE usage_requests SET review_cost_micros = 50, review_prompt_tokens = 10 WHERE id = ?').bind(request.id).run();
  await holdUncertainUsage(env.DB, request.id);
  await resolveRequest(request.id, 'verified', 100);
  await expect(resolveRequest(request.id, 'verified', 100)).rejects.toThrow();
  await settleUsage(env.DB, request.id, { costMicros: 999, promptTokens: 999, completionTokens: 999 });
  const summary = await usageSummary(env.DB, account.id);
  expect(summary.usage.costMicros).toBe(150);
  expect(summary.usage.promptTokens).toBe(10);
  expect(summary.usage.pendingRequests).toBe(0);
  expect(await env.DB.prepare('SELECT reserved_micros, spent_micros FROM free_months').first())
    .toEqual({ reserved_micros: 0, spent_micros: 150 });
  await expect(beginAccountDeletion(env.DB, account.id)).resolves.toBe(true);
});

it('rejects resolving an active request and rejects a write-off containing a fabricated cost', async () => {
  const account = await accountForIdentity(env.DB, 'invalid-resolution');
  const request = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000);
  await expect(resolveRequest(request.id, 'verified', 100)).rejects.toThrow();
  await holdUncertainUsage(env.DB, request.id);
  await expect(resolveRequest(request.id, 'write_off', 100)).rejects.toThrow();
  await resolveRequest(request.id, 'write_off', 0);
  expect((await usageSummary(env.DB, account.id)).usage.pendingRequests).toBe(0);
});


it('keeps unresolved requests visible after the allowance month rolls over', async () => {
  const account = await accountForIdentity(env.DB, 'old-month');
  const now = new Date();
  const previousMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const request = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000, previousMonth);
  await holdUncertainUsage(env.DB, request.id);
  await env.DB.prepare('UPDATE usage_requests SET needs_review_at = ? WHERE id = ?').bind(Date.now(), request.id).run();
  const summary = await usageSummary(env.DB, account.id);
  expect(summary.free.usedThisMonth).toBe(0);
  expect(summary.usage.pendingRequests).toBe(1);
  expect(summary.usage.requestsNeedingReview).toBe(1);
});


it('rejects a resolution whose combined review and provider accounting exceeds safe integer precision', async () => {
  const account = await accountForIdentity(env.DB, 'overflow-resolution');
  const request = await reserveUsage(env.DB, account.id, crypto.randomUUID(), 10000);
  await env.DB.prepare('UPDATE usage_requests SET review_cost_micros = 1 WHERE id = ?').bind(request.id).run();
  await holdUncertainUsage(env.DB, request.id);
  await expect(resolveRequest(request.id, 'verified', Number.MAX_SAFE_INTEGER)).rejects.toThrow();
  expect((await usageSummary(env.DB, account.id)).usage.pendingRequests).toBe(1);
  expect(await env.DB.prepare('SELECT request_id FROM usage_resolutions').first()).toBeNull();
});
