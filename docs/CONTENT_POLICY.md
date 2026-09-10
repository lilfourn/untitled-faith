# Topic and safety moderation

Product decision, September 9, 2026: allow as much freedom as possible for Bible and Christianity questions. Restrict harmful assistance and unrelated tasks; do not censor hard questions, doubt, disagreement, or criticism of Christianity.

## Behavior

| Request | Behavior |
| --- | --- |
| Scripture, theology, Christian history/practice, prayer, pastoral support | Answer |
| Atheistic objections, contradictions, hell, biblical violence, slavery, sexuality, LGBTQ issues, abortion, religious comparisons | Answer fairly in the Christian/Bible context |
| Profanity, anger, skepticism, or disagreement | Not a reason to refuse |
| Grief, guilt, relationships, distress without explicit religious keywords | Allow reasonable pastoral support without imposing belief |
| Short follow-ups, greetings, thanks, app-purpose questions | Allow; use the whole conversation for context |
| General code, recipes, shopping, sports, unrelated news | Briefly redirect to the app's purpose |
| Unrelated task prefixed with “for my church” or “in Jesus' name” | Still off topic |
| Mixed faith question and unrelated task | Address only the faith question and redirect the unrelated part |
| Instructions enabling violence, exploitation, sexual content involving minors, erotica, targeted hate, fraud, cyber abuse, doxxing, self-harm | Safe refusal, including when framed as religious or fictional |
| Discussion, history, ethics, prevention, or recovery involving those subjects | Allow; do not confuse the subject with harmful assistance |
| Current danger, self-harm intent, or a recent potentially life-threatening act | Supportive crisis response regardless of topic; encourage immediate human help |

Pastoral support must not pressure someone to remain in abuse, force forgiveness or reconciliation, replace treatment with prayer, diagnose/prescribe, or affirm dangerous commands as divine revelation. Abstract theological discussion of suicide remains answerable. Crisis support takes precedence over off-topic filtering and refusal.

## Enforcement

`backend/src/content-policy.ts` owns the policy, upstream JSON schema, runtime parser, and fixed redirect/refusal/crisis text. `answer-prompt.ts` combines it with the existing source-grounding instructions.

A separate request reviewer (`google/gemini-2.5-flash-lite`) classifies the latest question in full conversation context before the answer model or paid web search runs. It uses Google provider families primarily, with GPT-4.1 Nano on OpenAI as the server-selected HTTP 429 fallback for updated clients, no tools, a 128-token output budget, and a strict one-field decision schema. Respectful Christian–Jewish relationships and interfaith questions are explicitly allowed; group names are not a blacklist. The server returns the existing fixed responses for off-topic, unsafe, and crisis decisions. Unknown/malformed/truncated review responses fail closed. The answer model receives server-owned confirmation of relevance and still checks its output for harmful content.

