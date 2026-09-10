import Stripe from 'stripe';
import { APIError } from '../http';

type PaymentConfiguration = {
  PAYMENTS_ENABLED?: string;
  STRIPE_MODE?: string;
  STRIPE_SECRET_KEY?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  PAYMENT_PUBLIC_ORIGIN?: string;
  PAYMENT_OWNER_ACCOUNT_ID?: string;
};
export type PaymentEnv = Pick<Env, 'DB' | 'SESSION_SIGNING_KEY' | 'AUTH_RATE_LIMITER'> & PaymentConfiguration;

export function paymentConfiguration(env: PaymentEnv) {
  const livemode = env.STRIPE_MODE === 'live';
  if (!['live', 'test'].includes(env.STRIPE_MODE ?? '') ||
      !new RegExp(`^(sk|rk)_${livemode ? 'live' : 'test'}_`).test(env.STRIPE_SECRET_KEY ?? '') ||
      !env.STRIPE_WEBHOOK_SECRET?.startsWith('whsec_')) throw new APIError(503, 'payments_not_configured');
  let origin: URL;
  try { origin = new URL(env.PAYMENT_PUBLIC_ORIGIN ?? ''); }
  catch { throw new APIError(503, 'payments_not_configured'); }
  if (origin.protocol !== 'https:' || origin.username || origin.password || origin.pathname !== '/' || origin.search || origin.hash) {
    throw new APIError(503, 'payments_not_configured');
  }
  return { livemode, origin: origin.origin };
}

export function stripeClient(env: PaymentEnv): Stripe {
  paymentConfiguration(env);
  return new Stripe(env.STRIPE_SECRET_KEY!, {
    httpClient: Stripe.createFetchHttpClient(), maxNetworkRetries: 2, timeout: 15_000,
    appInfo: { name: 'Untitled Faith' },
  });
}

export async function requirePaymentEnvironment(env: PaymentEnv): Promise<void> {
  const config = paymentConfiguration(env);
  const row = await env.DB.prepare('SELECT livemode FROM payment_environment WHERE id = 1').first<{ livemode: number }>();
  if (!row || Boolean(row.livemode) !== config.livemode) throw new APIError(503, 'payment_mode_mismatch');
}

export function checkoutEnabled(env: PaymentEnv): boolean {
  if (env.PAYMENTS_ENABLED !== 'true') return false;
  try { paymentConfiguration(env); return true; } catch { return false; }
}

export function parseSelection(value: Record<string, unknown>) {
  const amount = value.amountCents;
  const share = value.developerShareBasisPoints;
  if (Object.keys(value).some(key => !['amountCents', 'developerShareBasisPoints', 'storefront'].includes(key)) ||
      typeof amount !== 'number' || !Number.isSafeInteger(amount) || amount < 100 || amount > 100_000 ||
      typeof share !== 'number' || !Number.isSafeInteger(share) || share < 0 || share > 300) {
    throw new APIError(400, 'invalid_contribution');
  }
  if (value.storefront !== 'USA') throw new APIError(403, 'checkout_region_unavailable');
  // An estimate only; the charge's balance transaction replaces this after settlement.
  const estimatedFeeCents = Math.ceil(amount * 290 / 10_000) + 30;
  return { amountCents: amount, developerShareBasisPoints: share, estimatedFeeCents };
}
