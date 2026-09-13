# Security audit — September 13, 2026

The review confirmed **four medium-severity findings and one low-severity finding**. No high or critical vulnerability was confirmed. The main risks are persistent access after session-token theft and abuse of shared service capacity. Findings remain open; this audit did not change application behavior or deploy anything.

## Scope and evidence

Reviewed the current working tree on `main`, including uncommitted changes, based on commit `0593129745cb9d4c4a26aa5add19db4a484e17a5`. Coverage included Apple authentication, JWT/JWE handling, account isolation/deletion, D1 accounting triggers, Stripe checkout/webhooks/reconciliation, inference boundaries, source rendering, iOS networking/storage, secrets, dependencies, and CI/deployment configuration. Concurrent UI edits were present; this is a review of the inspected files, not certification of every future change or the deployed binary.

Validation completed:

- `./scripts/dev check`: passed Bible-index verification, backend TypeScript checks, **379 Workers tests**, **2 recovery-script tests**, and the deployment dry run.
- Six additional local audit probes: **6 passed**, reproducing the five findings below. Passing means the vulnerable behavior was reproduced, not that a fix passed. Apple, Stripe, ESV, and other outbound calls were mocked; D1 ran locally with the actual migrations.
- `npm audit --json --ignore-scripts`: **0 known npm vulnerabilities** across 184 dependencies. This does not assess unknown vulnerabilities or Swift package advisories.
- Targeted credential-pattern scan: no matches in 209 current text files or 491 unique text blobs reachable through 88 local Git commits. This is a heuristic scan, not an exhaustive secret detector. `backend/.dev.vars` is ignored and has mode `0600`; its values were not printed.
- Bounded live checks using curl: `/health` returned 200; unauthenticated usage, readiness, owner payments, payment configuration, and answers returned 401; a bogus refresh envelope returned 401; an unsigned webhook returned 400. An initial urllib attempt returned uniform 403 responses, so those responses were not treated as application validation.

No simulator automation or iOS test run was performed, consistent with `AGENTS.md`. No live authenticated exploitation, charges, paid inference, production data inspection, or secret rotation occurred. The live checks do not establish that deployed code matches the reviewed tree. Cloudflare dashboard rules, Apple notification configuration, provider spending limits, and Stripe account fraud settings were not independently audited.

Local evidence, excluded from Git:

- `.dev/logs/backend-tests-20260913-163346-71988.log`
- `.dev/logs/recovery-script-tests-20260913-163423-71988.log`
- `.dev/logs/backend-bundle-20260913-163423-71988.log`
- `.dev/logs/security-audit-probes-20260913.log`
- `.dev/security-audit/security-audit.local.spec.ts`
- `.dev/security-audit/source-snapshot.json`
- `.dev/security-audit/live-checks.json`

To rerun the audit probes locally, copy the preserved spec to `backend/test/security-audit.local.spec.ts` without overwriting an existing file, run `npm --prefix backend test -- test/security-audit.local.spec.ts`, then remove only that temporary copy. The spec intentionally asserts the current gaps and should not become a permanent regression suite without changing those expectations.

## Findings

### 1. Medium — Refresh credentials cannot be invalidated by signing out

**Locations:** `backend/src/apple-auth.ts:86`, `backend/src/apple-auth.ts:120`, `Untitled Faith/App/AppSession.swift:288`.

Refresh envelopes are encrypted and expire after a fixed 30 days, but the server keeps no session identifier, consumed-token record, or revocation state. Refresh issues a different envelope while continuing to accept the previous one. The native sign-out path only clears local state and Keychain; `/v1/auth/revoke` is account deletion, not session logout.

**Impact:** An attacker who obtains a refresh envelope can keep minting access tokens after the user signs out, for the remainder of the 30-day session while Apple authorization remains valid. Access includes spending the victim's available AI allowance/funding and reading account usage; server-side conversation history is not exposed because it is not stored there. This requires token theft first; the audit found no token-exfiltration path. Apple revocation is checked during refresh after the daily interval, so local sign-out is not an immediate server-side containment mechanism.

