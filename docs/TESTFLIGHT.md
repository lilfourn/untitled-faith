# TestFlight

Untitled Faith uses internal TestFlight testing for Luke's phone and a private external group for invited testers. This does not publish an App Store release.

- App Store Connect app: [Untitled Faith](https://appstoreconnect.apple.com/apps/6810459093/testflight), Apple ID `6810459093`.
- Bundle ID: `com.lukefournier.UntitledFaith`; team: `BZT8F2M765`.
- SKU: `untitled-faith-ios`; primary language: English (U.S.).
- Internal group: **Personal Testing**, with automatic build distribution enabled.
- External group: **Friends and Family**, with email invitations only. External builds require TestFlight beta review before testers can install them.
- Requires iOS 17 or newer and the TestFlight app on the phone.

## Archive and upload

```sh
./scripts/dev archive
# Use the exact archive path printed by that command:
./scripts/dev upload 'DerivedData/Archives/Untitled Faith-<timestamp>-<build>.xcarchive'
```

Both commands hold the same cooperative lock as local iOS builds. Archives use Release, the physical-device SDK, enabled signing, and `DerivedData/Release`. Archive creation verifies the actual Apple sign-in and Keychain identity. It does not install or launch the app, run simulator tests, or upload anything.

The upload command sends the archive to Apple, allows Xcode to manage distribution signing and provisioning, and uses `Configuration/TestFlightExport.plist`. It uploads symbols and enables Xcode's `manageAppVersionAndBuildNumber`. Builds are eligible for internal testing and submission to external beta review; uploading alone does not submit a build for review or publish an App Store release. Apple processes the build before it can be installed. The original build `3` was uploaded as internal-only and cannot be shared with external groups.

Xcode must be signed in to the configured Apple Developer team. If archiving reports a missing profile, use `FAITH_ALLOW_PROVISIONING_UPDATES=1 ./scripts/dev archive`. Upload already enables provisioning updates. Never disable signing to work around provisioning errors.

## Automatic versioning

`./scripts/dev archive` reserves the next integer build number under the iOS lock. It reads the counter in `.dev/last-build-number` and existing local archives, then chooses a number greater than both. Failed builds consume a number; gaps are harmless. A manual override is available as `./scripts/dev archive 25`, but it must exceed the existing local numbers. The current integer format supports 1–9999.

Xcode manages the final build number during upload to avoid collisions with builds uploaded from other machines. A local counter alone cannot know about remote uploads. If using Organizer instead of the upload command, keep **Manage version and build numbers** enabled.

The public version stays at `MARKETING_VERSION` in `project.yml` (currently `1.0`); change it deliberately for a new product release. Both version fields in the generated Info.plist now reference build settings, so overrides reach the actual app bundle. Do not edit generated version strings in Xcode or `Configuration/Info.plist` directly.

## Install and verify

Luke's existing App Store Connect user is the sole tester in **Personal Testing**. Install TestFlight on the phone and accept the tester invitation. Apple may take time to process an uploaded build.

Use the normal Apple sign-in screen on the phone. Check sign-in, sending a question, opening citations, and restoring the session after closing the app. Preview mode is compiled out of Release. The build uses the deployed backend URL from `project.yml`, and archive/upload does not deploy backend changes.

The app bundles the `CA92.1` required-reason declaration for its private UserDefaults preference. This is separate from App Store privacy labels and the bundled legal drafts. The current client uses Apple's HTTPS, CryptoKit hashing, and Keychain APIs. Build `3`'s export compliance questionnaire was completed in App Store Connect. Future builds set `ITSAppUsesNonExemptEncryption = false` in `project.yml`, so they do not require repeating that questionnaire. Revisit the declaration if client cryptography or dependencies change.

## First upload

On September 9, 2026, version `1.0` build `3` uploaded successfully using Xcode 26.6, completed processing, and cleared export compliance. App Store Connect confirmed **Personal Testing: 1 Tester, 1 Build**, with Luke's status **Invited**. Archive: `DerivedData/Archives/Untitled Faith-20260909-193215-3.xcarchive`. Log: `.dev/logs/testflight-upload-20260909-193233-13294.log`. Build `2` failed Apple's upload validation because orientations were missing; `project.yml` now explicitly supports all four orientations required for iPad multitasking.

Verified signed Release archiving, Apple sign-in/Keychain entitlements, bundled version `3`, orientations, privacy manifest inclusion, backend health (HTTP 200), and rejection of invalid Apple credentials (HTTP 401). Build numbering checks covered increments, recovery from archives, explicit overrides, and invalid/duplicate rejection. Simulator tests and phone sign-in were not run. Next action: Luke accepts the invitation on his iPhone, installs the app, and signs in normally.

## External beta

On September 9, 2026, Caroline was added as the sole tester in the private **Friends and Family** group. Version `1.0` build `4` was uploaded with external-testing eligibility and submitted to TestFlight beta review. App Store Connect confirmed **Waiting for Review**, assigned to both **Personal Testing** and **Friends and Family**. **Automatically notify testers** is enabled, so the external invitation can be delivered after approval. No public invitation link was created.

Archive: `DerivedData/Archives/Untitled Faith-20260909-194947-4.xcarchive`. Successful upload log: `.dev/logs/testflight-upload-20260909-195028-30144.log`. Signed archiving, build `4`, the bundled exempt-encryption declaration, and export options were verified. Review contact details were supplied by Luke and saved in App Store Connect. Review notes explicitly describe native Sign in with Apple and automatic app-account creation; there is no separate app username/password or shared demo account. If Apple requests another review-access method, resolve that request before resubmitting.

Next action: check Apple's beta review result. External testers cannot install until approval. Internal testing remains available while external review is pending.

## References

- [Apple: Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Apple: Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [Apple: Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [Apple: Required-reason privacy declarations](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
