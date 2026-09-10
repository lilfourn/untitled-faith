// Creates only the named app's webhook. It never charges, changes bank details, or deploys the Worker.
// Usage: node --env-file=.dev.vars scripts/configure-payment-webhook.mjs --account=acct_... --apply
import Stripe from 'stripe';
import { chmod, readFile, writeFile, rename } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { STRIPE_EVENT_TYPES } from '../src/payments/events.ts';

const accountID = process.argv.find(value => value.startsWith('--account='))?.slice(10);
const apply = process.argv.includes('--apply');
const secretFile = process.argv.find(value => value.startsWith('--secrets-file='))?.slice(15);
const secretPath = secretFile ? resolve(secretFile) : fileURLToPath(new URL('../.dev.vars', import.meta.url));
const origin = new URL(process.env.PAYMENT_PUBLIC_ORIGIN ?? 'https://untitled-faith-proxy.vendors-c0f.workers.dev');
const url = `${origin.origin}/v1/payments/stripe/webhook`;
if (origin.protocol !== 'https:' || origin.username || origin.password || origin.pathname !== '/' || origin.search || origin.hash) {
  throw new Error('invalid_payment_origin');
}
if (!apply) {
  console.log(JSON.stringify({ action: 'create Untitled Faith Stripe webhook if absent', accountID: accountID ?? null,
    url, events: STRIPE_EVENT_TYPES, writesSecretTo: secretPath, apply: false }, null, 2));
} else {
  if (!accountID || !process.env.STRIPE_SECRET_KEY) throw new Error('An expected account ID and STRIPE_SECRET_KEY are required');
  try {
    const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, { maxNetworkRetries: 1, timeout: 15000 });
    if ((await stripe.accounts.retrieve()).id !== accountID) throw new Error('stripe_account_mismatch');
    const endpoints = await stripe.webhookEndpoints.list({ limit: 100 });
    const existing = endpoints.data.find(endpoint => endpoint.url === url);
    if (existing) {
      console.log(JSON.stringify({ created: false, endpointID: existing.id, status: existing.status,
        localSigningSecretPresent: Boolean(process.env.STRIPE_WEBHOOK_SECRET) }));
      if (!process.env.STRIPE_WEBHOOK_SECRET) process.exitCode = 1;
    } else {
      const endpoint = await stripe.webhookEndpoints.create({ url, enabled_events: [...STRIPE_EVENT_TYPES],
        api_version: '2026-08-26.dahlia', description: 'Untitled Faith payment confirmations and reconciliation',
        metadata: { application: 'untitled-faith' } }, { idempotencyKey: `faith-webhook-${accountID}-${Buffer.from(url).toString('base64url')}` });
      if (!endpoint.secret) throw new Error('webhook_secret_missing');
      const path = secretPath;
      // Read immediately before writing to preserve other agents' additions. Never print the file or secret.
      const current = await readFile(path, 'utf8');
      if (/^STRIPE_WEBHOOK_SECRET=/m.test(current)) throw new Error('Existing webhook secret must be reconciled without rotation');
      const temporary = `${path}.${randomUUID()}.tmp`;
      await writeFile(temporary, `${current.trimEnd()}\nSTRIPE_WEBHOOK_SECRET=${endpoint.secret}\n`, { mode: 0o600, flag: 'wx' });
      if (await readFile(path, 'utf8') !== current) throw new Error('Secret file changed concurrently; recover the new webhook secret from Stripe');
      await rename(temporary, path);
      await chmod(path, 0o600);
      console.log(JSON.stringify({ created: true, endpointID: endpoint.id, localSecretSaved: true, deployed: false }));
    }
  } catch (error) {
    console.error(JSON.stringify({ configured: false, error: error?.type ?? 'webhook_setup_failed' }));
    process.exitCode = 1;
  }
}
