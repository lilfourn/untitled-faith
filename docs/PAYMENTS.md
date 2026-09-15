# Stripe payments and developer accounting

Updated September 13, 2026. **Live Standard Checkout and Apple Pay are enabled for the U.S. storefront.**
Luke chose Stripe Checkout with Apple Pay, custom $1–$1,000 amounts, immediate estimated credit followed
by fee reconciliation, and a **separate Untitled Faith Stripe account**. Do not use Gridbloom’s account,
credentials, webhook configuration, or payout settings. A real Stripe sandbox payment and partial/full refunds passed; no live payment was collected during verification.

## Payment activation snapshot — September 10

See [deployment status](../backend/DEPLOYMENT.md) for subsequent Worker releases and
[TestFlight history](TESTFLIGHT.md) for current client releases.

- Live Stripe account: `acct_1UE9yV4dOZG5zTuC` (**untitled faith**). Charges and payouts are enabled; USD settlement, Apple Pay, and cards are available and switched on.
- Live Worker: `untitled-faith-proxy`, version `0f893638-1ca3-4808-bfa7-655ce3e660e8`.
- Live webhook: `we_1UEAin4dOZG5zTuCS39GYex3`, with the event set in `backend/src/payments/events.ts`.
- Sandbox Stripe account: `acct_1UE9ya8xsUtifsc8` (**untitled faith sandbox**).
- Sandbox Worker: `untitled-faith-payments-sandbox`, version `204926b8-f6e6-482f-a6f2-90006096573c`; its isolated database is `d8c7f293-9e82-4df9-9126-d85a323657a0`.
- Sandbox webhook: `we_1UEAKv8xsUtifsc8XH7SlDcc`. Its deployment is payment-only and has no inference endpoint or production session credential.

Server secrets are in protected `.dev/stripe-live/.dev.vars` and `.dev/stripe-sandbox/.dev.vars`, and in the corresponding Worker secret bindings. The live server uses the existing standard live API key revealed from the account’s Dashboard, not the CLI credential. The CLI is logged in under project `untitled-faith`; its separate authorization expires December 9, 2026. Neither server secret was printed or embedded in the client.

The owner overview is assigned to Luke’s existing production app account by its explicit UUID. The latest TestFlight client, **1.0.6 (11)**, already includes the dynamic payment entry and overview; reopen Settings to refresh availability. No new app archive was needed for activation.

## Payment info

Settings → **Payment info** identifies Gridbloom as the LLC behind Untitled Faith and explains
that all payments are invoiced under Gridbloom, which appears on payment receipts. This page is
available regardless of storefront or payment availability.

## Purchase flow

