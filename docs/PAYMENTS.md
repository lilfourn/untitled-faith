# Stripe payments and developer accounting

Updated September 10, 2026. **Live Standard Checkout and Apple Pay are enabled for the U.S. storefront.**
Luke chose Stripe Checkout with Apple Pay, custom $1–$1,000 amounts, immediate estimated credit followed
by fee reconciliation, and a **separate Untitled Faith Stripe account**. Do not use Gridbloom’s account,
credentials, webhook configuration, or payout settings. A real Stripe sandbox payment and partial/full refunds passed; no live payment was collected during verification.

## Current deployment

- Live Stripe account: `acct_1UE9yV4dOZG5zTuC` (**untitled faith**). Charges and payouts are enabled; USD settlement, Apple Pay, and cards are available and switched on.
- Live Worker: `untitled-faith-proxy`, version `0f893638-1ca3-4808-bfa7-655ce3e660e8`.
- Live webhook: `we_1UEAin4dOZG5zTuCS39GYex3`, with the event set in `backend/src/payments/events.ts`.
- Sandbox Stripe account: `acct_1UE9ya8xsUtifsc8` (**untitled faith sandbox**).
- Sandbox Worker: `untitled-faith-payments-sandbox`, version `204926b8-f6e6-482f-a6f2-90006096573c`; its isolated database is `d8c7f293-9e82-4df9-9126-d85a323657a0`.
- Sandbox webhook: `we_1UEAKv8xsUtifsc8XH7SlDcc`. Its deployment is payment-only and has no inference endpoint or production session credential.

Server secrets are in protected `.dev/stripe-live/.dev.vars` and `.dev/stripe-sandbox/.dev.vars`, and in the corresponding Worker secret bindings. The live server uses the existing standard live API key revealed from the account’s Dashboard, not the CLI credential. The CLI is logged in under project `untitled-faith`; its separate authorization expires December 9, 2026. Neither server secret was printed or embedded in the client.

The owner overview is assigned to Luke’s existing production app account by its explicit UUID. The latest TestFlight client, **1.0.6 (11)**, already includes the dynamic payment entry and overview; reopen Settings to refresh availability. No new app archive was needed for activation.

## Purchase flow

