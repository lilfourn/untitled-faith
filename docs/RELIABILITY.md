# Reliability implementation — September 10, 2026

The implementation preserves the existing interface and data-retention policy.
The original assessment follows this update for context; its proposed fixes are
not a description of the current UI.

Implemented:

- Settings exposes sign-out, the remembered AI-answer toggle, and privacy/terms.
- Session restoration can retry temporary credential/refresh failures; confirmed
  expiry/revocation still requires sign-in. Apple key-server outages are reported
  as temporary backend errors rather than invalid credentials.
- Pending deletion is stored separately in device-only Keychain. Server retries
  accept an already-deleted account's valid credential; a revocation checkpoint
  lets scheduled database cleanup resume. Device cleanup preserves other accounts.
- Interrupted usage has durable stages, attempt/error tracking, escalation, and an
  atomic audited resolution CLI. Only proven pre-dispatch failures auto-release.
  Holds requiring support remain visible across allowance-month changes.
- Retry checks an authenticated metadata endpoint before allowing another attempt.
  The user is told that another generation can consume allowance. Completed answer
  text remains unavailable for replay because the server stores no chat content.
- Failed answer saves block navigation/sign-out until saved or explicitly discarded.
  Cached usage remains visible with refresh errors and its last update time.
- Concurrent payment integration was preserved. Its availability gate controls
  the Add usage entry; this reliability work does not enable production payments.
- Added authenticated readiness, backend CI checks, and a command to compile signed
  iOS tests without launching a simulator. Live content evaluation now uses the
  production source-recovery path.

The backend requires migration 0007 before deployment. The combined checkout
also includes payment migration 0008. See [operations and release recovery](OPERATIONS.md).
The release snapshot was deployed September 10 as Worker version
`834cb8e4-f263-48aa-9fea-88f6c3469030` from commit `d34ae20`, after both migrations
were applied. App **1.0.6 (11)** uploaded successfully and Apple accepted it for
processing. The release passed 376 backend tests and two script tests; a live
Paul-answer request completed in 11.1 seconds and settled correctly. See the
[deployment record](../backend/DEPLOYMENT.md) and [TestFlight record](TESTFLIGHT.md).

### Reported Paul-answer failure

At approximately 00:21 CDT, request `d5173092-e787-47b9-be7e-11c39f4dcd30`
received an upstream HTTP 200 and ended with an SSE error/502 after 14.2 seconds.
The failure was at `moderation`, the stage containing the JSON/output-contract
validator. The original output was not retained, so the exact malformed field,
syntax, or size condition cannot be recovered from those logs.

One diagnostic reproduction of “Give me the story of Paul” completed and passed
validation in 8.4 seconds. It used a separate provider diagnostic identity and did
not consume an app question. Provider-reported cost was $0.00853575 before the
acquisition fee. This demonstrates an intermittent failure, not that all response
format failures are fixed. No additional paid attempts were made.

Added specific `AnswerValidationError` reasons (`string_count`, `invalid_json`,
`fields`, `answer_length`, `empty_answer`, `decision`, and `encoded_length`) and
provider generation ID to failure logs, without logging answer text. Invalid
formats now emit `invalid_answer_format`, which the app maps to its unreadable
answer message. Validation remains enforced. Evidence is recorded in the ignored
`.dev/paul-error-investigation.json`; the synthetic replay is also stored privately.

### Verification and remaining release work

Final `./scripts/dev check` passed the Bible index, TypeScript, **372 Workers
runtime tests**, **two recovery-script tests**, and deployment dry run. Logs:
`.dev/logs/backend-tests-20260910-003104-87010.log`,
`.dev/logs/recovery-script-tests-20260910-003127-87010.log`, and
`.dev/logs/backend-bundle-20260910-003127-87010.log`.

A separate isolated snapshot passed backend checks without local secret files
(`.dev/logs/reliability-ci-without-secrets.log`; 364 tests at that earlier snapshot).
`./scripts/dev build` passed with verified signing
(`.dev/logs/build-Debug-20260910-002343-79208.log`). Final signed app/unit/UI test
compilation passed using `./scripts/dev build-tests`
(`.dev/logs/ios-test-build-20260910-003105-87081.log`); the resulting app also passed
`./scripts/dev verify`. Ten new native recovery tests were compiled, not executed.
iOS tests and simulator UI automation were not run, as required by AGENTS.md.
Only the existing non-blocking App Intents metadata warning was emitted.
Workflow YAML parsing and `git diff --check` passed.

Still required before claiming complete end-to-end verification: confirm Apple
processing and run real signed-in/device acceptance journeys;
configure operational alert delivery; verify the first hosted CI run; rehearse
staging database/Worker recovery; and run the broader live answer-quality suite.

