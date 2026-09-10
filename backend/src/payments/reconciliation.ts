import type Stripe from 'stripe';
import { APIError } from '../http';
import { CheckoutIntent, provisionCheckout, validateSession } from './checkout';
import { PaymentEnv, paymentConfiguration, requirePaymentEnvironment, stripeClient } from './configuration';

type Payment = { id: string; revision: number; intent_id: string };
export type PaymentSnapshot = {
  id: string; chargeID: string; grossCents: number; feeCents: number; feeConfirmed: boolean;
  refundedCents: number; disputed: boolean; disputeOpen: boolean; usageMicros: number; developerMicros: number;
};

export function allocation(grossCents: number, feeCents: number, refundedCents: number, shareBps: number, disputed: boolean) {
  if (![grossCents, feeCents, refundedCents, shareBps].every(Number.isSafeInteger) || grossCents < 100 ||
      grossCents > 100_000 || feeCents < 0 || feeCents > 100_000 || refundedCents < 0 || refundedCents > grossCents ||
      shareBps < 0 || shareBps > 300) throw new APIError(409, 'payment_mismatch');
  const remaining = disputed ? 0 : grossCents - refundedCents;
  const net = Math.max(0, remaining - feeCents);
  const developerCents = Math.min(net, Math.floor((remaining * shareBps + 5000) / 10_000));
  return { usageMicros: (net - developerCents) * 10_000, developerMicros: developerCents * 10_000 };
}

export async function synchronizeCheckout(env: PaymentEnv, sessionID: string, stripe = stripeClient(env)): Promise<boolean> {
  await requirePaymentEnvironment(env);
  for (let attempt = 0; attempt < 4; attempt++) {
    // Capture the revision BEFORE the remote reads. A concurrent update forces a fresh read from Stripe.
    const existing = await env.DB.prepare(`SELECT p.id, p.revision, p.intent_id FROM stripe_payments p
      JOIN checkout_intents i ON i.id = p.intent_id WHERE i.session_id = ?`).bind(sessionID).first<Payment>();
    const session = await stripe.checkout.sessions.retrieve(sessionID);
    if (session.metadata?.application !== 'untitled-faith') return false;
    const intent = await env.DB.prepare('SELECT * FROM checkout_intents WHERE id = ?')
      .bind(session.metadata.intent_id ?? '').first<CheckoutIntent>();
    if (!intent) throw new APIError(409, 'payment_intent_missing');
    if (Boolean(intent.livemode) !== paymentConfiguration(env).livemode) throw new APIError(409, 'payment_mode_mismatch');
    validateSession(session, intent);
    if (!intent.session_id) {
      await env.DB.prepare('UPDATE checkout_intents SET session_id = ? WHERE id = ? AND session_id IS NULL')
        .bind(session.id, intent.id).run();
    }
    if (session.status === 'expired') {
      await env.DB.prepare("UPDATE checkout_intents SET status = 'expired', checked_at = ? WHERE id = ? AND status != 'paid'")
        .bind(Date.now(), intent.id).run();
      return true;
    }
    if (session.payment_status !== 'paid' || session.status !== 'complete') {
      await env.DB.prepare('UPDATE checkout_intents SET checked_at = ? WHERE id = ?').bind(Date.now(), intent.id).run();
      return true;
    }
    const paymentID = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id;
    if (!paymentID) throw new APIError(409, 'payment_mismatch');
    const pi = await stripe.paymentIntents.retrieve(paymentID, { expand: ['latest_charge.balance_transaction'] });
    const snapshot = await snapshotFromStripe(stripe, pi, intent);
    if (existing && existing.id !== snapshot.id) throw new APIError(409, 'payment_mismatch');
    const changed = await saveSnapshot(env.DB, intent, snapshot, existing?.revision ?? null);
    if (!changed) continue;
    await env.DB.prepare("UPDATE checkout_intents SET status = 'paid', checked_at = ? WHERE id = ?")
      .bind(Date.now(), intent.id).run();
    return true;
  }
  throw new APIError(503, 'payment_busy');
}

async function snapshotFromStripe(stripe: Stripe, pi: Stripe.PaymentIntent, intent: CheckoutIntent): Promise<PaymentSnapshot> {
  if (pi.metadata.application !== 'untitled-faith' || pi.metadata.intent_id !== intent.id ||
      pi.status !== 'succeeded' || pi.currency !== 'usd' || pi.amount !== intent.amount_cents ||
      pi.amount_received !== intent.amount_cents || pi.livemode !== Boolean(intent.livemode)) throw new APIError(409, 'payment_mismatch');
  const charge = pi.latest_charge;
  if (!charge || typeof charge === 'string' || !charge.paid || !charge.captured || charge.status !== 'succeeded' ||
      charge.currency !== 'usd' || charge.amount !== intent.amount_cents || charge.livemode !== Boolean(intent.livemode) ||
      charge.payment_intent !== pi.id) throw new APIError(409, 'payment_mismatch');
  const balance = charge.balance_transaction;
  if (typeof balance === 'string') throw new APIError(503, 'payment_fee_pending');
  // Never treat non-USD settlement amounts as USD. Configure the Stripe account to settle USD.
  if (balance && (balance.currency !== 'usd' || balance.amount !== charge.amount ||
      balance.net !== balance.amount - balance.fee)) throw new APIError(409, 'payment_currency_mismatch');
  const fee = balance?.fee ?? intent.estimated_fee_cents;
  let disputed = false;
  let disputeOpen = false;
  if (charge.disputed) {
    const disputes = await stripe.disputes.list({ charge: charge.id, limit: 100 });
    if (disputes.has_more || disputes.data.length === 0) throw new APIError(503, 'dispute_status_pending');
    disputed = disputes.data.some(dispute => !['won', 'warning_closed'].includes(dispute.status));
    disputeOpen = disputes.data.some(dispute => !['won', 'lost', 'warning_closed'].includes(dispute.status));
  }
  return { id: pi.id, chargeID: charge.id, grossCents: charge.amount, feeCents: fee,
    feeConfirmed: Boolean(balance), refundedCents: charge.amount_refunded, disputed, disputeOpen,
    ...allocation(charge.amount, fee, charge.amount_refunded, intent.developer_share_bps, disputed) };
}

