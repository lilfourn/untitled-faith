import { env } from 'cloudflare:workers';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SignJWT } from 'jose';
import { accountForIdentity, beginAccountDeletion, requireAccount } from '../src/accounts';
import { handlePayments, paymentReturnPage } from '../src/payments/routes';
import { createCheckout, CheckoutIntent, isStripeCheckoutURL } from '../src/payments/checkout';
import { allocation, saveSnapshot, synchronizeCheckout } from '../src/payments/reconciliation';
import { PaymentEnv, parseSelection } from '../src/payments/configuration';
import { ownerPaymentSummary } from '../src/payments/summary';
import { receiveStripeEvent, retryStripeEvents } from '../src/payments/webhook';

const paymentEnv: PaymentEnv = { ...env, PAYMENTS_ENABLED: 'true', STRIPE_MODE: 'test',
  STRIPE_SECRET_KEY: 'sk_test_mock_only', STRIPE_WEBHOOK_SECRET: 'whsec_test_mock_only',
  PAYMENT_PUBLIC_ORIGIN: 'https://faith.example',
  AUTH_RATE_LIMITER: { limit: async () => ({ success: true }) } };
let intent: CheckoutIntent;
let session: Record<string, unknown>;
let charge: Record<string, unknown>;
let pi: Record<string, unknown>;
let createCalls = 0;
let sessionCalls = 0;
let stripeDown = false;
let disputeStatus = 'needs_response';
let lastCreateBody: URLSearchParams;

async function makeIntent(amount = 1000, share = 300) {
  const user = await accountForIdentity(env.DB, crypto.randomUUID());
  const now = Date.now();
  const row: CheckoutIntent = { id: crypto.randomUUID(), user_id: user.id, idempotency_key: crypto.randomUUID(),
    amount_cents: amount, developer_share_bps: share, estimated_fee_cents: Math.ceil(amount * .029) + 30,
    livemode: 0, session_id: 'cs_test_' + crypto.randomUUID(), checkout_url: 'https://checkout.stripe.com/c/pay/test',
    status: 'open', created_at: now, checked_at: now };
  await env.DB.prepare(`INSERT INTO checkout_intents
    (id, user_id, idempotency_key, amount_cents, developer_share_bps, estimated_fee_cents, livemode,
      session_id, checkout_url, status, created_at, checked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(row.id, row.user_id, row.idempotency_key, amount, share, row.estimated_fee_cents, 0,
      row.session_id, row.checkout_url, 'open', now, now).run();
  return row;
}

beforeEach(async () => {
  await env.DB.prepare('UPDATE payment_environment SET livemode = 0 WHERE id = 1').run();
  intent = await makeIntent();
  createCalls = 0; sessionCalls = 0; stripeDown = false; disputeStatus = 'needs_response';
  session = { id: intent.session_id, object: 'checkout.session', metadata: { application: 'untitled-faith', intent_id: intent.id },
    client_reference_id: intent.id, mode: 'payment', currency: 'usd', amount_total: 1000, livemode: false,
    payment_status: 'paid', status: 'complete', payment_intent: 'pi_paid', url: intent.checkout_url };
  charge = { id: 'ch_paid', object: 'charge', paid: true, captured: true, status: 'succeeded', currency: 'usd',
    amount: 1000, amount_refunded: 0, livemode: false, payment_intent: 'pi_paid', disputed: false,
    balance_transaction: { id: 'txn_fee', currency: 'usd', amount: 1000, fee: 59, net: 941 } };
  pi = { id: 'pi_paid', object: 'payment_intent', metadata: { application: 'untitled-faith', intent_id: intent.id },
    status: 'succeeded', currency: 'usd', amount: 1000, amount_received: 1000, livemode: false, latest_charge: charge };
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (url.hostname !== 'api.stripe.com') throw new Error('Unexpected network request');
    if (stripeDown) return Response.json({ error: { type: 'api_error', message: 'Temporary failure' } }, { status: 503 });
    if (url.pathname === '/v1/checkout/sessions' && request.method === 'POST') {
      createCalls++;
      lastCreateBody = new URLSearchParams(await request.text());
      const id = lastCreateBody.get('metadata[intent_id]')!;
      return Response.json({ ...session, id: 'cs_test_created', metadata: { application: 'untitled-faith', intent_id: id },
        client_reference_id: id, amount_total: Number(lastCreateBody.get('line_items[0][price_data][unit_amount]')),
        payment_status: 'unpaid', status: 'open' });
    }
    if (url.pathname.startsWith('/v1/checkout/sessions/')) { sessionCalls++; return Response.json(session); }
    if (url.pathname.startsWith('/v1/payment_intents/')) return Response.json(pi);
    if (url.pathname === '/v1/disputes') return Response.json({ object: 'list', data: [{ status: disputeStatus }], has_more: false });
    throw new Error('Unexpected Stripe operation');
  });
});
afterEach(() => { vi.restoreAllMocks(); });

async function balance() { return (await requireAccount(env.DB, intent.user_id!)).paid_balance_micros; }
async function requestToken(userID: string) {
  return new SignJWT({ scope: 'answers' }).setProtectedHeader({ alg: 'HS256' }).setSubject(userID)
    .setIssuer('untitled-faith').setAudience('untitled-faith-proxy').setIssuedAt().setExpirationTime('10m')
    .sign(new TextEncoder().encode(env.SESSION_SIGNING_KEY));
}
async function signedEvent(type = 'checkout.session.completed', overrides: Record<string, unknown> = {}, ageSeconds = 0) {
  const body = JSON.stringify({ id: 'evt_test_event', object: 'event', type, livemode: false,
    data: { object: session }, ...overrides });
  const timestamp = Math.floor(Date.now() / 1000) - ageSeconds;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(paymentEnv.STRIPE_WEBHOOK_SECRET),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const digest = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${timestamp}.${body}`)));
  const signature = Array.from(digest, b => b.toString(16).padStart(2, '0')).join('');
  return new Request('https://faith.example/v1/payments/stripe/webhook', {
    method: 'POST', body, headers: { 'Stripe-Signature': `t=${timestamp},v1=${signature}` },
  });
}

