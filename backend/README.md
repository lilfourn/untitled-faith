# Answer proxy

See [deployment status](DEPLOYMENT.md) for the current server-secret configuration and remaining activation steps.

See [accounts and personal funding](../docs/ACCOUNTS.md) for D1 migrations, monthly limits, billing reservations, reconciliation, and contribution integration boundaries. Answer requests require an `Idempotency-Key`; `GET /v1/me/usage` returns the signed-in user's remaining usage.

The iOS app sends `POST /v1/answers` to this Worker over HTTPS. The Worker verifies an app session, checks the request version marker and limits, calls OpenRouter, and returns answer text plus approved source links and checked quotation metadata. OpenRouter's key and the session signing keys exist only on the server. The public authentication endpoints issue sessions only after verified Apple authorization or a valid encrypted renewal envelope. There is no model-selection field. See [Apple setup](../APPLE_SIGNIN.md).

The fixed answer model is `google/gemini-3.8-flash`, verified against OpenRouter's catalog on September 9, 2026. Allowed provider families are `google-ai-studio` and `google-vertex`. Routing requests `data_collection: deny`. If the model or eligible providers are unavailable, the request fails; it never falls back to a different model. The app displays no model branding or routing metadata. A prompt asks the assistant not to volunteer implementation details; prompting alone cannot guarantee that generated prose never mentions a model.

Answers now include a server-validated topic/safety decision before text is released. Difficult questions and criticism of Christianity remain allowed; unrelated tasks receive a brief redirect, harmful requests receive a safe refusal, and current danger receives supportive crisis guidance. An independent `google/gemini-2.5-flash-lite` request reviewer checks relevance and safety in full conversation context before answer generation; the answer model also checks its output. Both use the same approved Google providers. Classification can still be wrong. See [content policy and evaluation](../docs/CONTENT_POLICY.md) for boundaries, fixed responses, billing, and live checks. Independent review and the Scripture quotation fixes were deployed on September 9, 2026; see [deployment status](DEPLOYMENT.md).

## Local setup

Use Node 22.12+ and npm. From this directory:

```sh
npm ci
cp .dev.vars.example .dev.vars
openssl rand -hex 32
```

Put the generated random value in `SESSION_SIGNING_KEY` in `.dev.vars`, and put your OpenRouter API key in `OPENROUTER_API_KEY`. This ignored file stays local. Never paste either into Swift, Info.plist, an Xcode scheme, or a client request.

```sh
npm run types
npm run check
npm test
npm run dev
```

Wrangler serves the local backend at `http://localhost:8787`. `GET /health` reports process health, not upstream readiness. Tests run in the Workers runtime with fake credentials and mocked inference; no paid requests occur. The test runner may warn that local secrets are missing before the test bindings are applied. Apply all D1 migrations, including `0005_request_review_usage.sql`, before deploying independent review.

In another terminal, `npm run session:dev` prints a development app session valid for 15 minutes. It has only the `answers` scope and is signed locally. This is an operator harness, not user authentication. For a local HTTP smoke request, supply that session as a bearer token and the JSON below to `/v1/answers`; this sends the example question to the real provider and consumes credits when your key is configured.

## Deploy and connect Xcode

The configured Cloudflare account is pinned in `wrangler.jsonc`. The deployed Worker is `untitled-faith-proxy`, with rate-limit namespaces `90817001` for answers and `90817002` for authentication. The Apple and OpenRouter server secrets are provisioned. See DEPLOYMENT.md.

```sh
npm run deploy:check
npx wrangler deploy --secrets-file .dev.vars
```

The second command deploys code and the secrets in the protected local file. There are four server secrets: the OpenRouter key, session signing key, session encryption key, and Apple private key. A fifth server secret, `ESV_API_KEY`, is now provisioned and enables exact ESV passages at `GET /v1/passages` and verified ESV context before answer generation (see `../docs/BIBLE.md`). The local setup above must also supply the two additional authentication secrets described in `../APPLE_SIGNIN.md`. Do not rotate existing session keys accidentally. Set an OpenRouter key spending limit before enabling public requests. Cloudflare's per-location rate limiter is not a global spending quota.

In Xcode's local Debug scheme:

- Add launch argument `--preview-chat`.
- Set `FAITH_PROXY_URL` to `https://<your-worker-host>/v1/answers`.
- Set `FAITH_PROXY_SESSION_TOKEN` to the short-lived token from `npm run session:dev` using the matching server signing key. Mint another token when it expires.
- Launch the app, enter a question, and tap Send. There is no separate AI-sharing popup.