The signed-in app checks StoreKit’s current storefront and the backend’s payment availability before
showing **Settings → Add usage**. The link is available only in the U.S. storefront. Other storefronts
retain free access; expanding paid access requires a separate storefront implementation and review.
This follows [Stripe’s iOS digital-goods flow](https://docs.stripe.com/mobile/digital-goods/checkout)
and [Apple’s external-purchase-link rules](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase).

The existing amount keypad and optional 0–3% developer share are preserved. The share comes out of the
entered total. Current source adds a third **Payment summary** step after the developer-share slider.
It prominently shows the estimated usage credit, with the total payment, developer share, and estimated
Stripe fee underneath. **Review payment** opens this summary; **Buy now · $amount** starts checkout.
Back navigation preserves the amount/share and recalculates the summary after edits. No Checkout
Session is created just to view the summary. This client change is built locally and is not yet in TestFlight.

The provisional client quote uses the same integer-cent rounding as the backend: 2.9% rounded upward
to cents plus $0.30. This is an estimate, not a guaranteed fee or answer count. Keep
`ContributionSelection.estimatedFeeCents` and `parseSelection` in
`backend/src/payments/configuration.ts` aligned when changing the estimate policy.
The summary explains that final fees can adjust usage credit. The app requests a
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

The **Payment overview** link was removed from Settings at Luke’s request on September 11.
The owner API remains available for operational accounting: user funding, developer share, remaining
balances/reservations, processing fees, refunds, disputes, monthly allocations, reconciliation counts,
and the latest 30 payments without buyer identities. Stripe deposits combined proceeds into the merchant’s bank account; these ledgers
separate the allocations but do not initiate bank transfers or automate developer withdrawals.

## CLI money report

Run from the repository root:

```sh
./scripts/dev money
./scripts/dev money --json
```

This reads the **live Untitled Faith account** through the installed Stripe CLI profile
`untitled-faith` and reads the production D1 ledger through project-local Wrangler. It verifies the
Stripe account ID, configured D1 database/account, USD settlement, and both live-mode markers. It uses
existing CLI logins; do not pass server keys or load `.dev.vars`. If Stripe authorization expires,
renew it with `stripe login --project-name untitled-faith` and select the separate Untitled Faith account.

The report separates:

- Usage funding after fees/refunds, paid usage consumed, and remaining positive user balances.
- Developer allocations after refunds, before business expenses, taxes, or withdrawals.
- Confirmed/estimated charge fees, refunds, free usage costs, and monthly ledger changes.
- Stripe available/pending cash and net payouts, which contain both kinds of funding.

Each run saves a dated `report.md` and `report.json` under ignored `.dev/payments/`, using private
file permissions. JSON retains exact integer micro-USD; the terminal shows up to six decimal places
when needed for usage. No buyer names, user IDs, email addresses, card details, or keys are exported.
The checked-in SELECT statement is `backend/scripts/payment-report.sql`; it captures internally
consistent ledger totals in one query. Stripe charges and balance transactions are fully paginated,
and all-time charge IDs, fees, refunds, disputes, allocation deltas, wallets, and cash are checked.
Monthly allocations use UTC adjustment dates, so an October refund reduces October's allocations
even when the payment was made in September. Saved reports capture the balance at each run.

Exit **0** means the captured records matched, **2** means a report was saved with review items, and
**1** means capture failed. Pending events, delayed fees, missing payments, unmatched cash, negative
balances, and deleted-account remainders require review. Concurrent Stripe/D1 activity can produce a
temporary difference; rerun after reconciliation. Reads never repair records, deploy, charge a buyer,
change payout settings, or transfer money.

Use usage funding for usage costs and keep outstanding user credit accounted for after Stripe pays
out to the bank. Reservations are already included in balances. Developer allocations are not a
withdrawal allowance: free AI usage, retained refund/dispute fees, other business costs, and any prior
owner withdrawals still need to be accounted for separately. The report does not read bank balances,
provider top-ups, or an owner-withdrawal ledger. A full refund can leave zero allocations and a negative
Stripe cash adjustment for retained fees; that cost is shown separately.

Stripe references checked September 13: [balance transactions](https://docs.stripe.com/api/balance_transactions/object),
[pagination](https://docs.stripe.com/api/balance_transactions/list), and
[current balances](https://docs.stripe.com/api/balance/balance_retrieve).
D1 reads use [Wrangler execute](https://developers.cloudflare.com/d1/wrangler-commands/#execute).

September 13 read-only verification matched one existing $10 live payment: $9.11 usage funding,
$0.30 developer allocation, and $0.59 confirmed fees. Paid usage consumed was $0.000091, leaving
$9.109909 in positive user balances; Stripe showed $9.41 pending and $0 available.
This inspection did not create a payment. The report's 11 regression tests use the real migrations
in in-memory SQLite and run as part of `./scripts/dev check`.
The signed client build passed with Apple sign-in and Keychain entitlements verified. No iOS test suite
or simulator UI automation was run; the new summary still needs on-device visual verification.

## Weekly Google Sheets accounting

The private [Untitled Faith Accounting sheet](https://docs.google.com/spreadsheets/d/1MILEpIm1FcYeynLgC8Y3zHr35b3FeJqMYU3HPoSrbd0/edit)
is live in Luke's personal Gmail account. Luke chose **weekly** refreshes on September 13.
The workbook contains four managed tabs:
**Balances**, **Monthly**, **Payments**, and **Stripe activity**. It shows exact micro-dollar usage,
separate developer allocations, fee/refund adjustments, and a stale-data notice after eight days.
Bank movements and developer withdrawals remain outside this report.

The updater is `backend/scripts/payment-sheets-sync.mjs`, exposed as `./scripts/dev money-sync`.
It captures the existing Stripe/D1 report, verifies the configured Google owner and private file
permissions, replaces the managed cells in one atomic Sheets request, and reads back the important
totals and timestamp before recording success. Repeated runs replace the same payment rows; they do
not append or double-count receipts. Complete reports with accounting differences are uploaded with
their review items. Failed captures keep the previous sheet data and timestamp. Add personal notes
in another tab, because the four managed tabs are replaced on refresh.

Google access uses the installed `gws` CLI. Luke's personal Gmail authorized initial workbook creation
with `drive.file` and basic identity scopes, using the separate **Untitled Faith Accounting** project
(`untitled-faith-accounting`, number `566148879765`). The Google API Services User Data Policy was
accepted with Luke's explicit approval. The old organization-only Hermes Desktop client was not changed.

Ongoing updates use `weekly-accounting-sync@untitled-faith-accounting.iam.gserviceaccount.com`, a
dedicated service account with no project-wide roles or domain delegation. It has editor access to
this spreadsheet only; Luke retains ownership. There is no public or domain-wide sharing. Its key
is in ignored `.dev/google-accounting/auth-service/key.json` with mode 0600 and its directory is 0700.
The updater verifies that the key identity/project match the local configuration and permits only
the owner and this specific writer in the file's sharing list. No notification email was sent when
granting the updater access.

This avoids using a seven-day OAuth testing token for weekly updates. The personal OAuth client stays
in Testing and is needed only for initial creation or owner-level maintenance, not scheduled runs.
Its encrypted credentials remain isolated in `.dev/google-accounting/auth`; the default Google CLI
login is preserved. Both CLI modes set `GOOGLE_APPLICATION_CREDENTIALS=/dev/null` to prevent unrelated
Google Cloud quota projects from being attached to Workspace requests. The bootstrap OAuth client
also has a blank optional `project_id`. Do not alter the default gcloud credentials to fix this.

Manual refresh and schedule inspection:

```sh
./scripts/dev money-sync
python3 scripts/payment-sheets-schedule.py --status
```

The importer saves the Google file ID/owner in ignored `.dev/google-accounting/sheet.json` and marks
the file with an app-private accounting property to recover an interrupted creation without making
duplicates, plus a non-sensitive file property that the dedicated writer can verify. Initial import
uses `money-sync --create <verified.xlsx> --account <owner-email>` with the owner's isolated OAuth
login. Configure the service-account writer and its key before scheduling. The scheduler refuses
installation until a successful sync receipt from that exact writer exists. It installs only
`com.lukefournier.untitled-faith-accounting`, for **Monday at 9 AM local Mac time**, with catch-up after
sleep or login. Scheduled invocations skip an already completed week. Internet and valid Stripe,
Cloudflare, and Google logins are required; a failed offline run can be retried with `money-sync`.

Use `python3 scripts/payment-sheets-schedule.py --status` to inspect the job. Logs and the latest
verified receipt are under `.dev/google-accounting/`; no API secrets or raw Google responses are
logged by the updater. Stripe's CLI login may need renewal when it expires. The importer currently
fails without changing cells if a single update exceeds 180 KB; extend its batching before growing
beyond that boundary. It stops if sharing is widened beyond the owner and dedicated writer, pending
operator review. Stripe's CLI authorization was documented to expire December 9, 2026; renew that
login when needed. The spreadsheet displays a notice if no successful update has occurred for eight days.

Initial local verification: four rendered tabs, no workbook formula errors, and five updater tests
covering money precision, repeated refreshes, removal of obsolete rows, formula injection, weekly
timing, and Google readback. Native creation and two service-account refreshes succeeded without
duplicating the one payment. The last verified capture at `2026-09-14T00:57:19.878Z` matched $9.11 in
usage funding, $0.30 in developer allocation, $0.59 in confirmed fees, and $9.081593 in remaining user
credit. The Google API scan found zero formula errors across all four tabs, and native layouts were
visually inspected. The installed launchd job reported exit 0; its initial invocation correctly
skipped another refresh because the current weekly snapshot was already complete.
`./scripts/dev check` passed the index check, TypeScript, 397 Workers tests, two recovery tests,
11 report tests, five Sheets tests, and deployment dry run. Logs use suffix `20260913-173949-79536`
for backend tests and `20260913-174013-79536` for the report/Sheets checks and dry run.

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
