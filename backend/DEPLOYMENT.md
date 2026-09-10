# Deployment status

Updated September 9, 2026.

The clearer teaching and context instructions are deployed as version
`cfda7243-bc3c-4378-b79a-8f8dcdcd6f25` from source commit `5d505d8`. Both answer paths now require
context before drawing conclusions, explained connections between passages and claims, plain definitions,
fair treatment of differing readings, and the same fallibility standard for all outside commentary.
See [teaching rationale and review cases](../docs/EXPLANATIONS.md).

The source was unchanged from the passing Bible index, TypeScript, 268 backend tests, and deployment
dry run (`.dev/logs/backend-tests-20260909-224725-91374.log`). Deployment used the project-local
`npm run deploy -- --keep-vars --strict`, retaining remote variables and secrets; no migration was needed.
Log: `.dev/logs/deploy-clear-teaching-20260909.log`. The source fingerprint in
`.dev/clear-teaching-release-source.json` matched after deployment, and Wrangler confirmed the new version
at 100% traffic. Live `/health` returned 200 and an unauthenticated `/v1/answers` returned 401.
No paid inference or live teaching-quality comparison was run. Existing clients receive the new prompt
without an app update; the separate usage-display client release is recorded in [TestFlight](../docs/TESTFLIGHT.md).


The preceding source-recovery and output-contract update was deployed as version `6640300e-44b1-4bb3-9301-11cdb3d86aaf`.
The reported faith question was reproduced through the real answer adapter: HTTP 200 generation failed
at `stage: sources` with `unverified_link`. The model had cited a retrieved ESV.org `/verses/Heb...` URL
excluded by the old route classifier. Its excerpt also contained a cross-reference marker inside the
quotation wording. The captured response replay now retains its explanation and all three quotations,
using another verified ESV excerpt for the noisy citation.

Both JSON and SSE now repair citation presentation, normalize URL aliases, preserve evidence across
empty duplicate annotations, and keep the explanation if an individual quote/link is unsupported.
Final quote metadata is still checked against evidence, with rebuilt UTF-16 positions. The prompt now
requires an explicit two-field JSON envelope, a self-contained explanation outside quotations, exact
evidence URLs, and a fixed quotation layout. Faith retrieval includes Hebrews 11:1–6 and Ephesians 2:1–10.
No client rebuild, migration, credential change, or additional inference retry is required for recovery.

Validation: `./scripts/dev check` passed the Bible index, TypeScript, **268 Workers tests**, and deployment
dry run (`.dev/logs/backend-tests-20260909-221929-65424.log`). Deployment used `wrangler deploy --keep-vars
--strict` (`.dev/logs/deploy-source-recovery-final-20260909.log`) and matched the recorded source fingerprint.
A live request through the deployed authenticated SSE endpoint for “What does it mean to have faith?”
completed in 7,844 ms with `start`, `delta`, and `done`, two verified quotes, valid quote positions, and
settled cost of 6,337 micro-USD including acquisition fees. The temporary operator account was removed
only after confirming settlement. The existing user's allowance was not used for this test.

The connected Wrangler log stream confirmed `answer_sources_recovered` with two repaired quotations,
zero omitted quotes/links, and `answer_stream_completed` status 200 for request
`28e07036-13f8-4853-86b7-e56a36fa0ddc`. Historical log retrieval through the MCP connector failed schema
validation, and the direct historical REST query lacked permission; the reproduction and live tail
provided the usable diagnostic evidence. Reports: `.dev/faith-source-reproduction.json`,
`.dev/source-recovered-replay.json`, `.dev/source-recovery-live-final.json`, and
`.dev/source-recovery-final-log-summary.json`. No iOS tests or simulator UI automation were run.


