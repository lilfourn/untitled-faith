# Untitled Faith

iOS 17+ SwiftUI app for Christian faith questions. Native Sign in with Apple connects to a deployed Cloudflare Worker, which verifies Apple credentials and proxies submitted questions to OpenRouter. OpenRouter web search is restricted to approved Bible and commentary sites; the dedicated Bible corpus is not connected.

## Run

Use the developer wrapper for repeatable local work:

```sh
./scripts/dev run          # Build, verify signing, install, and open
./scripts/dev test         # Signed iOS tests in a separate build folder
./scripts/dev check        # Backend checks and a deployment dry run
./scripts/dev doctor       # Tools, dependencies, permissions, simulator state
./scripts/dev auth-check   # Public backend checks without credentials or inference
./scripts/dev archive      # Signed device archive with an automatic build number
./scripts/dev --help
```

The wrapper keeps signing enabled, verifies simulator entitlements inside the executable, and never shuts down or erases simulators. iOS commands use a cooperative lock, with logs in `.dev/logs`. Run builds use `DerivedData/DevApp`; tests use `DerivedData/Tests`, avoiding the old shared artifact folder. Set `FAITH_SIMULATOR` to an existing name or UDID to choose a device. Concurrent agents should use the wrapper for iOS commands.

Use `./scripts/dev run` to generate, build, verify signing, install, and launch on the simulator. `project.yml` is the project source. The authentication screen contains the wordmark and Apple sign-in button. Use the `--preview-chat` launch argument to open the chat preview in Debug builds; the argument is ignored in Release builds.

See [backend setup](backend/README.md) for secrets, deployment, the short-lived development session, and Xcode configuration. Without configuration, the app reports that answers are unavailable. Send submits questions directly without an AI-sharing popup. AI answers are enabled by default; the existing device preference is still respected. No model picker or model label is present.

See [Apple sign-in setup](APPLE_SIGNIN.md) for the configured App ID, key, authentication flow, session behavior, and verification steps. Keep simulator signing enabled when testing Keychain.

See [TestFlight](docs/TESTFLIGHT.md) for release archives, automatic build numbering, uploads, and installation on a phone.

See [Bible text and search](docs/BIBLE.md) for the bundled Berean Standard Bible, ESV quoting through Crossway's API, and offline keyword and semantic search.

See [accounts and usage](docs/ACCOUNTS.md) for the persistent user database, monthly free limits, personal funding balances, and payment integration status. Settings contains an editable profile photo, a usage-remaining bar with Add usage, and Delete account at the bottom. The photo is saved as a 512-pixel thumbnail in Application Support, scoped to the account and backend. It survives app restarts and sign-in, uses atomic writes and iOS data protection, and is excluded from backups. It is never uploaded. Successful account deletion removes the local photo.

## Structure

- `App`: session routing and shared appearance.
- `Features/Authentication`: native Sign in with Apple entry screen.
- `Features/Chat`: conversation state, composer, answer/citation rendering, and the empty-state verse carousel (`HomeVerses` holds 36 ESV quotations).
- `Features/Settings`: locally saved profile photo selection, usage, and account deletion.
- `Features/Legal`: bundled draft Privacy Policy and Terms of Use, accessible before sign-in.
- `Models`: questions, answers, Bible references, and attributed commentary.
- `Services`: native streaming HTTPS answer client, full conversation context, local session files, consent checks, and sanitized errors.
- `Services/Bible`: bundled public-domain Bible (SQLite + FTS5), reference parsing and detection, ESV passage client with a capped device cache, and an on-device semantic verse index. See [Bible text and search](docs/BIBLE.md).
- `backend`: authenticated OpenRouter proxy, request validation, rate limiting, and Workers runtime tests.
- `Untitled FaithTests`: native client request, privacy, error, and context tests.

Conversations are saved on the device, separated by account, and can be reopened or deleted from history. Each request sends the entire conversation plus the latest question; over-limit requests fail explicitly without trimming history. Chat files are excluded from backups and are not synced to the cloud. See [chat sessions and streaming](docs/CHAT.md). Apple credentials are verified by the backend before the app stores a session in device-only Keychain. Account deletion and Apple authorization revocation are available in Settings. The development preview bypass exists only in Debug; Release builds cannot use its environment token. Web citations and quotation blocks link to approved sources; see [web search](docs/WEB_SEARCH.md).

## Brand exploration

The selected app icon is the standalone white glass speech bubble with a centered Latin Christian cross. Its opaque 1024×1024 PNG is installed in `Untitled Faith/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; iOS applies the rounded icon mask. Earlier dark and flat concepts are exploratory history. Manrope and Space Grotesk remain font options; the scaffold currently uses system sans typography.

Gridbloom board: **Untitled Faith · Monochrome identity** (`kx7b9g2t8ey0y2d18e4sj6tchh8e3z7g`). Early wordmark concept sheets are saved in `public/` for review only. These generated images are exploratory presentations, not production app-icon exports.

## Next integration work

1. Apple sign-in is configured and the first real simulator sign-in was confirmed working by Luke. Validate the complete account lifecycle on a physical device before public launch.
2. Add retrieval, licensed Bible translations, and an explicitly approved commentary catalog. BibleProject and GotQuestions are approved web commentary sources; this is not an endorsement by those organizations. Ground answers in retrieved passages, validate citations, and abstain when sources cannot support an answer. Model prompting alone does not enforce Bible-only sourcing. The proxy's fixed model and Google provider allowlist are documented in the backend.
3. Validate the account/usage quota and deletion work before public use. Current access tokens expire within 15 minutes; requests also require an existing account record. Rate limits are approximate and local to each Cloudflare location. The bundled privacy copy covers local conversation persistence.
4. Before App Store submission, validate the implemented deletion flow with a real account, finalize and publish privacy/terms/support pages, complete privacy disclosures, and add store assets. The bundled legal drafts use `untitledfaith@gmail.com`; replace it when the new address is ready.
5. Before public launch, verify actual provider retention/training settings and Cloudflare trace metadata, disable optional prompt logging and product-data-use settings where appropriate, and finalize legal disclosures. The user removed the separate AI-sharing popup from the preview; revisit the explicit-permission flow before App Store submission. The proxy requests `data_collection: deny`, which does not replace checking provider terms and account settings. Do not treat Apple sign-in or acceptance of terms as AI-sharing consent.

## Checks

Run `./scripts/dev check` for backend type checks, Workers tests, and a deployment dry run. Run `./scripts/dev test` for signed simulator tests. Tests mock inference and do not spend OpenRouter credits. Use normal signed simulator builds for Keychain/authentication tests.

Apple references: [native sign-in button](https://developer.apple.com/documentation/signinwithapple/displaying-sign-in-with-apple-buttons-in-your-app), [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
