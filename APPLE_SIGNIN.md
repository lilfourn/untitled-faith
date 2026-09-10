# Sign in with Apple

## Configured resources

- Apple Developer team: `BZT8F2M765` (Luke Fournier).
- Native App ID: `com.lukefournier.UntitledFaith`, with Sign in with Apple enabled as a primary App ID.
- Key name: **Untitled Faith Sign In**. Key ID: `4ADZN888UW`. Its only enabled service is Sign in with Apple, associated with this App ID.
- Backend: `https://untitled-faith-proxy.vendors-c0f.workers.dev` in Cloudflare account `c0f96de71bdc54889c1ad27ccc90dfc0`.
- Server secrets: `APPLE_PRIVATE_KEY`, `SESSION_SIGNING_KEY`, `SESSION_ENCRYPTION_KEY`, and the existing `OPENROUTER_API_KEY`.
- The Apple key backup is at `~/.local/share/untitled-faith/keys/AuthKey_4ADZN888UW.p8` with file mode `0600` inside a `0700` directory. The original download is also restricted to `0600`. Never commit the key or put it in the app.

This is native iOS Sign in with Apple. A web Services ID, redirect URL, or email relay configuration is not needed for this implementation. The app requests Apple’s full-name scope, reads only `fullName.givenName`, and sends that first name with the credential exchange. It does not request email or transmit the family name. The backend validates the optional first name and stores it only after Apple identity verification and code exchange succeed. Later sign-ins that omit the name preserve the saved value. Apple may omit names on later authorizations, so existing accounts without a captured name remain unnamed until Apple supplies one; there is no name lookup from an access token.

## Flow

1. The app creates a cryptographically random nonce and state. It sends the nonce's SHA-256 digest to Apple and checks the returned state locally.
2. The app sends the identity token, one-use authorization code, and original nonce to `POST /v1/auth/apple` over HTTPS.
3. The Worker verifies Apple's signature, issuer, audience, expiration, nonce, and code hash when provided. It exchanges the code with Apple and verifies that the resulting identity matches before issuing a session.
4. The app receives an access token with a maximum 15-minute lifetime and an encrypted renewal envelope with a maximum 30-day lifetime. Apple's raw refresh token is sealed for the server; the envelope and app-specific Apple identifier are stored in device-only Keychain storage.
5. `POST /v1/auth/refresh` renews the app access token. It rechecks Apple no more than once per day for the current envelope, per Apple's guidance. The app also checks Apple's local credential state on restoration/activation and listens for revocation notifications.
6. Sign out clears this device's Keychain session and local conversation. Delete account calls `POST /v1/auth/revoke` to revoke Apple's authorization and remove its account record, then clears the local session. The account/usage implementation stores an opaque account ID and hashed Apple identity in D1; no chat content is stored. Outstanding funding or usage must be resolved before deletion.

The AI-sharing popup was removed at the user’s request. AI answers default on, with a device-persisted switch in Settings. The backend loads the first name from the authenticated account and includes it as profile data in both streamed and regular answer prompts. An opaque account ID remains the provider’s user identifier; Apple identifiers and credentials are not passed to OpenRouter. No name is inferred from conversation content. Migration `0004_account_first_name.sql` is required before deploying this change.

## Run and verify

`project.yml` supplies the public `FAITH_API_BASE_URL` and derives `ANSWER_PROXY_URL`. Both are explicitly written into `Configuration/Info.plist` by XcodeGen. To point at another deployment, update the public URL in `project.yml` or override the build settings. Never put secrets in those settings.

```sh
./scripts/dev run
./scripts/dev test
./scripts/dev auth-check
```

Keep signing enabled for authentication/Keychain tests. `CODE_SIGNING_ALLOWED=NO` caused the Keychain test to fail in this project. Simulator entitlements are embedded in Mach-O `__TEXT,__entitlements`; an empty `codesign --display --entitlements` dictionary alone does not prove they are missing. The wrapper validates the signed bundle and its embedded simulator identity. A signed physical-device build and provisioning profile also contain `com.apple.developer.applesignin = [Default]`.

From `backend`, use `npm run check`, `npm test`, and `npm run deploy:check`. Tests use mocked Apple and inference endpoints. The live health endpoint and invalid-credential rejection have been checked. Luke confirmed the first full Apple sign-in working in the simulator after the backend network-call fix.

## Operations and remaining launch work

The `.dev.vars` file contains local copies of server secrets and is ignored/restricted to `0600`. Upload secrets through Wrangler stdin or its protected secret-file mechanism; never put secret values in command arguments. `npm run deploy` preserves configured server secrets.

Sign-out removes the local session; its access token otherwise lasts until its short expiration. The account/usage work now also checks that the account exists before allowing authenticated requests. There is no per-session inventory or denylist. Daily Apple checks are not a substitute for server-to-server account-change notifications if the product needs immediate handling of external Apple revocations. Validate those controls and account-wide spending limits before public launch.

## Known development failures

- An unsigned artifact can overwrite a shared build folder. Use the wrapper's isolated build folder and entitlement check before installing.
- Calling native Workers `fetch` as a class property method throws `Illegal invocation`. `AppleClient` wraps the native call in an arrow function, and its tests enforce the native receiver rule. Server redirect handling also uses the runtime-supported manual mode and rejects redirects.
- Overlaying a custom label on a system Apple button can reveal both labels when the view dims. The current control renders one label and invokes `ASAuthorizationController` directly, anchored to its own window.

The 30-day renewal lifetime is fixed at sign-in and is not extended by refreshing. A fresh Apple authorization is required after expiration. Replacing `SESSION_ENCRYPTION_KEY` invalidates stored renewal envelopes; replacing `SESSION_SIGNING_KEY` invalidates current access tokens. Plan rotations deliberately.

Legal pages remain drafts and describe the implemented data flow. Finalize public policy URLs, App Store privacy disclosures, and the app's remaining launch requirements separately.

## Apple references

- [Native app setup](https://developer.apple.com/documentation/authenticationservices/implementing-user-authentication-with-sign-in-with-apple)
- [Verifying a user](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)
- [Token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens)
- [Token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens)
