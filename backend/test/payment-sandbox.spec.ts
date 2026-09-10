import { env } from 'cloudflare:workers';
import { describe, expect, it } from 'vitest';
import sandbox from '../src/payments/sandbox-worker';
import type { PaymentEnv } from '../src/payments/configuration';

const sandboxEnv: PaymentEnv = { DB: env.DB, AUTH_RATE_LIMITER: env.AUTH_RATE_LIMITER,
  SESSION_SIGNING_KEY: env.SESSION_SIGNING_KEY, STRIPE_MODE: 'test', STRIPE_SECRET_KEY: 'sk_test_fixture' };

describe('isolated payment sandbox', () => {
  it('identifies itself as a sandbox', async () => {
    const response = await sandbox.fetch(new Request('https://sandbox.example/health'), sandboxEnv, {} as ExecutionContext);
    expect(await response.json()).toEqual({ status: 'ok', environment: 'stripe-sandbox' });
  });
  it('cannot run with live mode or a live credential', async () => {
    for (const configuration of [{ STRIPE_MODE: 'live' }, { STRIPE_SECRET_KEY: 'sk_live_fixture' }]) {
      const response = await sandbox.fetch(new Request('https://sandbox.example/health'), { ...sandboxEnv, ...configuration }, {} as ExecutionContext);
      expect(response.status).toBe(503);
    }
  });
  it('has no inference endpoint', async () => {
    const response = await sandbox.fetch(new Request('https://sandbox.example/v1/answers', { method: 'POST' }), sandboxEnv, {} as ExecutionContext);
    expect(response.status).toBe(404);
  });
  it('preserves authentication failures instead of turning async errors into 500s', async () => {
    const response = await sandbox.fetch(new Request('https://sandbox.example/v1/payments/configuration'), sandboxEnv, {} as ExecutionContext);
    expect(response.status).toBe(401);
  });
});
