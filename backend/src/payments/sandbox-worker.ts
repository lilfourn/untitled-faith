// Dedicated payment verification deployment. It cannot accept live keys or call inference providers.
// Test sessions are issued locally by the operator, never by an unauthenticated HTTP endpoint.
import { authenticate } from '../auth';
import { APIError, jsonResponse } from '../http';
import { usageSummary } from '../usage';
import { PaymentEnv } from './configuration';
import { handlePayments, paymentReturnPage } from './routes';
import { reconcilePayments } from './reconciliation';
import { retryStripeEvents } from './webhook';

function sandboxOnly(env: PaymentEnv) {
  if (env.STRIPE_MODE !== 'test' || !/^(sk|rk)_test_/.test(env.STRIPE_SECRET_KEY ?? '')) {
    throw new APIError(503, 'sandbox_not_configured');
  }
}

export default {
  async scheduled(_controller, env): Promise<void> {
    sandboxOnly(env);
    await retryStripeEvents(env);
    await reconcilePayments(env);
  },
  async fetch(request, env, ctx): Promise<Response> {
    try {
      sandboxOnly(env);
      const path = new URL(request.url).pathname;
      if (path === '/health' && request.method === 'GET') return jsonResponse({ status: 'ok', environment: 'stripe-sandbox' });
      if (request.method === 'GET') {
        const page = paymentReturnPage(path);
        if (page) return page;
      }
      if (path === '/v1/me/usage' && request.method === 'GET') {
        const userID = await authenticate(request, env.SESSION_SIGNING_KEY);
        return jsonResponse(await usageSummary(env.DB, userID));
      }
      if (path.startsWith('/v1/payments/') || path === '/v1/owner/payments') return await handlePayments(request, env, ctx);
      throw new APIError(404, 'not_found');
    } catch (error) {
      const failure = error instanceof APIError ? error : new APIError(500, 'internal_error');
      return jsonResponse({ error: { code: failure.code } }, failure.status);
    }
  },
} satisfies ExportedHandler<PaymentEnv>;