`backend/src/review-policy.ts` owns the reviewer prompt and routing limits; `request-review.ts` validates its decision and checkpoints measured usage before answer generation. The primary answer model remains `google/gemini-3.8-flash`; updated clients permit the cheaper `openai/gpt-5.6-luna` fallback after an HTTP 429 before generation. Other failures are not automatically retried. See [routing and release status](CHAT.md#cheaper-fallback-and-allowance-clarity). Both calls share the existing 45-second deadline. The complete generated answer must contain exactly `decision` and `answer`. The runtime parser accepts the previously observed whole-response JSON fence and literal string whitespace, but rejects duplicate fields, missing structure, truncation, and provider content-filter stops.

For an allowed answer, the Worker validates nonempty text, the existing 8,000 UTF-16-unit response bound, and exact source/quotation checks. Scripture has no separate quotation word limit. A reproduced prayer answer was correctly allowed but discarded because one verified quotation contained 109 words, exceeding the former 100-word cap. This was a source-validation failure, not a moderation rejection. Another reproduced interfaith answer cited a legitimate Bible.com translation-comparison passage route that the source filter did not recognize; constrained passage-comparison URLs are now accepted. Source failure logs contain a reason enum, never question, answer, or excerpt text.

Both JSON and SSE use the reviewer and answer gate. SSE sends `start` immediately and buffers generated output until moderation, source checks, and settlement finish, then sends one approved `delta` and `done`. No partial generated text or private review fields reach the client. The iOS app previews quotations at 200 characters, with **Read more** opening the full saved quotation; it no longer rejects a quotation solely for exceeding 1,500 UTF-16 units.

Migration `0005_request_review_usage.sql` adds three accounting-only checkpoint columns. The reservation includes both calls. Settlement and later provider reconciliation add the known review cost exactly once to answer cost, while counting the exchange as one question. An unbilled answer failure still settles the completed review; an unbilled review failure releases the reservation. Unknown costs retain their hold. Requests interrupted without a provider generation ID still require operator reconciliation, as before. No chats, review reasoning, new credentials, or account penalties are stored.

Model decisions remain fallible. The reviewer supplies an independent semantic decision, and deterministic validation enforces its returned label; neither guarantees classification accuracy or prevents every prompt injection. Provider failures and unsupported citations can still return a sanitized error. Bible retrieval can occur before review, but the reviewer itself has no tools and blocked requests never reach paid web search.

## Verification

Run `./scripts/dev check` for type checks, mocked Workers tests, and a deployment dry run. Tests cover both transports, replacement of unsafe/off-topic text, preservation of an allowed controversial answer, full-context forwarding, attempted client overrides, malformed envelopes, JSON escapes/fences, source validation, provider content-filter stops, no partial-text leaks, cancellation, and accounting. Mocked decisions test enforcement; they do not test classification accuracy.

The synthetic cases in `backend/test/fixtures/content-policy-cases.json` exercise permissive and restrictive decisions, topic drift, forged assistant instructions, Spanish, pastoral distress, and crisis support. To evaluate the actual production prompt and request configuration using the protected local key:

```sh
cd backend
node --env-file=.dev.vars scripts/evaluate-content-policy.mjs --run-paid-eval
```

This explicitly enabled command consumes inference credits, runs independent review and verified ESV retrieval, alternates JSON and SSE for allowed answers, and checks the decision plus existing source validation. Add `--review-only` to exercise just classification across the corpus; its report is `.dev/request-review-eval.json`. It uses the installed esbuild tooling to import the current backend implementation. It does not use app accounts or touch D1. Results contain case IDs, decisions, sanitized failures, and cash cost in micro-USD including acquisition fees; no credentials or generated answer text. Reports are saved to `.dev/content-policy-eval.json`. Use `--case=ID` for a targeted rerun, saved separately. Classification checks still require qualitative review of allowed responses for theological fairness and quality.

Earlier same-day validation (before independent review):

- `./scripts/dev check` passed all 192 tests in the shared checkout, including the concurrent Bible-retrieval work, type checking, and the deployment dry run. Logs: `.dev/logs/backend-typecheck-20260909-183757-59695.log`, `.dev/logs/backend-tests-20260909-183757-59695.log`, and `.dev/logs/backend-bundle-20260909-183818-59695.log`.
- The 26-case live run in `.dev/content-policy-eval.json` completed before the final literal-whitespace normalization fix: 17 passed end to end; four failed JSON parsing, three had correct `answer` decisions but failed source checks, and two encountered provider failures. Every completed, parsed moderation decision matched its expected label. That run reported $0.23785 in inference cost; this excludes other diagnostic/rerun calls and acquisition fees.
- Targeted live reruns after the parser fix passed all four formerly malformed cases: Bible reading, skepticism, sexuality, and abuse disclosure. Their separate reports are `.dev/content-policy-eval-bible.json`, `.dev/content-policy-eval-skepticism.json`, `.dev/content-policy-eval-sexuality.json`, and `.dev/content-policy-eval-abuse-disclosure.json`. Do not describe this as an all-green full live suite: citation validation and provider reliability still need follow-up.
- No iOS files were changed for moderation, and the existing client parser accepts the single approved delta followed by matching `done`. The implementation stage did not rebuild iOS or deploy; the subsequent authorized deployment is recorded below.

Subsequent user-authorized deployment: Worker version `cd2013c8-f093-48e9-a0f8-f5e95709f55c` is live. The pre-deploy check again passed 192 tests, type checking, and the bundle dry run. Remote migration 0004 was applied first, existing secrets were preserved, and all three authenticated endpoint smoke tests passed: off-topic redirect, an allowed question about innocent suffering, and crisis support. The temporary test account was removed after usage settled. See `backend/DEPLOYMENT.md` and `.dev/moderation-release-verification.json`.

Remaining integration work: investigate the earlier live `sources_unavailable` cases (biblical violence, mixed faith/unrelated requests, Spanish faith question) in the concurrently evolving source-grounding path and rerun the full live corpus. Preserve the fail-closed gate and all shared Bible/pastoral-prompt edits. The successful deployment smoke checks do not establish that those intermittent source/provider issues are resolved.

## References

- [OpenRouter structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs): schema requests, endpoint-specific support, `require_parameters`, and streaming behavior. The allowed Gemini endpoints advertised `structured_outputs` and `response_format` on September 9, 2026; live behavior still required runtime validation.
- [OpenRouter web-search server tool](https://openrouter.ai/docs/guides/features/server-tools/web-search): the existing server-side search and citation annotations.
- [OpenRouter reasoning controls](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens): Gemini effort mapping and the shared reasoning/output budget; effort does not guarantee a precise token allocation.
- [Workers Streams API](https://developers.cloudflare.com/workers/runtime-apis/streams/): bounded upstream streaming and the app's SSE response.

Independent-review verification: the 28-case live classification corpus passed, including the exact prayer and Christian–Jewish relationship questions, for 2,531 micro-USD including acquisition fees. Targeted full-answer checks passed for prayer over SSE and interfaith relationships over JSON. One interfaith attempt encountered an upstream HTTP 400; a later attempt succeeded. These checks are not a guarantee of upstream availability.

The independent-review update and quotation fixes were subsequently deployed as `a78a316f-1a7e-4a8e-b017-c4f29d5867fe` after migration 0005 and 231 passing backend tests. The updated signed app was installed and opened normally. iOS unit tests passed (44); the UI suite did not pass, and the user asked to stop automatic simulator testing. See `backend/DEPLOYMENT.md` for the precise validation boundary.