The preceding monthly-only allowance update was deployed as version `529edd2d-0385-4c3f-bbd8-e7b9c1456931`.
Users can spend all 30 monthly free requests on any day. Migration `0006_monthly_only_allowance.sql`
was applied to the remote `untitled-faith-users` database before deploying the Worker. It removes only
the daily predicate from the reservation trigger and retains monthly, shared-pool, funding, concurrency,
and idempotency checks. A read-only query confirmed the deployed trigger no longer references the daily
limit and still checks the monthly limit and active requests. Existing usage and funding records were retained.

`./scripts/dev check` passed index consistency, TypeScript, 253 Workers tests, and deployment dry run
(`.dev/logs/backend-tests-20260909-211515-25863.log`). The regressions spend all 30 monthly requests in
one day, spend an existing account's remaining 20 in one day, and still reject a 31st unfunded request.
Migration log: `.dev/logs/migrate-monthly-only-20260909.log`. Deployment used `wrangler deploy --keep-vars
--strict` (`.dev/logs/deploy-monthly-only-20260909.log`); the source matched
`.dev/monthly-only-release-source.json`. The health endpoint returned 200. No paid inference was run.
The matching signed client archive is 1.0.2 (7), restoring the single progress bar and percentage;
see [TestFlight release status](../docs/TESTFLIGHT.md#monthly-allowance-update-102).


The preceding reliability and cheaper-fallback update was deployed as version `ef1f3f13-2136-4262-9f0a-99ab40e8fde3`.
Updated clients use Gemini 3.8 Flash primarily and GPT-5.6 Luna with low reasoning after a provider HTTP 429;
the independent reviewer uses GPT-4.1 Nano if Gemini Flash Lite is rate-limited. Older clients keep their
Google-only routes. The deployment also preserves specific source/rate-limit errors and distinguishes
daily/monthly free limits from shared-pool availability. Daily reset time is included in usage responses.
No database migration or secret change was required.

`./scripts/dev check` passed the Bible index, TypeScript, 252 Workers tests, and deployment dry run
(`.dev/logs/backend-tests-20260909-205650-11841.log`). Deployment used `wrangler deploy --keep-vars --strict`
with existing remote variables retained (`.dev/logs/deploy-reliability-20260909-retry.log`). An initial CLI
authentication failure was resolved by refreshing the existing OAuth login through `wrangler whoami`;
no new credential was created. The source matched `.dev/reliability-release-source.json` after deployment.
The deployed health endpoint returned 200, and an unauthenticated answer request returned 401.
No paid inference or forced live fallback was run; provider behavior is covered by mocked tests and
catalog verification, not a live quality evaluation. The client release is TestFlight 1.0.1 (6); see
[release status](../docs/TESTFLIGHT.md#reliability-update-101).

The preceding response-formatting prompt was deployed as version `98170bc5-0180-4ace-80eb-c4a5d0525b17`.
It asks for short paragraphs, bullet lists, numbered steps, selective bold and italics, and headings in
longer answers, while keeping verified quotations verbatim. `./scripts/dev check` passed the Bible index,
type checks, 231 backend tests, and deployment dry run (`.dev/logs/backend-tests-20260909-192654-98626.log`).
Deployment used `wrangler deploy --keep-vars --strict` (`.dev/logs/deploy-response-formatting-20260909.log`).
The deployed health endpoint returned `{"status":"ok"}`.
The signed app was rebuilt, installed, and opened with ESV-only home verses and increased Markdown spacing
(`.dev/logs/build-Debug-20260909-192730-2196.log`). No iOS test suite, simulator UI automation, or paid inference
check was run for this update; manual signed-in presentation verification remains outstanding.

The preceding writing-style prompt was deployed as version `5bb83ec1-a837-4cb9-9798-1d66e45fd569`.
Both answer paths now receive the stop-slop instructions, including no em dashes in generated prose or citation labels.
Verified quotations retain their original punctuation. Deployment retained remote variables and secrets with
`wrangler deploy --keep-vars --strict` (`.dev/logs/deploy-writing-style-20260909.log`). The Bible index check,
type check, 231 backend tests, and deployment dry run passed (`.dev/logs/backend-tests-20260909-191919-81133.log`).
The deployed health endpoint returned `{"status":"ok"}`. No live inference quality check was run.
The app was rebuilt, signing verified, installed, and opened with `./scripts/dev run`
(`.dev/logs/build-Debug-20260909-192015-83646.log`).

The preceding independent-review and Scripture quotation fixes were deployed as version `a78a316f-1a7e-4a8e-b017-c4f29d5867fe`.
Migration `0005_request_review_usage.sql` was applied first. Deployment used `wrangler deploy --keep-vars --strict`
and retained existing remote secrets. Review uses a separate Gemini Flash Lite model, full conversation context,
and accounting checkpoints; verified Scripture quotations no longer have a separate word cap. Bible.com passage
comparison URLs are now recognized, and interfaith retrieval includes Romans 11 and Ephesians 2.

Before deployment, the Bible index check, type check, **231 backend tests**, and deployment dry run passed
(`.dev/logs/backend-tests-20260909-190442-31862.log`). All 28 live reviewer cases passed. Full-answer checks passed
for the exact prayer question over SSE and Christian–Jewish relationship question over JSON. One earlier
interfaith call returned upstream HTTP 400; provider availability remains fallible. The live checks used the
current local adapters and real providers, not a new post-deployment operator account.

The signed iOS build was installed and opened normally with `./scripts/dev run`; Apple sign-in and Keychain
entitlements were verified (`.dev/logs/build-Debug-20260909-190623-36060.log`). It displays 200-character quotation
previews and Read more sheets, retaining full quote text. All 44 iOS unit tests passed before the user stopped
automatic test runs; the full UI suite did not pass (contribution navigation failures/interruption). Do not restart
simulator UI automation automatically. Actual signed-in manual verification remains with the user.

Release records: `.dev/logs/migrate-request-review-20260909.log`, `.dev/logs/deploy-request-review-20260909.log`,
`.dev/request-review-source.json`, and `.dev/request-review-eval.json`. The backend source fingerprint was
unchanged during deployment. No post-deployment inference or UI test run was started after the user's stop request.


The preceding Crossway ESV proxy and answer-grounding release was deployed as version `a88f23f3-0fa8-4dad-b6c6-b8897e12ffb9`.
The user supplied `ESV_API_KEY`; it was added to the protected local `.dev.vars` (0600) and Cloudflare secret
storage. The API key was verified against Crossway without printing it. Deployment retained the existing
remote secrets and variables (`wrangler deploy --keep-vars --strict`); no existing secret was rotated.
No new migration was required by ESV grounding, and the already-applied account migration was checked before deployment.

Verification: the Bible index consistency check, type check, **203 backend tests**, and deployment dry run
passed. The deployed `/v1/passages` returned exact ESV text for an authenticated temporary operator account,
rejected an unauthenticated request with 401, and returned no credentials. A live SSE answer quoted John 11:35
from the supplied Crossway evidence and passed source matching. It completed in 4,963 ms and settled 2,923
prompt tokens, 103 completion tokens, and 2,721 micro-USD including acquisition fees. The temporary account
was removed after verifying no unsettled requests. This is a focused smoke check, not an exhaustive quality evaluation.

Release records: `.dev/logs/backend-tests-20260909-184653-78114.log`,
`.dev/logs/backend-bundle-20260909-184709-78114.log`, `.dev/logs/deploy-esv-20260909.log`, and
`.dev/logs/esv-live-verification-20260909.log`. The source matched the recorded
`.dev/esv-tested-source.json` fingerprint before deployment. Worker startup was 83 ms; upload was
8,237.33 KiB / 2,665.01 KiB gzip. No iOS rebuild is required for this proxy/grounding change.

The preceding moderation release was deployed as version `cd2013c8-f093-48e9-a0f8-f5e95709f55c`. Migration `0004_account_first_name.sql` was applied to the remote database before deployment; Wrangler subsequently reported no pending migrations. The backend first-name support is included. Installing the updated signed iOS build and verifying Apple given-name capture remain separate client verification steps. Existing accounts have no first name until Apple supplies one during authorization.

Release verification: `./scripts/dev check` passed the Bible index check, type check, all 192 backend tests, and deployment dry run (`.dev/logs/backend-tests-20260909-184031-64428.log`). Deployment used `wrangler deploy --keep-vars` with existing remote secrets retained, without uploading or rotating secret values (`.dev/logs/deploy-moderation-20260909.log`). The deployed health endpoint returned 200, and an unauthenticated answer request returned 401. Authenticated live checks passed an off-topic redirect over SSE, a brief Christian explanation of innocent suffering for an atheist over JSON, and crisis support over SSE. Each stream emitted only `start`, the approved `delta`, and `done`. All three requests settled, totaling 10,951 micro-USD including acquisition fees; the temporary operator account was removed afterward. Results are in `.dev/moderation-release-verification.json`.

The prior broader evaluation's intermittent citation/provider failures remain a known limitation; these three smoke checks are not a full citation regression run. A source fingerprint was recorded in `.dev/moderation-release-source.json`; concurrent edits to `src/bible/types.ts` and `src/esv.ts` were observed during deployment and are not claimed as verified by this release. Preserve those edits for their own validation/release.

Local validation for first-name personalization: `./scripts/dev check` passed the Bible index check, backend type check, 192 tests, and deployment dry run (`.dev/logs/backend-tests-20260909-183747-59296.log`). `./scripts/dev test` passed 41 signed iOS unit tests and 2 UI tests (`.dev/logs/ios-tests-20260909-183754-59471.log`). `./scripts/dev build` passed with Apple sign-in and Keychain identity verified, including the updated privacy text (`.dev/logs/build-Debug-20260909-183918-62738.log`). Apple and inference endpoints were mocked in those tests; no live name capture or paid inference was performed for that local validation. Implementation touches Apple name-scope capture/exchange, account profile validation and migration, account-backed prompts in both answer paths, reservation sizing, tests, and privacy/setup documentation. Remaining client action: install the new signed app and verify Apple given-name capture when Apple provides it.

The `untitled-faith-proxy` Worker is deployed at `https://untitled-faith-proxy.vendors-c0f.workers.dev` in Cloudflare account `c0f96de71bdc54889c1ad27ccc90dfc0` (`vendors@gridbloom.app`). The current clearer-teaching deployment is version `cfda7243-bc3c-4378-b79a-8f8dcdcd6f25`. The preceding source-recovery deployment was `6640300e-44b1-4bb3-9301-11cdb3d86aaf`. The preceding monthly-only allowance deployment was `529edd2d-0385-4c3f-bbd8-e7b9c1456931`. The preceding reliability deployment was `ef1f3f13-2136-4262-9f0a-99ab40e8fde3`. The preceding response-formatting deployment was `98170bc5-0180-4ace-80eb-c4a5d0525b17`. The preceding writing-style deployment was `5bb83ec1-a837-4cb9-9798-1d66e45fd569`. The preceding independent-review deployment was `a78a316f-1a7e-4a8e-b017-c4f29d5867fe`. The preceding ESV-grounding deployment was `a88f23f3-0fa8-4dad-b6c6-b8897e12ffb9`. The preceding moderation deployment was `cd2013c8-f093-48e9-a0f8-f5e95709f55c`. The preceding approved-web-search deployment was `ca6e14d4-a368-430a-bdd2-b51a7780fe14`. The prior streaming deployment was `32ff97f1-0a92-474c-8f03-5ad8fcbfa319`. The preceding account/usage deployment was `8b09e554-6947-42f1-aab4-83ad415eea78`.

Web-search verification: 94 backend tests, 30 signed iOS unit tests, and 2 iOS UI tests passed. A live request through the deployed `/v1/answers` endpoint returned a GotQuestions quotation matched against the retrieved excerpt, its exact source URL, and commentary formatting metadata. Text streamed in four deltas, with first text at 11.755 seconds and completion at 12.408 seconds. The ledger settled 5,083 prompt tokens, 1,352 completion tokens, and 16,756 micro-USD including search and acquisition fees. The temporary developer account was removed after confirming no pending charges. The native quotation layout was rendered and visually checked; the app was rebuilt and installed with signing verified. Search added no secrets or database migrations. See [approved web search](../docs/WEB_SEARCH.md).

Streaming/session verification: 69 backend tests and 21 signed simulator tests passed. The signed Debug app was rebuilt, installed, and opened in chat preview; both top-of-chat notices were visually confirmed removed. A live streamed request included a three-message conversation and correctly recalled the word from the first message. Its first text arrived at 9.214 seconds and the settled completion at 9.472 seconds, with 191 prompt tokens, 161 completion tokens, and 789 micro-USD including acquisition fees. The temporary developer account was removed after checking there were no unsettled requests. No chat text is stored in D1; local session storage requires no database migration. Existing secrets and bindings were retained. See [chat harness details](../docs/CHAT.md).

The `DB` binding points to D1 database `untitled-faith-users` (`599fc9a3-1546-443b-b9bd-27dfb65c4240`). Migrations 0001, 0002, and 0003 are applied locally and remotely. Migration 0003 adds the optional developer-share ledger; no real contribution has been credited. The scheduled usage reconciliation runs every 15 minutes. See [account and funding behavior](../docs/ACCOUNTS.md).

Account/usage verification: 55 backend tests passed; 12 signed simulator tests passed; the signed Release simulator build passed. A live developer account started at 100%, received one answer with 171 prompt tokens and 295 completion tokens, recorded 1,303 micro-USD including acquisition fees, and changed to 96%. A repeated idempotency key returned 409 without another generation. No unsettled requests remained; the developer account was removed and its accounting record unlinked. Three earlier diagnostic reservations were released after confirming that an unsupported fetch redirect mode rejected those requests before upstream I/O. Server fetches now use manual redirect handling, preserving the no-forwarding policy.

Payment checkout and verified-payment ingestion are not connected yet. The personal contribution/refund ledger is implemented and tested; no real contribution has been credited.

The supplied OpenRouter key was accepted by OpenRouter's authenticated key endpoint. Its value is stored in Cloudflare as `secret_text` and in the ignored local `.dev.vars` file with owner-only permissions (`0600`). It is absent from Apple client source and configuration. Users never supply an OpenRouter key; the backend uses this secret for their requests.

`SESSION_SIGNING_KEY`, `SESSION_ENCRYPTION_KEY`, and `APPLE_PRIVATE_KEY` are provisioned as Worker secrets alongside the existing OpenRouter key. The Apple key ID is `4ADZN888UW`, scoped to the app's Sign in with Apple capability. The app now contains the public backend URL. No server secret is embedded in the app.

Authentication verification: Luke confirmed successful Apple sign-in in the simulator after the server fetch receiver/redirect fixes. The authentication fix deployment passed 55 backend tests; the earlier signed app suite passed 11 tests. The app now uses a single button label with a native authorization controller, avoiding doubled text during popup dimming. The developer wrapper verifies the built and installed simulator entitlement sections and isolates build output. The signed physical-device profile also contains the Sign in with Apple entitlement for `com.lukefournier.UntitledFaith`.

Verification: OpenRouter key endpoint returned HTTP 200; `wrangler secret list` confirmed `OPENROUTER_API_KEY` as `secret_text`; local file permissions and absence of the key from client source/configuration were checked.

A prior user-authorized live inference test through the actual `generateAnswer` backend adapter returned HTTP 200 with finish reason `stop` in 3.36 seconds. Usage was 175 prompt tokens, 328 completion tokens, 503 total tokens, and a reported cost of $0.00136125. The adapter returned a valid answer suggesting the Gospel of John as a starting point for Bible reading. Apple sign-in has subsequently been confirmed working by Luke.
