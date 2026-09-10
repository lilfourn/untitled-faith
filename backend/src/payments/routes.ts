import { authenticate } from '../auth';
import { requireAccount } from '../accounts';
import { APIError, isRecord, jsonResponse, readJSON } from '../http';
import { createCheckout } from './checkout';
import { checkoutEnabled, PaymentEnv, requirePaymentEnvironment } from './configuration';
import { synchronizeCheckout } from './reconciliation';
import { ownerPaymentSummary } from './summary';
import { receiveStripeEvent } from './webhook';

export async function handlePayments(request: Request, env: PaymentEnv, ctx?: ExecutionContext): Promise<Response> {
  const path = new URL(request.url).pathname;
  if (path === '/v1/payments/stripe/webhook') {
    if (request.method !== 'POST') throw new APIError(405, 'method_not_allowed');
    await receiveStripeEvent(request, env, ctx);
    return jsonResponse({ received: true });
  }
  const userID = await authenticate(request, env.SESSION_SIGNING_KEY);
  await requireAccount(env.DB, userID);
  const isOwner = Boolean(env.PAYMENT_OWNER_ACCOUNT_ID) && userID === env.PAYMENT_OWNER_ACCOUNT_ID;
  if (path === '/v1/payments/configuration' && request.method === 'GET') {
    let enabled = checkoutEnabled(env);
    if (enabled) { try { await requirePaymentEnvironment(env); } catch { enabled = false; } }
    return jsonResponse({ enabled, isOwner, mode: env.STRIPE_MODE ?? 'disabled' });
  }
  if (path === '/v1/owner/payments' && request.method === 'GET') {
    if (!isOwner) throw new APIError(403, 'forbidden');
    return jsonResponse(await ownerPaymentSummary(env.DB));
  }
  if (!(await env.AUTH_RATE_LIMITER.limit({ key: `payments:${userID}` })).success) throw new APIError(429, 'rate_limited');
  if (path === '/v1/payments/checkout' && request.method === 'POST') {
    if (request.headers.get('Content-Type')?.split(';')[0]?.trim().toLowerCase() !== 'application/json') {
      throw new APIError(415, 'invalid_request');
    }
    const body = await readJSON(request.body, 4096);
    if (!isRecord(body)) throw new APIError(400, 'invalid_request');
    return jsonResponse(await createCheckout(env, userID, request.headers.get('Idempotency-Key'), body));
  }
  if (path === '/v1/payments/pending' && request.method === 'GET') {
    const pending = await env.DB.prepare(`SELECT session_id FROM checkout_intents
      WHERE user_id = ? AND status IN ('creating', 'open') AND session_id IS NOT NULL ORDER BY created_at DESC LIMIT 3`)
      .bind(userID).all<{ session_id: string }>();
    for (const intent of pending.results) await synchronizeCheckout(env, intent.session_id);
    const results = await env.DB.prepare(`SELECT i.id, i.status, p.usage_micros AS usageMicros,
      p.developer_micros AS developerMicros, p.fee_confirmed AS feeConfirmed
      FROM checkout_intents i LEFT JOIN stripe_payments p ON p.intent_id = i.id
      WHERE i.user_id = ? ORDER BY i.created_at DESC LIMIT 10`).bind(userID).all();
    return jsonResponse({ checkouts: results.results });
  }
  throw new APIError(404, 'not_found');
}

export function paymentReturnPage(path: string): Response | null {
  if (!['/payments/return', '/payments/cancel', '/payments/open'].includes(path)) return null;
  const text = path === '/payments/cancel' ? 'Checkout closed. Return to Untitled Faith whenever you’re ready.' :
    'Return to Untitled Faith to see your balance. Usage updates after your payment is confirmed.';
  return new Response(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Untitled Faith</title><style>body{font:18px system-ui;max-width:30rem;margin:15vh auto;padding:24px;line-height:1.5;background:#f7f6f2;color:#25291e}a{color:inherit}</style>
    <h1>Untitled Faith</h1><p>${text}</p><a href="untitledfaith://payments/open">Open Untitled Faith</a></html>`, {
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
      'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' },
  });
}
