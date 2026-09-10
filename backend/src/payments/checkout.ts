import type Stripe from 'stripe';
import { APIError } from '../http';
import { checkoutEnabled, parseSelection, paymentConfiguration, PaymentEnv, requirePaymentEnvironment, stripeClient } from './configuration';

export type CheckoutIntent = {
  id: string; user_id: string | null; idempotency_key: string; amount_cents: number;
  developer_share_bps: number; estimated_fee_cents: number; livemode: number;
  session_id: string | null; checkout_url: string | null; status: 'creating' | 'open' | 'paid' | 'expired';
  created_at: number; checked_at: number;
};

export async function createCheckout(env: PaymentEnv, userID: string, key: string | null, input: Record<string, unknown>) {
  if (!checkoutEnabled(env)) throw new APIError(503, 'payments_not_configured');
  await requirePaymentEnvironment(env);
  if (!key || !/^[a-zA-Z0-9_-]{16,128}$/.test(key)) throw new APIError(400, 'idempotency_key_required');
  const selection = parseSelection(input);
  const config = paymentConfiguration(env);
  const now = Date.now();
  await env.DB.prepare(`INSERT INTO checkout_intents
    (id, user_id, idempotency_key, amount_cents, developer_share_bps, estimated_fee_cents, livemode, created_at, checked_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, idempotency_key) DO NOTHING`)
    .bind(crypto.randomUUID(), userID, key, selection.amountCents, selection.developerShareBasisPoints,
      selection.estimatedFeeCents, config.livemode ? 1 : 0, now, now).run();
  const intent = await env.DB.prepare('SELECT * FROM checkout_intents WHERE user_id = ? AND idempotency_key = ?')
    .bind(userID, key).first<CheckoutIntent>();
  if (!intent || intent.amount_cents !== selection.amountCents || intent.developer_share_bps !== selection.developerShareBasisPoints ||
      intent.livemode !== Number(config.livemode)) throw new APIError(409, 'checkout_conflict');
  if (intent.status === 'paid' || intent.status === 'expired') throw new APIError(409, 'checkout_finished');
  if (intent.session_id && intent.checkout_url) return checkoutResponse(intent);
  await provisionCheckout(env, intent);
  return checkoutResponse((await env.DB.prepare('SELECT * FROM checkout_intents WHERE id = ?').bind(intent.id).first<CheckoutIntent>())!);
}

export async function provisionCheckout(env: PaymentEnv, intent: CheckoutIntent, stripe = stripeClient(env)): Promise<void> {
  const { origin } = paymentConfiguration(env);
  // Recover ambiguous timeouts before ever considering a new checkout. Past the idempotency window,
  // search Stripe and close only an intent proven to have no session; never recreate it.
  if (Date.now() - intent.created_at >= 23 * 60 * 60 * 1000) {
    await recoverOldCheckout(env, intent, stripe);
    return;
  }
  const metadata = { application: 'untitled-faith', intent_id: intent.id };
  const session = await stripe.checkout.sessions.create({
    mode: 'payment', managed_payments: { enabled: false }, adaptive_pricing: { enabled: false },
    payment_method_types: ['card'], client_reference_id: intent.id,
    metadata, payment_intent_data: { metadata },
    line_items: [{ quantity: 1, price_data: {
      currency: 'usd', unit_amount: intent.amount_cents,
      product_data: { name: 'Untitled Faith usage funding',
        description: `Optional developer share: ${(intent.developer_share_bps / 100).toFixed(1)}% of this total. Remaining proceeds fund your usage after payment fees.` },
    } }],
    success_url: `${origin}/payments/open`, cancel_url: `${origin}/payments/cancel`,
    expires_at: Math.floor(intent.created_at / 1000) + 24 * 60 * 60,
  }, { idempotencyKey: `faith-checkout-${intent.id}` });
  validateSession(session, intent);
  if (!session.url || !isStripeCheckoutURL(session.url)) throw new APIError(502, 'checkout_unavailable');
  await env.DB.prepare(`UPDATE checkout_intents SET session_id = ?, checkout_url = ?, status = 'open', checked_at = ?
    WHERE id = ? AND status = 'creating' AND session_id IS NULL`)
    .bind(session.id, session.url, Date.now(), intent.id).run();
}

async function recoverOldCheckout(env: PaymentEnv, intent: CheckoutIntent, stripe: Stripe): Promise<void> {
  let found: Stripe.Checkout.Session | undefined;
  let scanned = 0;
  for await (const session of stripe.checkout.sessions.list({ limit: 100, created: {
    gte: Math.floor(intent.created_at / 1000) - 1, lte: Math.floor(intent.created_at / 1000) + 24 * 60 * 60,
  } })) {
    if (session.metadata?.application === 'untitled-faith' && session.metadata.intent_id === intent.id) { found = session; break; }
    if (++scanned >= 1000) throw new APIError(503, 'checkout_needs_review');
  }
  if (!found) {
    await env.DB.prepare("UPDATE checkout_intents SET status = 'expired', checked_at = ? WHERE id = ? AND status = 'creating'")
      .bind(Date.now(), intent.id).run();
    return;
  }
  validateSession(found, intent);
  await env.DB.prepare(`UPDATE checkout_intents SET session_id = ?, checkout_url = ?, status = ?, checked_at = ?
    WHERE id = ? AND status = 'creating'`)
    .bind(found.id, found.url && isStripeCheckoutURL(found.url) ? found.url : null,
      found.status === 'expired' ? 'expired' : 'open', Date.now(), intent.id).run();
}

export function validateSession(session: Stripe.Checkout.Session, intent: CheckoutIntent) {
  if (session.metadata?.application !== 'untitled-faith' || session.metadata.intent_id !== intent.id ||
      session.client_reference_id !== intent.id || session.mode !== 'payment' || session.currency !== 'usd' ||
      session.amount_total !== intent.amount_cents || session.livemode !== Boolean(intent.livemode) ||
      (intent.session_id !== null && intent.session_id !== session.id)) throw new APIError(409, 'payment_mismatch');
}

export function isStripeCheckoutURL(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname === 'checkout.stripe.com' && !url.username && !url.password && !url.port;
  } catch { return false; }
}

function checkoutResponse(intent: CheckoutIntent) {
  if (intent.status !== 'open' || !intent.checkout_url) throw new APIError(409, 'checkout_finished');
  return { intentID: intent.id, checkoutURL: intent.checkout_url, estimatedFeeCents: intent.estimated_fee_cents };
}