describe('Stripe checkout boundary', () => {
  it('seals an arbitrary cent amount and optional share before contacting Stripe, and retries without a second checkout', async () => {
    const key = crypto.randomUUID();
    const input = { amountCents: 1234, developerShareBasisPoints: 300, storefront: 'USA' };
    const first = await createCheckout(paymentEnv, intent.user_id!, key, input);
    expect(await createCheckout(paymentEnv, intent.user_id!, key, input)).toEqual(first);
    expect(createCalls).toBe(1);
    expect(lastCreateBody.get('line_items[0][price_data][unit_amount]')).toBe('1234');
    expect(lastCreateBody.get('payment_method_types[0]')).toBe('card');
    expect(lastCreateBody.get('payment_intent_data[metadata][intent_id]')).toBe(first.intentID);
    expect(await balance()).toBe(0);
    await expect(createCheckout(paymentEnv, intent.user_id!, key, { ...input, amountCents: 1300 }))
      .rejects.toMatchObject({ code: 'checkout_conflict' });
  });
  it('rejects client fees, invalid precision, unapproved storefronts and invalid share percentages', () => {
    for (const override of [{ amountCents: 0 }, { amountCents: 100001 }, { amountCents: 100.5 },
      { developerShareBasisPoints: 301 }, { developerShareBasisPoints: -1 }, { feeCents: 0 }, { userID: 'another-user' }]) {
      expect(() => parseSelection({ amountCents: 1000, developerShareBasisPoints: 0, storefront: 'USA', ...override })).toThrow();
    }
    expect(() => parseSelection({ amountCents: 1000, developerShareBasisPoints: 0, storefront: 'GBR' }))
      .toThrow('checkout_region_unavailable');
  });
  it('fails closed until configured and never returns an arbitrary redirect host', async () => {
    await expect(createCheckout({ ...paymentEnv, PAYMENTS_ENABLED: 'false' }, intent.user_id!, crypto.randomUUID(), {}))
      .rejects.toMatchObject({ code: 'payments_not_configured' });
    expect(isStripeCheckoutURL('https://checkout.stripe.com/c/pay/x')).toBe(true);
    for (const url of ['http://checkout.stripe.com/x', 'https://checkout.stripe.com.evil.test/x', 'https://x@checkout.stripe.com/x']) {
      expect(isStripeCheckoutURL(url)).toBe(false);
    }
  });
  it('prevents account deletion while a checkout can still be paid', async () => {
    await expect(beginAccountDeletion(env.DB, intent.user_id!)).rejects.toMatchObject({ code: 'account_has_unsettled_funding' });
    await env.DB.prepare("UPDATE checkout_intents SET status = 'expired' WHERE id = ?").bind(intent.id).run();
    expect(await beginAccountDeletion(env.DB, intent.user_id!)).toBe(true);
  });
});

