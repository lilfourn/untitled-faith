# Local conversations and streaming

September 9, 2026. User decisions: keep conversations on the phone, make them reopenable/deletable, and send the **whole conversation plus the new message on every request**. Do not silently truncate or summarize. The initial harness left retrieval outside its scope; [approved web search](WEB_SEARCH.md) was subsequently added at the user’s request. The two informational notices above the chat were removed at the user's request; storage/privacy details remain in Settings.

The user subsequently removed the “Allow AI answers?” popup. Send now goes directly to the answer service. AI answers default on; Settings has an on/off switch whose value persists on the device. The existing `consentVersion` wire field is retained for compatibility with the deployed API; it is not a record of an explicit popup opt-in.

## Storage and context

`LocalConversationStorage` stores one versioned JSON file per conversation under Application Support. Directories are scoped by a hash of the backend and Apple app-specific identity, with a separate preview namespace. Files use atomic replacement and iOS data protection, and the directory is excluded from backups. There is no cloud chat table, sync service, or new D1 migration.

The app opens to a new, empty conversation after launch/sign-in. Previous conversations remain in History and open only when selected. New conversation preserves the previous chat. History supports reopening and confirmed deletion. Signing out retains local chats for that identity; successful account deletion removes that identity's local chat directory on this device after the active send stops. Removing the app removes its files. Other devices retain their own files.

The question is saved before inference starts. The app shows shimmering Thinking… text while awaiting output, then Writing… when content starts arriving. Provider deltas stay offscreen until a valid final response arrives. The full response is saved before its formatted reveal begins. Interrupted requests retain the question without publishing unfinished answers. Stopping the visual reveal shows the already-saved full answer. The client never automatically retries; the server may try its configured cheaper model after an unbilled HTTP 429 rejection. Unreadable files are preserved and reported.

Every send constructs the full ordered `user`/`assistant` message array from the current conversation, including any displayed partial answer, then appends the latest question. The backend prepends the existing system prompt. The request ceiling is 1 MiB, 1,000 messages, 8,000 UTF-16 units per message, and 200,000 total. An over-limit conversation fails explicitly. No earlier message is dropped to fit.

## Streaming path

1. iOS posts to `/v1/answers` with its app bearer token, current consent version, stable `Idempotency-Key`, and `Accept: text/event-stream`.
2. The Worker validates the complete context and reserves usage with the existing accounting rules.
3. The existing OpenRouter request configuration enables `stream: true`, usage reporting, and a structured topic/safety decision. The provider parser handles comment heartbeats, multiline data, split UTF-8/CRLF, repeated terminal reasons on usage frames, `[DONE]`, and errors inside HTTP 200 streams. It buffers the bounded upstream response until the complete moderation and source checks pass. See [content policy](CONTENT_POLICY.md).
4. The Worker emits `start` immediately, then one approved `delta` and `done` after validation and settlement. Provider/model fields, moderation decisions, and usage metadata stay server-side:

```text
data: {"type":"start","requestID":"…"}

data: {"type":"delta","text":"Hello"}

data: {"type":"done","answer":{"text":"Hello","scripture":[],"commentary":[]},"requestID":"…"}

```

Failures emit `{"type":"error","error":{"code":"answer_unavailable"},"requestID":"…"}` (or the applicable generic code). The client requires a valid `done` event; EOF is not success. After completion it reveals the already-formatted answer from top to bottom with a soft edge, over 0.5–4 seconds depending on length. Markdown is parsed before this reveal, so headings, lists, and quotation layout stay stable. Reduce Motion or VoiceOver skips the reveal; Reduce Motion also disables shimmer. Automatic scrolling stops when the user drags through earlier messages. Stop cancels the connection; it does not guarantee the provider stops billing.

The Worker persists the generation ID for accounting recovery as soon as it is available, settles measured usage before `done`, releases known unbilled rejections, and holds uncertain charges for the existing reconciler. Chat text is never written to D1 or application logs. The legacy JSON response remains available to clients that request JSON.

## Verification and references

`./scripts/dev check` covers Workers runtime tests, type checks, and deployment dry run. `./scripts/dev test` covers signed iOS tests, including disk restoration/deletion/account isolation, full-history follow-ups, partial-answer restoration, request-size failures, and URLSession receiving text before completion. Tests mock inference and do not spend credits.