export async function saveSnapshot(db: D1Database, intent: CheckoutIntent, snapshot: PaymentSnapshot, expectedRevision: number | null): Promise<boolean> {
  const expected = allocation(snapshot.grossCents, snapshot.feeCents, snapshot.refundedCents, intent.developer_share_bps, snapshot.disputed);
  if (snapshot.grossCents !== intent.amount_cents || snapshot.usageMicros !== expected.usageMicros ||
      snapshot.developerMicros !== expected.developerMicros) throw new APIError(409, 'payment_mismatch');
  // SQL triggers apply the user and developer deltas in the same transaction as this snapshot.
  const now = Date.now();
  if (expectedRevision === null) {
    const result = await db.prepare(`INSERT INTO stripe_payments
      (id, intent_id, user_id, charge_id, gross_cents, fee_cents, fee_confirmed, refunded_cents, disputed, dispute_open,
       usage_micros, developer_micros, created_at, checked_at)
      SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS
        (SELECT 1 FROM users WHERE id = ? AND deleting_at IS NULL)
      ON CONFLICT DO NOTHING RETURNING id`)
      .bind(snapshot.id, intent.id, intent.user_id, snapshot.chargeID, snapshot.grossCents, snapshot.feeCents,
        Number(snapshot.feeConfirmed), snapshot.refundedCents, Number(snapshot.disputed), Number(snapshot.disputeOpen), snapshot.usageMicros,
        snapshot.developerMicros, now, now, intent.user_id).first();
    return result !== null;
  }
  const result = await db.prepare(`UPDATE stripe_payments SET fee_cents = ?, fee_confirmed = ?, refunded_cents = ?,
    disputed = ?, dispute_open = ?, usage_micros = ?, developer_micros = ?, revision = revision + 1, checked_at = ?
    WHERE id = ? AND intent_id = ? AND charge_id = ? AND gross_cents = ? AND revision = ?
      AND (fee_confirmed = 0 OR ? = 1) RETURNING id`)
    .bind(snapshot.feeCents, Number(snapshot.feeConfirmed), snapshot.refundedCents, Number(snapshot.disputed),
      Number(snapshot.disputeOpen),
      snapshot.usageMicros, snapshot.developerMicros, now, snapshot.id, intent.id, snapshot.chargeID,
      snapshot.grossCents, expectedRevision, Number(snapshot.feeConfirmed)).first();
  return result !== null;
}

export async function synchronizePaymentIntent(env: PaymentEnv, paymentID: string): Promise<boolean> {
  const stripe = stripeClient(env);
  const payment = await stripe.paymentIntents.retrieve(paymentID);
  if (payment.metadata.application !== 'untitled-faith') return false;
  const intent = await env.DB.prepare('SELECT * FROM checkout_intents WHERE id = ?')
    .bind(payment.metadata.intent_id ?? '').first<CheckoutIntent>();
  if (!intent?.session_id) throw new APIError(503, 'checkout_pending');
  return synchronizeCheckout(env, intent.session_id, stripe);
}

export async function reconcilePayments(env: PaymentEnv): Promise<void> {
  try { await requirePaymentEnvironment(env); } catch { return; }
  const pending = await env.DB.prepare(`SELECT * FROM checkout_intents WHERE status IN ('creating', 'open')
    AND checked_at < ? ORDER BY checked_at LIMIT 20`).bind(Date.now() - 60_000).all<CheckoutIntent>();
  for (const intent of pending.results) {
    try {
      // Mark attempts even on failure so one broken item cannot starve other payments.
      await env.DB.prepare('UPDATE checkout_intents SET checked_at = ? WHERE id = ?').bind(Date.now(), intent.id).run();
      if (intent.session_id) await synchronizeCheckout(env, intent.session_id);
      else await provisionCheckout(env, intent);
    } catch { console.warn(JSON.stringify({ event: 'checkout_reconciliation_pending', intentID: intent.id })); }
  }
  const payments = await env.DB.prepare(`SELECT p.id, i.session_id FROM stripe_payments p JOIN checkout_intents i ON i.id = p.intent_id
    WHERE p.checked_at < ? OR (p.fee_confirmed = 0 AND p.checked_at < ?)
    ORDER BY p.checked_at LIMIT 20`).bind(Date.now() - 24 * 60 * 60_000, Date.now() - 60_000)
    .all<{ id: string; session_id: string }>();
  for (const payment of payments.results) {
    try {
      await env.DB.prepare('UPDATE stripe_payments SET checked_at = ? WHERE id = ?').bind(Date.now(), payment.id).run();
      await synchronizeCheckout(env, payment.session_id);
    } catch { console.warn(JSON.stringify({ event: 'payment_reconciliation_pending', paymentID: payment.id })); }
  }
}
