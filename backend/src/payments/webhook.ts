import Stripe from 'stripe';
import { STRIPE_EVENT_TYPES } from './events';
import { APIError, isRecord } from '../http';
import { PaymentEnv, paymentConfiguration, requirePaymentEnvironment, stripeClient } from './configuration';
import { synchronizeCheckout, synchronizePaymentIntent } from './reconciliation';

type InboxEvent = { id: string; session_id: string | null; payment_intent_id: string | null; status: string };
const supported = new Set<string>(STRIPE_EVENT_TYPES);

export async function receiveStripeEvent(request: Request, env: PaymentEnv, ctx?: ExecutionContext): Promise<void> {
  const config = paymentConfiguration(env);
  await requirePaymentEnvironment(env);
  const signature = request.headers.get('Stripe-Signature');
  if (!signature || signature.length > 4096) throw new APIError(400, 'invalid_payment_signature');
  const body = await boundedWebhookBody(request.body);
  let event: Stripe.Event;
  try {
    event = await stripeClient(env).webhooks.constructEventAsync(body, signature, env.STRIPE_WEBHOOK_SECRET!,
      300, Stripe.createSubtleCryptoProvider());
  } catch { throw new APIError(400, 'invalid_payment_signature'); }
  if (event.livemode !== config.livemode) throw new APIError(400, 'payment_mode_mismatch');
  const object: unknown = event.data.object;
  let sessionID: string | null = null;
  let paymentID: string | null = null;
  if (supported.has(event.type) && isRecord(object)) {
    if (event.type.startsWith('checkout.session.')) sessionID = objectID(object.id, 'cs_');
    else if (event.type.startsWith('payment_intent.')) paymentID = objectID(object.id, 'pi_');
    else paymentID = objectID(object.payment_intent, 'pi_');
  }
  const now = Date.now();
  await env.DB.prepare(`INSERT INTO stripe_events(id, event_type, session_id, payment_intent_id, status, created_at, checked_at)
    VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`)
    .bind(event.id, event.type, sessionID, paymentID, sessionID || paymentID ? 'pending' : 'ignored', now, now).run();
  const record = await env.DB.prepare('SELECT id, session_id, payment_intent_id, status FROM stripe_events WHERE id = ?')
    .bind(event.id).first<InboxEvent>();
  if (record?.status === 'pending') {
    const processing = processEvent(env, record);
    if (ctx) {
      ctx.waitUntil(processing.catch(() => console.warn(JSON.stringify({ event: 'stripe_event_pending', stripeEventID: event.id }))));
    } else await processing;
  }
}

async function processEvent(env: PaymentEnv, event: InboxEvent): Promise<void> {
  await env.DB.prepare('UPDATE stripe_events SET attempts = attempts + 1, checked_at = ? WHERE id = ?')
    .bind(Date.now(), event.id).run();
  const handled = event.session_id ? await synchronizeCheckout(env, event.session_id) :
    event.payment_intent_id ? await synchronizePaymentIntent(env, event.payment_intent_id) : false;
  await env.DB.prepare('UPDATE stripe_events SET status = ?, checked_at = ? WHERE id = ?')
    .bind(handled ? 'processed' : 'ignored', Date.now(), event.id).run();
}

export async function retryStripeEvents(env: PaymentEnv): Promise<void> {
  try { await requirePaymentEnvironment(env); } catch { return; }
  const pending = await env.DB.prepare(`SELECT id, session_id, payment_intent_id, status FROM stripe_events
    WHERE status = 'pending' ORDER BY checked_at LIMIT 20`).all<InboxEvent>();
  for (const event of pending.results) {
    try { await processEvent(env, event); }
    catch { console.warn(JSON.stringify({ event: 'stripe_event_pending', stripeEventID: event.id })); }
  }
}

function objectID(value: unknown, prefix: string): string | null {
  const id = isRecord(value) ? value.id : value;
  return typeof id === 'string' && id.startsWith(prefix) && id.length <= 255 ? id : null;
}

async function boundedWebhookBody(body: ReadableStream<Uint8Array> | null): Promise<string> {
  if (!body) throw new APIError(400, 'invalid_request');
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 256 * 1024) { await reader.cancel(); throw new APIError(413, 'request_too_large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try { return new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes); }
  catch { throw new APIError(400, 'invalid_request'); }
}
