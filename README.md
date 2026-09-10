# Untitled Faith

A native iPhone and iPad app for exploring the Bible, asking difficult questions about Christianity, and growing in faith.

Untitled Faith combines a SwiftUI interface with Scripture retrieval and AI-assisted explanations. The app takes a Scripture-first approach, identifies differences between Christian traditions, and asks the reader to weigh interpretations against the biblical text.

## Mission

I created this app to use my skills for the glory of God. After spending so much time building applications, I felt called to build something that serves His kingdom. This has been on my heart for a while, and I want to give my time, my work, and my abilities fully to the Lord.

## Features

- **Faith conversations:** Ask questions about Scripture, theology, Christian history, and living out your faith, with follow-up questions in the same conversation.
- **Scripture grounding:** The backend retrieves relevant passages from the bundled Berean Standard Bible and requests verified ESV text from Crossway when configured.
- **Source-linked explanations:** Read citations and quotation blocks from approved Bible providers, historical writings, and theological references.
- **Deeper theological study:** Explore subjects such as the Trinity, salvation, predestination, suffering, sacraments, and objections to Christianity.
- **Personal conversation history:** Reopen or delete conversations saved on your device and separated by account.
- **Native account access:** Sign in with Apple, view usage, manage your profile, and request account deletion.

## Scripture and sources

Scripture is the app's final authority for spiritual and doctrinal conclusions. Other sources serve as fallible teaching and research aids. The answer instructions distinguish biblical statements, interpretation, a tradition's teaching, and speculation, with uncertainty explained beside the affected claim.

The source catalog includes Bible Gateway, YouVersion, ESV.org, BibleProject, GotQuestions, historical Christian texts, denominational confessions, biblical studies, and philosophical references. Consultation does not imply agreement with every source or endorsement of the app by those organizations.

The backend checks quotation wording against retrieved evidence and restricts citation URLs to approved sources. These checks do not verify every claim in generated prose. AI-assisted answers can be mistaken and should support personal study, prayer, and conversation with a local church.

See the [source catalog and theology policy](docs/THEOLOGY.md), [Bible retrieval documentation](docs/BIBLE.md), and [citation validation rules](docs/WEB_SEARCH.md).

## Project status

Untitled Faith is in active development, with release history documented in the [TestFlight guide](docs/TESTFLIGHT.md). This repository describes the current source code; the deployed backend may run an earlier revision. See [deployment status](backend/DEPLOYMENT.md) for the published backend version.

Stripe Checkout with Apple Pay and separate usage/developer accounting are implemented locally. Production purchases remain disabled pending the separate Untitled Faith Stripe account setup and end-to-end validation. See [payments](docs/PAYMENTS.md) for activation status.

## Development

### Requirements

- macOS with Xcode and an iOS 17 or later simulator.
- XcodeGen to generate the Xcode project from `project.yml`.
- Node.js 22.12 or later and npm for the backend.
- Python 3 for the Bible index tooling.
- Apple signing configuration and backend credentials for authenticated app use.

### Get started

1. Clone the repository and install backend dependencies:

   ```sh
   git clone https://github.com/lilfourn/untitled-faith.git
   cd untitled-faith
   npm --prefix backend ci
   ```

2. Follow [backend setup](backend/README.md) and [Sign in with Apple setup](APPLE_SIGNIN.md). For your own installation, configure your Apple team, app identifiers, and backend URL in `project.yml`.

3. Check your development environment and launch the app:

   ```sh
   ./scripts/dev doctor
   ./scripts/dev run
   ```

Use `project.yml` as the Xcode project source and `./scripts/dev` for routine iOS work. The wrapper coordinates builds with a shared lock, keeps signing enabled, and saves logs under `.dev/logs`. Set `FAITH_SIMULATOR` to an existing simulator name or UDID to choose a device.

Store server secrets in the ignored `backend/.dev.vars` file or Cloudflare secrets. Keep credentials out of Swift files, Xcode project settings, and commits. The native client uses HTTPS; see backend setup for development connectivity.

### Common commands

| Command | Purpose |
| --- | --- |
| `./scripts/dev run` | Generate, build, verify signing, install, and launch the app |
| `./scripts/dev check` | Verify the Bible index, type-check the backend, run Workers tests, and validate a deployment dry run |
| `./scripts/dev test` | Run signed iOS tests in a separate build folder |
| `./scripts/dev doctor` | Check tools, dependencies, configuration, and simulator state |
| `./scripts/dev auth-check` | Check public backend health and invalid-credential rejection |
| `./scripts/dev archive` | Create a signed release archive and advance the patch version and build number |
| `./scripts/dev --help` | Show available commands and options |

Backend tests mock inference and do not spend model credits. Live answer requests use the configured provider account. Keep signing enabled for Apple sign-in and Keychain verification.

## Architecture

The SwiftUI client communicates over HTTPS with a Cloudflare Worker. The Worker verifies the app session, reviews the request, retrieves Bible evidence, and requests an answer through OpenRouter. Approved web search uses Exa. The backend validates the response and source metadata before releasing the answer to the client.

| Location | Responsibility |
| --- | --- |
| `Untitled Faith/App` | Session routing and shared appearance |
| `Untitled Faith/Features` | Authentication, chat, settings, contributions, and legal screens |
| `Untitled Faith/Models` | Conversations and answer metadata |
| `Untitled Faith/Services` | Networking, authentication, local storage, and Bible access |
| `Untitled Faith/Resources` | Assets and bundled Bible data |
| `backend/src` | Authentication, answer generation, retrieval, source validation, and usage accounting |
| `backend/test` | Workers runtime tests |
| `Untitled FaithTests` | Native app tests |
| `scripts` | Development, release, and Bible data tooling |
| `docs` | Feature documentation, policies, and release records |

## Privacy and data handling

The app stores conversation history on the device, separates it by account, and excludes chat files from backups. Each answer request sends the full conversation to the backend and model provider. Web search queries may include conversation details. The backend does not persist chat history; it maintains account and usage records.

The app stores authentication sessions in device-only Keychain. Profile photos remain on the device. You can manage saved conversations from chat history and control AI answers or request account deletion in Settings.

See [chat storage and transport](docs/CHAT.md), [accounts and usage](docs/ACCOUNTS.md), and [backend data handling](backend/README.md) for implementation details. Bundled legal documents remain drafts pending public-release review.

## Documentation

- [Bible text, retrieval, and translation handling](docs/BIBLE.md)
- [Theology sources and evidence standards](docs/THEOLOGY.md)
- [Answer style and passage context](docs/EXPLANATIONS.md)
- [Topic and safety policy](docs/CONTENT_POLICY.md)
- [Backend setup](backend/README.md)
- [Sign in with Apple](APPLE_SIGNIN.md)
- [TestFlight and release workflow](docs/TESTFLIGHT.md)

## Contributing

Issues and focused pull requests are welcome. Describe the problem, the proposed change, and how you verified it. For changes to theological explanations or source selection, include supporting references and identify relevant differences between traditions.

Read [AGENTS.md](AGENTS.md) before making changes. Run the checks relevant to your work, preserve signing for authentication testing, and keep secrets and personal data out of issues, logs, and commits.