describe('verified payment accounting', () => {
  it('credits the buyer once and keeps developer earnings out of their spendable balance', async () => {
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(9_110_000);
    const totals = await ownerPaymentSummary(env.DB);
    expect(totals.stripe?.developerShareMicros).toBe(300_000);
    expect(totals.stripe?.usageFundingMicros).toBe(9_110_000);
    expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM payment_allocations').first())?.n).toBe(1);
  });
  it('handles concurrent deliveries with one credit', async () => {
    await Promise.all([synchronizeCheckout(paymentEnv, intent.session_id!), synchronizeCheckout(paymentEnv, intent.session_id!)]);
    expect(await balance()).toBe(9_110_000);
  });
  it('credits an estimate when fees are delayed and reconciles the difference exactly once', async () => {
    charge.balance_transaction = null;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect((await ownerPaymentSummary(env.DB)).stripe?.awaitingFees).toBe(1);
    charge.balance_transaction = { id: 'txn_fee', currency: 'usd', amount: 1000, fee: 74, net: 926 };
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(8_960_000);
    expect((await ownerPaymentSummary(env.DB)).stripe?.developerShareMicros).toBe(300_000);
    expect((await ownerPaymentSummary(env.DB)).stripe?.awaitingFees).toBe(0);
  });
  it('prorates a partial refund and reverses both allocations on a full refund', async () => {
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    charge.amount_refunded = 500;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(4_260_000);
    expect((await ownerPaymentSummary(env.DB)).stripe?.developerShareMicros).toBe(150_000);
    charge.amount_refunded = 1000;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(0);
    expect((await ownerPaymentSummary(env.DB)).stripe?.developerShareMicros).toBe(0);
  });
  it('does not credit a payment first observed after its refund', async () => {
    charge.amount_refunded = 1000;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(0);
    expect((await ownerPaymentSummary(env.DB)).stripe?.refundedMicros).toBe(10_000_000);
  });
  it('removes spendable funding during a dispute', async () => {
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    charge.disputed = true;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(0);
    expect((await ownerPaymentSummary(env.DB)).stripe?.disputedMicros).toBe(10_000_000);
  });
  it('restores both allocations after a won dispute', async () => {
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    charge.disputed = true;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    disputeStatus = 'won';
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(9_110_000);
    expect((await ownerPaymentSummary(env.DB)).stripe?.developerShareMicros).toBe(300_000);
  });
  it('blocks deletion for an open dispute but permits it once the loss is final', async () => {
    charge.disputed = true;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    await expect(beginAccountDeletion(env.DB, intent.user_id!)).rejects.toMatchObject({ code: 'account_has_unsettled_funding' });
    disputeStatus = 'lost';
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(0);
    expect(await beginAccountDeletion(env.DB, intent.user_id!)).toBe(true);
  });
  it('uses a negative balance when already-spent funding is refunded', async () => {
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    await env.DB.prepare(`INSERT INTO wallet_entries(id, user_id, delta_micros, kind, reference_id, created_at)
      VALUES (?, ?, -1000000, 'usage', 'test-spend', ?)`).bind(crypto.randomUUID(), intent.user_id, Date.now()).run();
    charge.amount_refunded = 1000;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(-1_000_000);
  });
  it('does not fulfill unpaid checkout or trust the browser return page', async () => {
    session.status = 'open'; session.payment_status = 'unpaid';
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await balance()).toBe(0);
    const page = paymentReturnPage('/payments/return')!;
    expect(await page.text()).toContain('after your payment is confirmed');
    expect(await balance()).toBe(0);
  });
  it.each([
    ['amount_total', 999], ['currency', 'eur'], ['livemode', true], ['client_reference_id', 'another-account'],
  ])('rejects a checkout with mismatched %s', async (field, value) => {
    session[field] = value;
    await expect(synchronizeCheckout(paymentEnv, intent.session_id!)).rejects.toMatchObject({ code: 'payment_mismatch' });
    expect(await balance()).toBe(0);
  });
  it('rejects a charge with another account intent and non-USD settlement', async () => {
    pi.metadata = { application: 'untitled-faith', intent_id: 'another-intent' };
    await expect(synchronizeCheckout(paymentEnv, intent.session_id!)).rejects.toMatchObject({ code: 'payment_mismatch' });
    pi.metadata = { application: 'untitled-faith', intent_id: intent.id };
    charge.balance_transaction = { currency: 'eur', amount: 1000, fee: 59, net: 941 };
    await expect(synchronizeCheckout(paymentEnv, intent.session_id!)).rejects.toMatchObject({ code: 'payment_currency_mismatch' });
    expect(await balance()).toBe(0);
  });
  it('rejects a stale reconciliation revision instead of restoring refunded credit', async () => {
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    charge.amount_refunded = 1000;
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    expect(await saveSnapshot(env.DB, intent, { id: 'pi_paid', chargeID: 'ch_paid', grossCents: 1000,
      feeCents: 59, feeConfirmed: true, refundedCents: 0, disputed: false, disputeOpen: false,
      usageMicros: 9_110_000, developerMicros: 300_000 }, 1)).toBe(false);
    expect(await balance()).toBe(0);
  });
  it('cent-rounds the developer allocation and preserves conservation', () => {
    const result = allocation(1234, 66, 0, 300, false);
    expect(result.developerMicros).toBe(370_000);
    expect(result.developerMicros + result.usageMicros + 660_000).toBe(12_340_000);
    expect(allocation(100, 150, 100, 300, false)).toEqual({ usageMicros: 0, developerMicros: 0 });
  });
});