## Original review — September 9, 2026

Reviewed source commit `679485c`. Findings below come from current code inspection;
failure scenarios were not reproduced in the signed-in app during this review.
The original findings below describe the pre-implementation state. Implementation status is recorded above.

## Verification completed

| Check | Result |
| --- | --- |
| `./scripts/dev check` | Passed Bible index verification, TypeScript, 323 tests across 14 Workers test files, and deployment dry run |
| `./scripts/dev build` | Passed signed Debug simulator build; wrapper verified Apple sign-in and Keychain identity |
| `./scripts/dev auth-check` | Live health HTTP 200; invalid Apple credentials rejected with HTTP 401 |
| Signed-in app journeys, iOS tests, physical-device verification | Not run in this review |
| Live inference, purchases, production database recovery | Not exercised |

Logs: `.dev/logs/backend-tests-20260909-235114-47948.log`,
`.dev/logs/backend-typecheck-20260909-235114-47948.log`,
`.dev/logs/backend-bundle-20260909-235131-47948.log`,
`.dev/logs/build-Debug-20260909-235128-48250.log`.
The build emitted a non-blocking App Intents metadata warning.

The existing foundation includes atomic account-scoped conversation files,
Keychain sessions, shared token refresh, bounded backend payload reads,
database-enforced reservation/idempotency rules, provider fallback on eligible
rate limits, quotation validation before delivery, and usage reconciliation.
Workers logs and sampled traces are already enabled.

## First fixes

### 1. Make account controls and recovery reachable

[SettingsView](../Untitled%20Faith/Features/Settings/SettingsView.swift) exposes
profile photo, usage, contributions, and account deletion, but no sign-out action
or AI-answer toggle. `AppSession` still persists `aiAnswersEnabled`, and both
the legal text and service errors direct users to that missing toggle. A user
with a previously saved false preference cannot re-enable answers through this UI.
Policy links are available on sign-in but not in Settings.

Proposed fix: expose these controls in the existing minimal settings design;
cancel active work before account changes. Keep removing the old confirmation
popup separate from restoring the persistent setting.

Acceptance: a returning user with AI answers disabled can enable them; disabling
prevents future sends; sign-out returns to sign-in without deleting history;
switching accounts never displays the previous account's messages or usage.

### 2. Recover from temporary authentication failures

[AppSession.restoreSession](../Untitled%20Faith/App/AppSession.swift) sets
`didRestore` before network-dependent work and clears in-memory authentication
for any thrown error. A transient Apple credential lookup or token refresh failure
therefore returns the user to sign-in. Stored credentials can remain in Keychain,
but restoration cannot retry on the same session object. The active-scene
credential check immediately exits when authentication is nil.

Proposed fix: distinguish restoring, temporarily unavailable, authorized, and
expired/revoked states. Preserve a restorable session on transient failures,
provide retry, and revalidate on reconnection. Never treat uncertainty as successful
authentication for protected API calls. Inject credential lookup, Keychain,
authentication transport, and clock boundaries to test these transitions.

Acceptance: launch offline with an expired access token and valid renewal token,
reconnect, and resume without another Apple authorization; revoked/expired renewal
credentials still require sign-in. A protected endpoint's 401 must lead to an
actionable recovery state without automatically replaying uncertain inference.

### 3. Give interrupted usage a terminal resolution

[reconcile-usage.ts](../backend/src/reconcile-usage.ts) moves old reservations to
`uncertain`, then queries only records with a generation ID. Requests interrupted
before that ID is recorded have no automatic resolution. Repeated missing provider
metadata also has no terminal escalation. Uncertain requests keep reservations and
count against free usage; [account deletion](../backend/src/accounts.ts) rejects
accounts with any uncertain request.

Proposed fix: record inference stages durably, track reconciliation attempts and
age, alert on stuck records, and provide an audited resolution operation. Define
an explicit policy for costs that cannot be verified; do not infer zero cost from
a timeout. Release holds only with appropriate evidence or an intentional operator
adjustment. Background execution alone does not replace durable recovery.

Acceptance: interruption before and after provider-ID capture, provider metadata
404, and settlement database failures all have a bounded operational resolution;
repeated reconciliation never double-charges review or answer costs. Account
deletion cannot remain blocked without a visible, actionable resolution path.

### 4. Make deletion retryable after partial success

[apple-auth.ts](../backend/src/apple-auth.ts) requires an existing account before
revocation. If deletion succeeds but its response is lost, retrying receives 401
because the account is gone. The client removes conversations and photos only after
receiving a successful revoke response. Failure after Apple's revoke but before
database deletion is another partially completed state.