The implementation follows [OpenRouter's streaming protocol](https://openrouter.ai/docs/api/reference/streaming) for deltas, usage, terminal events, and cancellation; [Cloudflare's Streams API](https://developers.cloudflare.com/workers/runtime-apis/streams/) for forwarding incremental output; and the separation between stored messages and model requests described in [AI SDK message persistence](https://ai-sdk.dev/docs/ai-sdk-ui/chatbot-message-persistence). These patterns are implemented directly for the existing Swift client and Worker without adding an agent framework.

Final checks for this change: 69 backend tests passed (`.dev/logs/backend-tests-20260909-173022-25713.log`); type checks and deployment dry run passed through `./scripts/dev check`. All 21 signed iOS tests passed (`.dev/logs/ios-tests-20260909-172830-21966.log`). `./scripts/dev run` and `./scripts/dev preview` verified signing, installed, and launched the app; the final simulator capture is `.dev/chat-final.png`. A live deployed stream verified context recall and usage settlement; see backend/DEPLOYMENT.md for its version and measured usage. The preview requires a valid development session or normal Apple sign-in for real API calls.

## Markdown presentation

September 9 readability update: new responses are instructed to use short paragraphs with blank lines,
bullets for related points, numbered steps for sequences, selective bold and italics, and brief headings
for longer answers. Verified quotation text stays verbatim. The app uses bold emphasis and more space
between paragraphs and list items. Existing saved answer text is not rewritten.

The empty-chat carousel selects random references from the complete bundled Bible and resolves their
ESV wording through the same authenticated passage service and cache used by chat. It never displays
the quoter's BSB fallback. A failed refresh keeps the visible ESV verse; if the first load fails, it shows
a temporary-unavailability message and tries again on the next cycle. It pauses outside the active scene
and remembers the last displayed reference across launches to avoid an immediate repeat.

Verification for this update: `./scripts/dev check` passed type checks, 231 backend tests, the Bible index
check, and deployment dry run (`.dev/logs/backend-tests-20260909-192654-98626.log`). The signed app was built,
installed, and opened with `./scripts/dev run` (`.dev/logs/build-Debug-20260909-192730-2196.log`). The home-verse
test fixtures were updated for ESV forwarding and rejection of BSB fallback, but iOS tests and simulator
UI automation were not run. Live response formatting and signed-in ESV display still need manual verification.

The shared answer system prompt includes [writing instructions](../backend/src/writing-style.ts) adapted from the local `stop-slop` skill. Both JSON and streaming answers receive them. They call for plain language, specific pastoral care, varied sentences, and purposeful formatting; they discourage stock validation, filler, formulaic contrasts, and automatic closing questions or prayers. The model must avoid em dashes in its own prose and citation labels, while preserving verified quotations and source URLs exactly. These are generation instructions, not an output rewriting filter; mocked backend checks do not establish live writing quality.

`AnswerMarkdown` uses MarkdownUI 2.4.1, pinned in `project.yml`, for native headings, emphasis, lists, tables, code blocks, and links. This version supports the app’s iOS 17 minimum (the author’s newer Textual package requires iOS 18). Custom Scripture/commentary quotation cards remain separate. Markdown image providers do not fetch remote images, and link opening is limited to the answer’s validated source URLs.

Presentation verification: `./scripts/dev build` passed with signing (`.dev/logs/build-Debug-20260909-181027-2922.log`). The final `./scripts/dev test` run passed all 41 unit tests, including the loading-state, buffering, saved-answer cancellation, and Markdown render tests. The separate contribution wizard UI tests failed during the concurrently changing checkout work (`.dev/logs/ios-tests-20260909-181535-14001.log`); this is not an all-green suite. Light/dark rendering fixtures were inspected at `.dev/answer-presentation-light.png` and `.dev/answer-presentation-dark.png`.


## Submission and failure recovery

September 9 robustness update (released in TestFlight 1.0.1; backend deployed): submission saves the question, clears the draft,
resets the native input identity, and sets the sending state synchronously before starting asynchronous
work. Input callbacks carry a draft revision; callbacks from the submitted field cannot restore stale
text. Validation/storage rejection preserves the draft. Stop before inference begins skips the call.

An unanswered last question has a Retry answer action, including after reopening History. An explicit
retry replaces that question's attempt ID and saves it before sending the same full context, without
adding a duplicate question or clearing a newly typed draft. Retry can consume allowance/funding;
there are no automatic retries after generation starts. The server-only HTTP 429 fallback is described below. Existing reservation rules still reject overlapping requests.

The streaming error envelope now includes an optional status so provider 429 responses retain their
rate-limit meaning. Source validation failures retain `sources_unavailable` through both backend answer
adapters. No unchecked answer is published. Review and streaming logs include failure-stage/status
metadata without conversation text or provider bodies. Streaming redirects now use the same known
unbilled classification as the JSON adapter, settling only any completed review work.

Verification: `./scripts/dev check` passed the index check, TypeScript, 232 Workers tests, and deployment
dry run (`.dev/logs/backend-tests-20260909-204159-80776.log`). Signed build passed
(`.dev/logs/build-Debug-20260909-204053-80326.log`). Added iOS regressions for immediate clearing,
stale keyboard updates, duplicate taps, retry persistence, stop, and error mapping; syntax parsing passed,
but iOS tests and simulator automation were not run per project instructions. Physical-keyboard/UI
verification remains outstanding; release details are recorded below. Production observability confirmed 502 failures,
but its event API failed schema validation and available aggregates did not establish the exact cause
of the reported gambling-question failure. Do not describe that provider incident as resolved.


## Cheaper fallback and allowance clarity

September 9 follow-up, deployed with the TestFlight 1.0.1 upload: answer routing is Gemini 3.8 Flash → GPT-5.6 Luna with low
reasoning. Review routing is Gemini 2.5 Flash Lite → GPT-4.1 Nano, preserving the separate model
and the 128-token decision budget. `model-policy.ts` and `review-policy.ts` own the fixed routes;
`model-routing.ts` tries the next route only for an HTTP 429 without OpenRouter platform-limit headers.
It closes the rejected response before continuing and shares the original abort signal/deadline.
HTTP 200 errors, partial streams, transport failures, 5xx, and moderation/source failures are not retried.

Both fallback providers are pinned to OpenAI through OpenRouter with data collection denied and
required parameters enforced. Luna's route caps are $0.40/M input and $1.80/M output to cover its
long-context tier; its standard listed rates are $0.20/M and $1.20/M. The existing reservation caps
cover both fallback routes, so no allowance, funding, or token budget was increased. OpenRouter's
public model and endpoint catalogs advertised the required parameters on September 9; no paid
inference or live quality test was performed.

The new client sends `2026-09-09-openrouter-fallbacks` and discloses OpenAI in its privacy text.
The backend also accepts `2026-09-09-openrouter-google` but keeps those older clients on Google-only
routes. Deploy the backend before distributing the new client. No database migration or secret change
is required. References: [rate-limit behavior](https://openrouter.ai/docs/api_reference/limits),
[provider routing](https://openrouter.ai/docs/guides/routing/provider-selection),
[model catalog](https://openrouter.ai/api/v1/models).

The reported funding notice was traced to the daily cap: the active account had five settled free
requests on September 10 UTC, ten this month, no paid funding, and no pending reservations. The shared
pool still had funds. Settings now labels the percentage monthly and shows separate daily/monthly free
counts plus the daily reset in local time. Backend 402 errors distinguish daily limit, monthly limit,
and shared pool exhaustion when personal funding cannot cover a request. The daily/monthly limits are
unchanged. History and new-chat toolbar symbols now share centered 44×44 frames and a 22-point font.

Validation: `./scripts/dev check` passed index consistency, TypeScript, 252 Workers tests, and deployment
dry run (`.dev/logs/backend-tests-20260909-205650-11841.log`, bundle
`.dev/logs/backend-bundle-20260909-205706-11841.log`). Signed build passed with Apple sign-in and
Keychain identity verified (`.dev/logs/build-Debug-20260909-205421-9173.log`). Added iOS allowance-error
regressions passed syntax parsing only; iOS tests and UI automation were not run. Device presentation and real fallback quality remain unverified. The backend was subsequently deployed
as `ef1f3f13-2136-4262-9f0a-99ab40e8fde3`, and TestFlight 1.0.1 (6) was uploaded successfully; Apple processing
and phone installation were not verified. See [release record](TESTFLIGHT.md#reliability-update-101).


## Monthly allowance without a daily cap

The user superseded the earlier daily-limit decision: the whole monthly allowance can be used on one
day, and Settings must return to only the usage progress bar and percentage. TestFlight **1.0.2 (7)**
implements the simpler UI and removes unused daily fields/messages from the client. The monthly
allowance remains 30. Extra count, reset, and pending-request explanations are removed from Settings.

Migration `0006_monthly_only_allowance.sql` removes the daily reservation predicate without resetting
existing usage or funding. New ledger rows retain the obsolete `free_daily_limit` field as zero for
schema compatibility; no enforcement reads it. Older apps receive compatible daily summary fields
that represent the entire remaining month, with the monthly reset. The backend is deployed as
`529edd2d-0385-4c3f-bbd8-e7b9c1456931`, and the live SQL trigger confirms no daily limit is enforced.

All 253 Workers tests, type checks, Bible index, and deployment dry run passed
(`.dev/logs/backend-tests-20260909-211515-25863.log`), including thirty free requests on one day and
an existing account spending its remaining twenty that day. Signed Release archiving and TestFlight
upload passed; Apple processing and phone presentation remain unverified. See
[release details](TESTFLIGHT.md#monthly-allowance-update-102). No iOS tests or paid inference were run.