describe('signed webhook inbox and access control', () => {
  it('verifies a real HMAC signature and deduplicates webhook delivery', async () => {
    await receiveStripeEvent(await signedEvent(), paymentEnv);
    await receiveStripeEvent(await signedEvent(), paymentEnv);
    expect(await balance()).toBe(9_110_000);
    expect(sessionCalls).toBe(1);
  });
  it('rejects forged and stale signatures and live events sent to the test endpoint', async () => {
    const forged = await signedEvent();
    forged.headers.set('Stripe-Signature', 't=1,v1=123');
    await expect(receiveStripeEvent(forged, paymentEnv)).rejects.toMatchObject({ code: 'invalid_payment_signature' });
    await expect(receiveStripeEvent(await signedEvent('checkout.session.completed', { livemode: true }), paymentEnv))
      .rejects.toMatchObject({ code: 'payment_mode_mismatch' });
    expect(await balance()).toBe(0);
  });
  it('retries a durably recorded event after a Stripe outage', async () => {
    stripeDown = true;
    await expect(receiveStripeEvent(await signedEvent(), paymentEnv)).rejects.toBeDefined();
    expect((await ownerPaymentSummary(env.DB)).operations.pendingEvents).toBe(1);
    stripeDown = false;
    await retryStripeEvents(paymentEnv);
    expect(await balance()).toBe(9_110_000);
    expect((await ownerPaymentSummary(env.DB)).operations.pendingEvents).toBe(0);
  }, 15_000);
  it('ignores unrelated Stripe applications without crediting an account', async () => {
    session.metadata = { application: 'gridbloom' };
    await receiveStripeEvent(await signedEvent(), paymentEnv);
    expect(await balance()).toBe(0);
    expect((await env.DB.prepare('SELECT status FROM stripe_events').first())?.status).toBe('ignored');
  });
  it('rejects an authentic signature outside the replay window', async () => {
    await expect(receiveStripeEvent(await signedEvent('checkout.session.completed', {}, 600), paymentEnv))
      .rejects.toMatchObject({ code: 'invalid_payment_signature' });
    expect(await balance()).toBe(0);
  });
  it('never lets test credentials fund the production ledger', async () => {
    await env.DB.prepare('UPDATE payment_environment SET livemode = 1 WHERE id = 1').run();
    await expect(synchronizeCheckout(paymentEnv, intent.session_id!)).rejects.toMatchObject({ code: 'payment_mode_mismatch' });
    await expect(receiveStripeEvent(await signedEvent(), paymentEnv)).rejects.toMatchObject({ code: 'payment_mode_mismatch' });
    expect(await balance()).toBe(0);
  });
  it('durably acknowledges a signed webhook before background processing completes', async () => {
    const tasks: Promise<unknown>[] = [];
    await receiveStripeEvent(await signedEvent(), paymentEnv, { waitUntil: (task: Promise<unknown>) => tasks.push(task) } as ExecutionContext);
    expect(tasks).toHaveLength(1);
    await Promise.all(tasks);
    expect(await balance()).toBe(9_110_000);
  });
  it('refuses to replace a confirmed fee with an estimate', async () => {
    await synchronizeCheckout(paymentEnv, intent.session_id!);
    charge.balance_transaction = null;
    await expect(synchronizeCheckout(paymentEnv, intent.session_id!)).rejects.toMatchObject({ code: 'payment_busy' });
    expect(await balance()).toBe(9_110_000);
    expect((await ownerPaymentSummary(env.DB)).stripe?.awaitingFees).toBe(0);
  });
  it('requires server-assigned owner identity to read the financial overview', async () => {
    const token = await requestToken(intent.user_id!);
    const request = new Request('https://faith.example/v1/owner/payments', { headers: { Authorization: `Bearer ${token}` } });
    await expect(handlePayments(request, paymentEnv)).rejects.toMatchObject({ code: 'forbidden' });
    const response = await handlePayments(request, { ...paymentEnv, PAYMENT_OWNER_ACCOUNT_ID: intent.user_id! });
    expect(response.status).toBe(200);
    await expect(handlePayments(new Request(request.url), paymentEnv)).rejects.toMatchObject({ code: 'unauthorized' });
  });
});