Proposed fix: make deletion idempotent for a verified deletion credential and use a
durable deletion state with recovery. Persist the device's pending cleanup intent
so app termination or an Apple revocation notification cannot abandon local cleanup.
Do not convert arbitrary authentication failures into successful deletion.

Acceptance: drop the final response, fail database deletion after Apple revocation,
and terminate/relaunch the client during deletion. Each path eventually removes
the intended data, reports a truthful result, and does not affect another account.

### 5. Resolve the unfinished purchase path

[ContributionCheckout](../Untitled%20Faith/Services/ContributionCheckout.swift)
always throws unavailable, and the wizard uses that implementation by default.
The backend allocation functions do not constitute an integrated checkout.

Proposed decision: complete the purchase integration, or clearly mark/disable
Add usage at its entry point while shipping a free-only release. Preserve the
user's chosen split inside the total. Match any purchase UI to actual supported
products rather than promising arbitrary purchasable prices.

Acceptance for a purchase release: verified transaction ownership, successful
credit, cancellation, pending payment, duplicate delivery, interrupted delivery,
refund, and account mismatch all work in the payment sandbox before release.

## Further hardening

- **Uncertain answer delivery:** `ChatStore.startSend(retrying:)` creates a new
  request ID. If a completed answer is lost in transit, retry can count a second
  request. The existing server deduplicates submissions but cannot replay an answer.
  Add a metadata-only status lookup and distinguish retry from starting another
  generation. Recovering completed text would require an explicit retention/privacy
  decision because the backend currently stores no chat content.
- **Local save recovery:** `ChatStore.saveCurrent()` reports a failed save but
  exposes no dedicated save retry. Navigating away can discard an answer that
  exists only in memory. Track unsaved changes, provide retry, and guard navigation
  until the user resolves or explicitly discards them. Preserve the current local
  storage policy; cloud sync is a separate product decision.
- **Honest usage state:** `UsageSection` hides refresh errors when any cached value
  exists, and does not show the cache timestamp. A stale percentage can look current.
  Keep the useful cached value while showing refresh failure and an accessible retry.
- **Operational visibility:** `/health` is a static liveness response. Add a separate
  protected readiness check for configuration/database schema, request-ID support
  in client errors, and alerts for answer failures, latency, stuck accounting, and
  shared budget exhaustion. Join provider-stage logs to request IDs. Distinguish
  the initial SSE HTTP 200 from final `answer_stream_completed` failure events.
- **Release recovery:** no checked-in CI workflow was found. Add automated backend
  checks and a signed-build validation path; establish staging isolation and a
  documented deployment rollback/database restore drill. Remote CI, alerts, backup
  configuration, and branch protection were not inspected in this review.
- **Answer quality:** extend the existing synthetic content-policy evaluation to
  assess useful explanations, follow-up context, translation accuracy, source
  recovery, and fair treatment of differing readings. Keep its validation behavior
  aligned with production: the evaluation currently uses `sources.finish`, while
  production uses `sources.resolve` for recovery. Mocked transport tests cannot
  establish live answer quality. Record model/prompt versions, latency, and cost.

## Release acceptance checklist

Treat a release as verified only when the applicable journeys have recorded
results for the actual app build and backend revision.

| Journey | Required evidence |
| --- | --- |
| Account lifecycle | Real Apple sign-in; restart; refresh; offline/reconnect; expiry; sign-out; account switch; deletion and deletion retry |
| Chat | Ask and follow up; open verified sources; stop; retry; disconnect; background/foreground; force quit; long input; rate limit; source/provider failure |
| Local data | History survives restart/update; accounts stay isolated; save failure is recoverable; corrupt files are preserved; deletion finishes |
| Usage | Exactly one settlement per attempt; duplicate delivery; pending recovery; allowance reset; shared pool exhaustion; stale display |
| Payments, if enabled | Sandbox transaction lifecycle, server verification, duplicate/refund handling, and correct final balance |
| Device/UI | Supported iOS versions, real iPhone, iPad, large text, VoiceOver, Reduce Motion, light/dark appearance, keyboard and rotation |
| Operations | Automated checks; protected readiness; useful failure correlation; alerts; exercised Worker rollback and database recovery |
| Content | Fixed synthetic question set, human-reviewed explanation quality, quotation fidelity, crisis/off-topic handling, and provider fallback |

Run backend checks after relevant changes. The repository requires Luke's explicit
request before `./scripts/dev test` or simulator UI automation. A preview launch
does not count as signed-in verification. Live inference evaluations consume
credits and were not run here.

Recommended implementation order: reachable controls and session recovery;
accounting/deletion recovery; save/retry/usage feedback; purchase scope decision;
release automation and device/operational acceptance runs. Finalize the existing
draft policies against the finished user experience before public release.
