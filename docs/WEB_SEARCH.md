# Approved web search

September 9, 2026. The user approved Bible Gateway, YouVersion (Bible.com), ESV.org, BibleProject, and GotQuestions.org. The first three provide Scripture passage sources; BibleProject and GotQuestions provide commentary.

The shared OpenRouter request uses `tools: [{ type: "openrouter:web_search", parameters: … }]` with Exa `fast`, one search allowance, five total results, and 2,000 excerpt characters per result. `allowed_domains` is set on the server. The model chooses whether to search. There is no client model/source override and no unrestricted fallback. Google native search cannot enforce these domain filters, so the engine is explicitly Exa. The older `web` plugin and `:online` shortcut are deprecated.

The backend additionally accepts citations only from HTTPS URLs on the exact approved hosts (or their `www` host). On Bible Gateway, Bible.com, and ESV.org, only passage routes qualify: publisher blogs, YouVersion events, and reading plans cannot become citations. Domain-level search filters may still return those pages; they are excluded from the app’s accepted sources. This validation does not turn arbitrary model prose into verified Scripture.

## Quotations and links

The model first receives [retrieved BSB passages](BIBLE.md) from the complete bundled corpus. It should use those without a paid web search when sufficient. External quotations still require search evidence. All quotations use a blockquote followed by the exact supplied URL. The server matches quoted text to the supplied corpus text or returned web excerpt, normalizing whitespace and typographic quotation marks. It caps third-party commentary at 25 words per source. Verified Scripture quotations have no separate word limit; the existing whole-answer transport bound still applies. Missing source evidence, invented links, unlinked quote blocks, and nonmatching quotations prevent a successful completion. Ordinary prose is model-generated and can still be wrong; the checker is not a semantic verification of every claim or an exhaustive detector of inline quotations.

The response keeps `text` and the legacy empty `scripture`/`commentary` arrays. Optional `sources` contains approved URLs, titles, source IDs, and `scripture`/`commentary` kinds. Optional `quotes` contains exact quotation text, attribution, source ID, and UTF-16 spans in the answer. Raw retrieved excerpts are not sent to the client or stored in D1.

The app renders Scripture quotes in serif text with a SCRIPTURE label. Commentary has an italic block with a COMMENTARY label. Quotation cards show up to 200 characters and a Read more button for longer text. Read more opens a scrollable view of the full stored quote, attribution, and source link. Cited pages also appear below the answer. The network response continues streaming internally while the app shows Thinking…/Writing…. The app reveals the full, formatted answer only after the final `done` event; incomplete output is not published. Metadata is saved with the local conversation, and old conversations without metadata still decode. Follow-up requests continue sending the entire text conversation, including its source URLs.

## Accounting and data handling

The reservation includes tool-selection/synthesis inference, retrieved excerpt input, and the Exa search fee. Actual settlement uses OpenRouter `usage.cost`, which includes search charges; never add the search fee twice. The existing usage ledger and uncertain-charge reconciliation continue to apply. The live upstream probe reported $0.01131625 total against $0.00431625 inference, a $0.007 search difference. Tool-use counters may include calls returning a limit result, so they are not used to independently bill the user.

Search queries can include conversation details and are sent by OpenRouter to Exa. The in-app privacy and Settings copy mention Exa. No new popup, credentials, database table, or additional search account is needed.

## References

- [OpenRouter web search](https://openrouter.ai/docs/guides/features/server-tools/web-search): tool parameters, domain filters, engine limitations, and search pricing.
- [OpenRouter server tools](https://openrouter.ai/docs/guides/features/server-tools): request tool budgets and usage reporting.
- [Citation annotation format](https://openrouter.ai/docs/guides/features/plugins/web-search#parsing-web-search-results): normalized `url_citation` metadata and returned excerpts.

Tests cover restricted domains, deceptive URLs, passage classification, quote/excerpt matching, quote limits, source propagation through SSE, charge settlement, old-file compatibility, and native quote rendering.

Validation logs: `.dev/logs/backend-tests-20260909-175746-75004.log` (94 passed), `.dev/logs/ios-tests-20260909-175746-75003.log` (30 unit and 2 UI tests passed), and `.dev/logs/build-Debug-20260909-175932-79407.log` (signed installed app). The deployed smoke test validated a source-matched GotQuestions quote and settled its combined cost; details are in backend/DEPLOYMENT.md. `.dev/answer-sources-preview.png` is a rendering fixture showing the separate styles, not a real sourced answer.

The passage allowlist includes Bible.com `/bible/compare/BOOK.CHAPTER.VERSES` translation-comparison pages. Retrieved evidence and exact-quote matching remain required; this does not allow reading plans, events, or arbitrary comparison paths.
