// Read-only account and webhook verification. Supply credentials through a protected env file.
import Stripe from 'stripe';
import { STRIPE_EVENT_TYPES } from '../src/payments/events.ts';

const accountID = process.argv.find(value => value.startsWith('--account='))?.slice(10);
const origin = process.env.PAYMENT_PUBLIC_ORIGIN ?? 'https://untitled-faith-proxy.vendors-c0f.workers.dev';
const key = process.env.STRIPE_SECRET_KEY;
if (!accountID || !key) {
  console.log(JSON.stringify({ ready: false, missing: [!accountID && '--account=acct_…', !key && 'STRIPE_SECRET_KEY'].filter(Boolean) }));
  process.exitCode = 1;
} else {
  try {
    const stripe = new Stripe(key, { maxNetworkRetries: 1, timeout: 15000 });
    const account = await stripe.accounts.retrieve();
    if (account.id !== accountID) throw new Error('stripe_account_mismatch');
    const endpoints = await stripe.webhookEndpoints.list({ limit: 100 });
    const endpoint = endpoints.data.find(item => item.url === `${origin}/v1/payments/stripe/webhook`);
    const missingEvents = endpoint?.enabled_events.includes('*') ? [] : STRIPE_EVENT_TYPES.filter(type => !endpoint?.enabled_events.includes(type));
    const mode = key.startsWith('sk_live_') || key.startsWith('rk_live_') ? 'live' : 'test';
    const report = { accountID: account.id, mode, chargesEnabled: account.charges_enabled,
      payoutsEnabled: account.payouts_enabled, defaultCurrency: account.default_currency,
      webhookConfigured: endpoint?.status === 'enabled', webhookModeMatches: endpoint?.livemode === (mode === 'live'),
      missingEvents, localWebhookSecretPresent: Boolean(process.env.STRIPE_WEBHOOK_SECRET),
      ownerAccountAssigned: Boolean(process.env.PAYMENT_OWNER_ACCOUNT_ID) };
    console.log(JSON.stringify(report, null, 2));
    if (!report.chargesEnabled || !report.payoutsEnabled || report.defaultCurrency !== 'usd' || !report.webhookConfigured ||
        !report.webhookModeMatches || missingEvents.length || !report.localWebhookSecretPresent || !report.ownerAccountAssigned) process.exitCode = 1;
  } catch (error) {
    // Stripe error objects can contain request details; print only the error classification.
    console.error(JSON.stringify({ ready: false, error: error?.message === 'stripe_account_mismatch' ? 'stripe_account_mismatch' : error?.type ?? 'stripe_verification_failed' }));
    process.exitCode = 1;
  }
}