Keep the development token in an unshared local scheme. The app reads it only in Debug preview mode. Normal builds use the public `FAITH_API_BASE_URL` build setting and obtain sessions through verified Apple credential exchange, with Keychain storage/restoration and authorization revocation. Real user authentication is required in Release.

`URLSession` uses HTTPS with normal certificate verification, an ephemeral session, no cache/cookies, and refuses redirects. No ATS exceptions are added. Use the deployed HTTPS URL for simulator/device testing; the app deliberately rejects local plain HTTP too. For a future sandboxed native macOS target, enable the outgoing network client entitlement on that target. The current project targets iPhone and iPad.

## Contract and boundaries

Request, with `Authorization: Bearer <app-session>` and `Content-Type: application/json`:

```json
{
  "consentVersion": "2026-09-09-openrouter-google",
  "messages": [{ "role": "user", "content": "How can I begin reading the Bible?" }]
}
```

Successful response:

```json
{
  "answer": { "text": "…", "scripture": [], "commentary": [] },
  "requestID": "opaque-request-id"
}
```

Errors contain only `{ "error": { "code": "…" }, "requestID": "…" }`. The API never forwards upstream headers, error messages, usage, provider IDs, or model fields. Message text is untrusted conversation content, not authority to change server configuration. The app-specific session subject sent upstream must be opaque; never use an Apple user identifier, email, or credential as the subject. The development harness uses `development-preview`.

Limits: 1 MiB request body, at most 1,000 messages, 8,000 UTF-16 units per message and 200,000 total; 10 requests per minute per subject per Cloudflare location; 2,048 output tokens; 45-second deadline shared by review and answer inference; 128 KiB JSON completion or 2 MiB SSE upstream cap. The client sends the **entire conversation plus the new question**, in order. It never drops older context; reaching a request limit asks the user to start a new conversation. Every request still requires its existing stable idempotency key and usage reservation. There are no automatic retries that could duplicate paid generations.

The app requests `Accept: text/event-stream`. The Worker emits JSON `data:` frames with `type: start`, `delta` (with `text`), `done` (with the final `answer`), or `error` (with a sanitized `error.code`). Only `done` means completion. The Worker buffers the structured upstream content until moderation and source checks pass, then settles usage before sending the approved text in one `delta` and `done`. Transport EOF, a provider error, or a non-stop finish fails without publishing partial generated text. Requests with a JSON Accept header retain the original JSON response for compatibility. See [the chat harness](../docs/CHAT.md) for persistence and protocol details.

Operational application logs contain only event, random request ID, status, and duration. Questions, answers, authorization headers, and user IDs are not logged by application code. Cloudflare logs/traces and provider metadata policies still need production review. The backend does not persist chats; the iOS app saves them locally. The device remembers the AI answers switch in Settings; switching it off stops subsequent sends and cancels the active client task where possible. The legacy `consentVersion` field remains an API compatibility marker and does not establish explicit consent. It cannot recall already transmitted data.

Before inference, the backend searches a bundled index of the complete public-domain BSB, fetches up to three selected ESV passages directly from Crossway in one bounded batch, and adds verified passages and a Bible overview to model context. The Crossway key stays in the Worker; only references are sent to Crossway and only passage text/metadata are sent to the model. This adds no paid retrieval service or extra model round. Direct references, surrounding verses, keyword ranking, and editorial topic guides are described in [Bible retrieval](../docs/BIBLE.md). The entire conversation is retained; the actual added context and independent review are included in the usage reservation. Review costs are checkpointed before the answer call and settled together as one question.

OpenRouter web search remains available with Exa and the approved source catalog when the Bible evidence is insufficient or external commentary is needed. The legacy `scripture` and `commentary` arrays remain empty for compatibility; `sources` and `quotes` carry bundled Bible or web citations and quotation blocks. Direct quotation blocks must match the supplied evidence and include its exact URL. Bundled quotations must be labeled BSB. This validates quotations, not every claim in generated prose. See [web search](../docs/WEB_SEARCH.md).

## References

- [OpenRouter model](https://openrouter.ai/google/gemini-3.8-flash), [provider routing](https://openrouter.ai/docs/guides/routing/provider-selection)
- [Apple HTTPS / ATS](https://developer.apple.com/documentation/security/preventing-insecure-network-connections), [AI data-sharing guideline 5.1.2](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing)
- [Workers secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [rate limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [runtime tests](https://developers.cloudflare.com/workers/testing/vitest-integration/write-your-first-test/)

The `sharp` development dependency override keeps the local Worker tooling on a patched release. It is not part of the deployed Worker bundle.
