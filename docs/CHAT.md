# Local conversations and streaming

September 9, 2026. User decisions: keep conversations on the phone, make them reopenable/deletable, and send the **whole conversation plus the new message on every request**. Do not silently truncate or summarize. The initial harness left retrieval outside its scope; [approved web search](WEB_SEARCH.md) was subsequently added at the user’s request. The two informational notices above the chat were removed at the user's request; storage/privacy details remain in Settings.

The user subsequently removed the “Allow AI answers?” popup. Send now goes directly to the answer service. AI answers default on; Settings has an on/off switch whose value persists on the device. The existing `consentVersion` wire field is retained for compatibility with the deployed API; it is not a record of an explicit popup opt-in.

## Storage and context

`LocalConversationStorage` stores one versioned JSON file per conversation under Application Support. Directories are scoped by a hash of the backend and Apple app-specific identity, with a separate preview namespace. Files use atomic replacement and iOS data protection, and the directory is excluded from backups. There is no cloud chat table, sync service, or new D1 migration.

The app opens to a new, empty conversation after launch/sign-in. Previous conversations remain in History and open only when selected. New conversation preserves the previous chat. History supports reopening and confirmed deletion. Signing out retains local chats for that identity; successful account deletion removes that identity's local chat directory on this device after the active send stops. Removing the app removes its files. Other devices retain their own files.

The question is saved before inference starts. The app shows shimmering Thinking… text while awaiting output, then Writing… when content starts arriving. Provider deltas stay offscreen until a valid final response arrives. The full response is saved before its formatted reveal begins. Interrupted requests retain the question without publishing unfinished answers. Stopping the visual reveal shows the already-saved full answer. Requests are never automatically retried; unreadable files are preserved and reported.

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
