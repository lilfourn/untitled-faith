# Accounts, usage, and personal funding

September 9, 2026. This supersedes the earlier proposal that contributions expand everybody's shared allowance: the user chose **personal usage funding equal to net proceeds after fees**. The owner continues to cover at most $100/month total for free access and overhead.

The Cloudflare D1 database is `untitled-faith-users`, bound as `DB`. Accounts are created only after verified Apple credential exchange. A hashed Apple identity resolves to a random account ID and a stable purchase-account UUID. The optional `users.first_name` stores only the given name captured at Apple sign-in, not a family name or email. Apple credentials, questions, and answers are not stored in D1. Migration 0004 adds this nullable field without changing existing accounts or funding. Both answer paths load the name using the authenticated account ID, include it as profile data in the system prompt and cost reservation, and use no name when it is absent. Account deletion removes the saved name with the account.

## Enforcement

- Free allowance: 30 requests per UTC calendar month, usable on any day, subject to the shared monthly pool. There is no daily cap.
- Shared free pool: $63.30/month of cash-equivalent service spending, representing $60 of inference plus the 5.5% credit-acquisition fee. The remainder of the owner's $100 plan is membership, hosting, and reserves. This is a limit on the free pool, not unlimited coverage for refunds or new infrastructure costs.
- When free allowance or shared capacity is exhausted, use only that account's contributed funding. If it cannot reserve enough for the request, return HTTP 402 with the monthly allowance, shared-pool, or insufficient-funding reason before inference.
- Contribution usage credit is gross proceeds less verified payment fees and any explicitly chosen developer thanks. The optional developer share is 0–3% of the original contribution, rounded to cents, and defaults to zero. It comes out of the total, never on top. Usage funding does not expire or reset with the free month. Compute has no profit markup.
- Money uses integer micro-USD, never floating-point balances. SQL triggers check and reserve funds atomically; concurrent requests cannot double-spend. Only one request may be actively generating per account.
- Every answer requires a stable `Idempotency-Key`. Repeating it cannot trigger another paid generation. Answers themselves are not stored for replay.

The response cost is measured, not assumed to be two cents. A conservative request reservation uses UTF-8 input size plus system/framing allowance, the output-token cap, and routing price ceilings. The provider request enforces maximum prompt/completion rates. The byte estimate is deliberately conservative, but is not a provider-certified tokenizer count; use the provider key spending limit as a separate operational backstop. Unused reservation is released after settlement; an unexpectedly higher reported cost is recorded in full and can make a paid balance negative, blocking further paid use.

## Accounting and refunds

`users` holds identity mapping and available/reserved funding. `usage_requests` is the monthly/daily usage ledger, with token counts and actual costs. `free_months` enforces the global monthly reserve. `contributions` and `wallet_entries` record funding and debits, including reversals. `contribution_reversals` prevents late purchase notifications from re-crediting an already-refunded transaction.

Migration 0003 records `developer_share_bps` and `developer_share_micros` on each contribution, with a separate `developer_entries` ledger. Payment fees are deducted from the usage portion, so a $10 contribution at 3% and $1.50 in verified fees allocates $0.30 to the developer and $8.20 to usage. Refunds reverse both allocations once. Existing contributions default to a zero developer share. See [the contribution wizard](CONTRIBUTIONS.md).

The trusted `creditContribution` boundary rejects duplicate ownership claims and credits a payment only once. `reverseContribution` reverses funding once; spending before a refund can leave a negative balance. Neither function is exposed as a client-writable endpoint. **The payment checkout and server payment-verification adapter are not connected in this step.** The database can support either a verified App Store purchase or a verified Stripe Apple Pay settlement. Do not enable purchases or manually assume net amounts from untrusted client receipts.

Apple built-in In-App Purchase was recommended for this digital-usage product after the user asked whether Apple could handle payments directly. The user had previously selected Stripe/Apple Pay; a final switch to Apple IAP has not yet been confirmed. No Stripe checkout or StoreKit purchase button was added. Actual net proceeds, storefront taxes, processor fees, refunds, and account ownership must be verified by the selected adapter before it calls the credit boundary.

## Interrupted requests

Known pre-inference rejections release the reservation. Chargeable failures with valid usage metadata settle their real cost. Timeouts, transport errors, and missing usage metadata retain the reservation rather than guessing they were free.

A cron every 15 minutes checks uncertain requests with a provider generation ID against OpenRouter's generation metadata and settles confirmed charges. Stale in-progress requests become uncertain after five minutes so the account can continue using remaining allowance/funding. Requests with no generation ID need operator investigation; their money stays reserved. No prompt or response content is fetched for reconciliation.

## App display

`GET /v1/me/usage` returns only the authenticated account's summary. Settings shows a single usage
progress bar and percentage, without daily/monthly counts, reset notices, or pending-request details.
The monthly allowance can be used entirely in one day. Older clients still receive compatible daily
fields, but their remaining-today value equals the entire remaining monthly allowance and their reset
is the monthly reset. Migration `0006_monthly_only_allowance.sql` removes the database's daily check;
the historical `free_daily_limit` ledger column is no longer enforced.

For a single bar covering both free questions and personal funding, the percentage is a display-only normalization: each free question has the planning weight of $0.02 plus the 5.5% acquisition fee; paid funding uses its actual available value. The denominator includes the month's starting paid balance, net added funding, and the full free allowance. The percentage is approximate; it never authorizes spending, bypasses monthly limits, or guarantees the shared pool remains available.

## Account deletion

Deletion locks the account against new requests/contributions, revokes Apple authorization, removes the identity mapping, and unlinks retained financial records. Outstanding positive funding and unsettled requests must first be resolved to avoid silently losing paid value. If Apple revocation fails, the lock is released for retry. A production refund/deletion support flow remains necessary before accepting payments.

## Operations

From `backend`:

```sh
npm run types
npm run check
npm test
npx wrangler d1 migrations apply untitled-faith-users --local
npx wrangler d1 migrations apply untitled-faith-users --remote
npm run deploy:check
npm run deploy
```

`npm run session:dev` creates a local development account and prints its short-lived session. Use `npm run session:dev -- --remote` only when intentionally testing the deployed database. Set `FAITH_USER_ID` to an existing account UUID to reuse it. Never put the signing secret in an Xcode scheme.

Existing sessions issued before persistent accounts were added must sign in again. No existing user database was migrated; this is the first account database.

Sources: [D1 transactional batches](https://developers.cloudflare.com/d1/worker-api/d1-database/), [OpenRouter price ceilings](https://openrouter.ai/docs/guides/routing/provider-selection), [generation accounting](https://openrouter.ai/docs/api/api-reference/generations/get-generation).