**Reproduction:** `AUDIT-1` signs in through mocked Apple verification, refreshes once, then replays the original envelope. Both refresh calls return 200, and the replayed access token successfully reads `/v1/me/usage`. The absence of a server call on sign-out was verified statically.

**Fix:** Store a revocable session/refresh-token family, invalidate consumed refresh credentials atomically, detect reuse, and provide a logout endpoint that revokes the session without deleting the account. Preserve reliable retries and concurrent-refresh behavior explicitly. Support account-wide session invalidation for external revocation. OAuth security guidance calls for rotation or sender-constrained refresh tokens for public clients. This applies to the app's own refresh envelope; Apple's daily token check can remain separate. [RFC 9700 §4.14](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14), [Apple user verification](https://developer.apple.com/documentation/signinwithapple/verifying-a-user).

### 2. Medium — Account recreation resets an exhausted monthly free allowance

**Locations:** `backend/src/accounts.ts:9`, `backend/src/accounts.ts:44`, `backend/migrations/0001_accounts_and_usage.sql:23`, `backend/migrations/0006_monthly_only_allowance.sql:12`.

Deletion removes the Apple identity mapping and sets historical usage rows' `user_id` to NULL. A subsequent sign-in with the same Apple identity creates a fresh random account ID. The monthly allowance counts only rows belonging to that new ID, giving the same person another 30 free requests.

**Impact:** A user with settled usage and no positive balance can repeatedly delete and reauthorize the same Apple account to bypass the personal monthly cap and consume the shared free pool. The global monthly spending ledger survives deletion, so this does **not** bypass its $63.30 cap or create unlimited inference spending. It can deny other users their free access.

**Reproduction:** `AUDIT-2` exhausts 30 reservations, confirms the next request is rejected with `monthly_free_limit`, deletes through `/v1/auth/revoke`, and signs in with the same mocked Apple identity. The new account has 30 remaining requests and can reserve free usage again. The old 30 records are unlinked, while global spending remains recorded.

**Fix:** Enforce the monthly allowance independently of the disposable account ID. One option is a minimal, expiring, keyed identity/month allowance record that survives account deletion until the month ends. Document its retention and avoid retaining profile data or chat content. Test deletion/recreation and concurrent sign-ins against the same allowance record.

### 3. Medium — ESV quota is shared globally but limited only per user

**Locations:** `backend/src/esv.ts:47`, `backend/src/index.ts:77`, `backend/wrangler.jsonc:25`.

When ESV is configured, both verse cards and answer grounding consume the same provider key. The only application quota is 20 requests per minute per user. There is no shared minute/hour/day budget. Answer grounding also calls ESV before usage reservation rejects exhausted, duplicate, or conflicting answer requests.

**Impact:** A few valid accounts can consume the application's provider quota and cause ESV requests to be throttled for everyone. Crossway documents limits of 60/minute, 1,000/hour, and 5,000/day. Four accounts at the permitted rate can send 80/minute; even one account's 20/minute allowance exceeds the hourly limit if sustained. The bundled Bible fallback limits the outage's scope, but ESV verse retrieval is affected. [Crossway API limits](https://api.esv.org/).

**Reproduction:** `AUDIT-3a` makes 80 successful local passage requests across four accounts while enforcing the configured 20-per-user cap. `AUDIT-3b` confirms that an exhausted account triggers an ESV fetch before the answer endpoint returns 402. No actual provider requests were sent.

**Fix:** Add a shared quota at the provider-call boundary, with per-user limits for fairness. Account for minute, hour, and day limits, and skip ESV work for requests already known to be ineligible or duplicated. Preserve the atomic final funding reservation. A constant key in the existing rate-limit binding is insufficient for a strict global quota because those counters are local to Cloudflare locations. Use coordinated storage for the shared budget. [Cloudflare rate-limit locality](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/#locality).

### 4. Medium — Unpaid checkout creation can overwhelm payment recovery

**Locations:** `backend/src/payments/checkout.ts:19`, `backend/src/payments/routes.ts:29`, `backend/src/payments/reconciliation.ts:130`, `backend/wrangler.jsonc:8`.

Every new idempotency key permits another checkout intent and Stripe session. The application limits request frequency but never caps an account's outstanding `creating`/`open` intents. The shared scheduled recovery path inspects only 20 pending checkouts per 15-minute run.

**Impact:** A normal authenticated account can accumulate unpaid sessions without funding anything. At the configured rate, it can create up to 600/hour at one location, while scheduled recovery performs at most 80 pending-checkout inspections/hour. Open sessions remain eligible for repeated inspection, worsening the backlog. This increases Stripe/D1 load and delays recovery of ambiguous checkouts for other users. Signed webhook processing and foreground polling remain alternate paths; this is not a demonstrated double-credit or payment-forgery issue.

**Reproduction:** `AUDIT-4` creates 30 open checkouts for one account with unique keys at simulated 6.1-second intervals, remaining within 10 requests/minute. All requests return 200. A later recovery invocation retrieves only 20 sessions. Stripe was fully mocked.

**Fix:** Atomically cap outstanding checkouts per account, reuse a suitable existing session, and safely expire abandoned sessions before allowing replacements. Add a daily creation budget and fair recovery scheduling so one account cannot dominate the shared backlog. Keep webhook recovery independent.

### 5. Low — Account-summary reads bypass the configured rate limiters

**Locations:** `backend/src/index.ts:53`, `backend/src/payments/routes.ts:20`.

`GET /v1/me/usage` returns before applying a limiter. Payment configuration does the same; the owner-only summary also precedes the payment limiter but requires owner authorization. Usage performs multiple database queries, including aggregates over the account's ledger. Client refresh throttling cannot constrain a custom API client.

**Impact:** Any valid account can repeatedly invoke these database-backed reads without the application-level throttling used elsewhere, increasing shared database load. No cross-account data access was demonstrated. Severity is low because reads are scoped and bounded in output; actual denial of service was not load-tested, and independent infrastructure limits may reduce impact.

**Reproduction:** `AUDIT-5` supplies rate limiters that always deny. Usage and payment configuration still return 200, and neither limiter is invoked.

**Fix:** Apply a shared authenticated read limiter before these routes, with a budget that accommodates normal launch/foreground refreshes. Test both normal polling and excessive reads.

## Controls that held up

- Apple verification constrains signature algorithm, issuer, audience, expiry, nonce, and exchanged identity; the one-use authorization code prevents identity-token-only replay.
- Access JWTs have constrained algorithms, issuer, audience, scope, age, and lifetime. Account-scoped queries and deletion-state checks protect authenticated routes.
- D1 triggers reserve and settle integer-denominated balances atomically, enforce the shared free pool, and prevent duplicate answer spending. Stripe signatures, timestamp tolerance, event IDs, current provider snapshots, payment identity checks, and revision checks protect credit allocation.
- The iOS client uses HTTPS, rejects redirects, disables persistent network caches/cookies, and keeps credentials in non-synchronizing, device-only, unlocked Keychain storage. Conversation/photo paths are hashed by account and backend, with backup exclusion and file protection.
- Provider request parameters, prices, tool limits, and destinations are server-owned. Inference output is validated before streaming it to the app. Generated images are disabled and Markdown links must match approved sources. No prompt-driven path to secrets, arbitrary server fetching, or privileged tools was identified.
- Sensitive request bodies and credentials are absent from the inspected logging calls. CI has read-only repository permissions, commit-pinned actions, and checkout credential persistence disabled.

Prioritize session revocation and allowance persistence, then shared ESV and checkout controls. Convert each audit probe into a test asserting rejection/containment when implementing its fix, while preserving existing account-deletion recovery and payment idempotency behavior.