The signed-in app checks StoreKit’s current storefront and the backend’s payment availability before
showing **Settings → Add usage**. The link is available only in the U.S. storefront. Other storefronts
retain free access; expanding paid access requires a separate storefront implementation and review.
This follows [Stripe’s iOS digital-goods flow](https://docs.stripe.com/mobile/digital-goods/checkout)
and [Apple’s external-purchase-link rules](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase).

The existing amount keypad and optional 0–3% developer share are preserved. The share comes out of the
entered total. The last step explains the browser checkout and fee adjustment. The app requests a
Checkout Session from the authenticated backend, then opens only an HTTPS `checkout.stripe.com` URL
in the external browser. Stripe-hosted Checkout displays Apple Pay on supported devices and card entry
otherwise. No native Apple Pay merchant certificate or card-processing SDK is embedded in the app.

The server explicitly sends `managed_payments[enabled]=false` and `adaptive_pricing[enabled]=false`, as Luke selected Standard Checkout over the account’s Managed Payments default. Tax handling remains with the business. The server validates integer cents, the share, and a retry key; stores an immutable checkout intent; and
creates a one-time card Checkout Session. Only the opaque intent ID and app name go into Stripe metadata.
User IDs, Apple credentials, and chat data are not sent to Stripe. The buyer supplies payment information
directly to Stripe. Sessions expire after 24 hours. Retrying the same selection/key returns the same
session. Ambiguous creation timeouts are recovered through Stripe’s idempotency handling and a bounded
session lookup; an old unresolved intent is never recreated past the idempotency window.

The return page contains no payment-success assertion. Universal links and the `untitledfaith` URL scheme
only reopen the app and refresh authenticated status; neither grants funding. Signed Stripe webhooks
are saved to a durable inbox before acknowledgement. Processing uses `ctx.waitUntil`; a scheduled retry
and authenticated pending-checkout refresh cover interruptions. See [Stripe webhook guidance](https://docs.stripe.com/webhooks).

## Two separate allocations

Migration `0008_stripe_payments.sql` adds:

- `checkout_intents`: authorized amount/share, account linkage, mode, and Checkout Session.
- `stripe_payments`: latest verified charge, fee status, refunds/disputes, and current allocations.
- `payment_allocations`: append-only changes to user funding and developer share, applied atomically.
- `stripe_events`: deduplicated webhook routing identifiers and retry status. Card data is never stored.
- `payment_environment`: a database-level test/live guard. Production initializes to live mode.

For a $10 payment with a selected 3% share and a $0.59 processing fee:

| Allocation | Amount |
| --- | ---: |
| Buyer’s usage funding | $9.11 |
| Developer share | $0.30 |
| Stripe processing fee | $0.59 |
| Total | $10.00 |

The fee in this example is illustrative. When Stripe has not yet attached a balance transaction, the
server uses an explicitly provisional estimate of 2.9% rounded upward to cents plus $0.30. The signed
webhook is a trigger to retrieve current Checkout, PaymentIntent, charge, and balance-transaction data;
it is not a trusted source of client-provided amounts. Actual USD settlement fees replace the estimate.
A fee correction changes the buyer’s funding, never the selected developer percentage. Non-USD
settlement fails closed instead of treating foreign-currency amounts as dollars.

Partial refunds reduce the developer share proportionally, rounded to cents, and reduce user funding
after retained processing fees. Full refunds reverse both allocations. Disputed funding is unavailable
until Stripe reports the dispute won or closed without a loss. Already-spent refunded funds can leave a
negative user balance. Refund/dispute processing fees beyond the original charge fee are separate
business expenses and must be checked against Stripe’s financial reports; the overview is not a profit
or bank-payout statement. Deletion waits while a checkout, unconfirmed fee, or disputed payment is unresolved.

Reconciliation uses a revision captured before reading Stripe and an atomic compare-and-swap update.
Concurrent or stale updates must fetch Stripe again rather than overwrite a newer refund or fee.
The existing contribution/developer ledgers remain available for historical records and their totals
are included in the owner overview. Developer allocations never increase the owner’s personal AI balance.

## Owner overview

`PAYMENT_OWNER_ACCOUNT_ID` must be set by an operator to Luke’s **verified app account UUID**. It is not
a Stripe account ID or an Apple identifier. No account is automatically made owner based on its name,
signup order, or a client flag. Non-owners receive 403 from `GET /v1/owner/payments`.

The owner’s Settings shows **Payment overview** with user funding, developer share, remaining user
balances/reservations, confirmed and estimated processing fees, refunds, disputed amounts, monthly
allocations, and pending reconciliation counts. The API also supplies the latest 30 payments without
buyer identities. Stripe deposits combined proceeds into the merchant’s bank account; these ledgers
separate the allocations but do not initiate bank transfers or automate developer withdrawals.

## Setup and reconfiguration procedure

The separate **Untitled Faith** account is created and active. The following procedure documents how to reproduce or update the setup; it is not a list of outstanding activation blockers. Gridbloom was not modified for these payments.

1. Finish the Untitled Faith Stripe account setup and confirm USD settlement and payment/payout eligibility.
2. Put its API credential in protected `backend/.dev.vars` as `STRIPE_SECRET_KEY`. A restricted key may
   be used if it permits Checkout creation/retrieval, PaymentIntent/charge/balance-transaction/dispute
   reads, and the operator’s account/webhook inspection. Do not paste keys into chat or source code.
3. Preview the webhook operation with `node backend/scripts/configure-payment-webhook.mjs --account=acct_...`.
   After verifying the expected account, run from `backend` with
   `node --env-file=.dev.vars scripts/configure-payment-webhook.mjs --account=acct_... --apply`.
   Add `--secrets-file=/absolute/path/to/.dev.vars` when using a separate protected environment file. It creates only this app’s webhook and saves its signing secret to the protected local file; it does
   not charge anyone or deploy. An existing webhook/secret is not rotated or overwritten.
4. Set `PAYMENT_OWNER_ACCOUNT_ID` to the verified app account UUID. Confirm the mode, origin, owner ID,
   credential, webhook secret, and database all refer to the intended environment. The current production
   origin is `https://untitled-faith-proxy.vendors-c0f.workers.dev`.
5. Run the read-only check from `backend`:
   `node --env-file=.dev.vars scripts/payment-readiness.mjs --account=acct_...`.
6. Apply migrations through `0008` and deploy the tested source with remote variables retained. Provision
   Stripe secrets using Wrangler’s protected stdin/file workflow. Keep `PAYMENTS_ENABLED=false` until
   the target environment and webhook are verified. `wrangler secret put` itself deploys a version;
   coordinate it with the release rather than updating secrets incidentally.
7. Validate a real Stripe **test-mode** purchase, return to app, duplicate delivery, refund, and fee
   reconciliation against an isolated test Worker and D1 database. Explicitly set that database’s
   `payment_environment.livemode` to 0 and use only test credentials. Never switch the production database
   to test mode. Configure a test origin and matching app build for that environment.
8. Enable production only after the live account and signed webhook configuration are checked. Archive
   and distribute the client through `./scripts/dev`; verify external-browser Apple Pay on Luke’s device.
   A real payment requires the buyer’s own authorization. No simulator UI automation or iOS test suite
   is run automatically.

Production webhook: `/v1/payments/stripe/webhook`. Supported snapshot event types are centralized in
`backend/src/payments/events.ts`. The SDK and setup script target Stripe API `2026-08-26.dahlia`.
The existing 15-minute schedule retries pending events/checkouts and delayed fees and periodically
rechecks completed payments to recover missed refund/dispute notifications.

## Verification

`./scripts/dev check` passed the Bible index, TypeScript, **376 Workers tests**, two recovery-script tests,
and a deployment dry run. After explicitly disabling adaptive currency pricing, TypeScript and all 34 focused payment/sandbox tests passed again, followed by another dry run. The frozen production source matched the checked files before deployment.
Payment-specific coverage includes 30 accounting/checkout tests plus four isolation tests. The signed
client build previously passed; this activation changed backend configuration and the Checkout request.

A $10 sandbox card purchase with 3% developer thanks completed through the hosted Checkout page, where
Apple Pay was visibly offered. Authentic Stripe webhooks recorded $9.11 in usage funding, $0.30 in
developer share, and $0.59 in confirmed fees. A $5 refund changed these allocations to $4.26 and $0.15;
the remaining $5 refund returned both allocations to zero. The verification used the owner summary API
without client-side synchronization, so the updates demonstrate real webhook delivery and processing.
The failed initial Managed Payments attempt was closed after verifying Stripe had created no session.

Production health returned 200; unauthenticated payment configuration returned 401; the authenticated
owner received `enabled=true`, `isOwner=true`, and `mode=live`. A $1 live Checkout Session was created,
verified as unpaid/live/Standard Checkout, then expired through Stripe without collecting payment. Its
real expiry webhook closed the pending checkout. Final production payment and developer balances stayed
zero, with zero pending events and checkouts. Apple Pay and cards were confirmed `available=true` and
`display_preference.value=on` in the live account’s default payment-method configuration.

No real Apple Pay authorization or live charge on Luke’s phone was performed. No simulator UI automation
or iOS test suite was run for this task. Verification evidence is under `.dev/stripe-sandbox/` and
`.dev/stripe-live/`; exact release logs and source references are in `backend/DEPLOYMENT.md`.
