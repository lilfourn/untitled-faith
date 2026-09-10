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
# For a big update instead: ./scripts/dev archive big
# Use the exact archive path printed by that command:
./scripts/dev upload 'DerivedData/Archives/Untitled Faith-<timestamp>-<build>.xcarchive'
```

Both commands hold the same cooperative lock as local iOS builds. Archives use Release, the physical-device SDK, enabled signing, and `DerivedData/Release`. Archive creation verifies the actual Apple sign-in and Keychain identity. It does not install or launch the app, run simulator tests, or upload anything.

The upload command sends the archive to Apple, allows Xcode to manage distribution signing and provisioning, and uses `Configuration/TestFlightExport.plist`. It uploads symbols and enables Xcode's `manageAppVersionAndBuildNumber`. Builds are eligible for internal testing and submission to external beta review; uploading alone does not submit a build for review or publish an App Store release. Apple processes the build before it can be installed. The original build `3` was uploaded as internal-only and cannot be shared with external groups.

Xcode must be signed in to the configured Apple Developer team. If archiving reports a missing profile, use `FAITH_ALLOW_PROVISIONING_UPDATES=1 ./scripts/dev archive`. Upload already enables provisioning updates. Never disable signing to work around provisioning errors.

## Automatic versioning

Every new `./scripts/dev archive` advances the visible version and reserves a build number under the iOS lock. Luke's small/big update convention uses Apple's three-component version format:

- `./scripts/dev archive` (or `archive minor`): small update, `1.0` → `1.0.1` → `1.0.2`.
- `./scripts/dev archive big`: big update, `1.0.2` → `1.1.0`, resetting the patch component.

The script updates `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` before generating Xcode's project. Commit these generated release-setting changes with the release. It also checks existing local archives to avoid moving backwards after switching checkouts. Version components are integers: `1.0.9` advances to `1.0.10`. Ordinary builds and runs do not advance the version. Uploading or retrying the same archive preserves its visible version; create a new archive for changed code. Failed archives consume their reserved version and build; gaps are harmless.

Build numbers still increase independently. The script reads `.dev/last-build-number` and existing local archives, choosing a number greater than both. A manual build override is available as `./scripts/dev archive minor 25` (legacy `archive 25` also works), but it must exceed existing local numbers. The integer format supports 1–9999.

Xcode manages the final build number during upload to avoid collisions with builds uploaded from other machines. A local counter alone cannot know about remote uploads. If using Organizer instead of the upload command, keep **Manage version and build numbers** enabled.

Both version fields in the generated Info.plist reference build settings. Archiving checks the actual app bundle against the reserved version and build and fails if they differ. Settings displays the installed version and build to help identify updates. Do not edit generated version strings in Xcode or `Configuration/Info.plist` directly. Verify the numbering helper locally with `python3 -B scripts/test-release-version.py`; this does not run iOS tests or access the simulator.

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

## Reliability update 1.0.1

On September 9, 2026, version **1.0.1 (build 6)** uploaded successfully to App Store Connect. This is a
patch release with prompt clearing, retry for unanswered questions, cheaper provider fallback, clearer
daily/monthly allowance display, specific backend errors, and evenly sized chat toolbar icons. It also
includes the automatic patch-version release workflow and installed version/build display in Settings.

Archive: `DerivedData/Archives/Untitled Faith-20260909-210225-6.xcarchive`.
Archive log: `.dev/logs/archive-20260909-210225-15224.log`.
Upload log: `.dev/logs/testflight-upload-20260909-210428-16531.log`.
The actual archive version/build, Apple sign-in, and Keychain identity were verified. Six local release
versioning tests and all 252 backend tests passed. No iOS tests, simulator UI automation, or paid inference
were run. The matching backend was deployed before upload, retaining existing secrets and supporting
older clients as well as the updated provider disclosure.

Apple accepted the upload; processing completion and device installation have not been verified.
Personal Testing has automatic distribution enabled. This upload does not submit the new build to
external beta review or publish an App Store release.

## Monthly allowance update 1.0.2

On September 9, 2026, version **1.0.2 (build 7)** uploaded successfully to App Store Connect.
The daily five-request restriction is removed: users may use the whole monthly allowance in one day.
Settings returns to its single usage progress bar and percentage, without the added daily/monthly
counts or reset explanations. The monthly allowance remains 30 free requests.

Archive: `DerivedData/Archives/Untitled Faith-20260909-211542-7.xcarchive`.
Archive log: `.dev/logs/archive-20260909-211542-25987.log`.
Upload log: `.dev/logs/testflight-upload-20260909-211700-26887.log`.
The archive's version/build, Apple sign-in, and Keychain identity were verified. All 253 backend tests,
TypeScript, Bible index, and deployment dry run passed. The database migration and matching Worker
were deployed before upload; the live trigger was checked to confirm removal of daily enforcement.
No iOS tests, simulator UI automation, or paid inference were run. Apple accepted the upload for
processing; processing completion and phone installation were not verified. Internal automatic
TestFlight distribution remains enabled; this upload does not submit external beta review.

## Native toolbar update 1.0.3

On September 9, 2026, version **1.0.3 (build 8)** uploaded successfully to App Store Connect.
Chat history and compose are now native `ToolbarItemGroup` buttons with icon-only system labels.
History uses `clock`; compose uses `square.and.pencil`. The custom 22-point font, 44-point label frames,
and HStack grouping are removed so iOS controls symbol scale, spacing, and toolbar presentation.

Archive: `DerivedData/Archives/Untitled Faith-20260909-213745-8.xcarchive`.
Archive log: `.dev/logs/archive-20260909-213745-38267.log`.
Upload log: `.dev/logs/testflight-upload-20260909-213828-38879.log`.
Signed Release archiving passed, with version/build, Apple sign-in, and Keychain identity verified.
Apple accepted the upload for processing. No iOS tests or simulator UI automation were run, and actual
phone appearance/processing completion have not been verified. This client-only change required no
backend deployment. Personal Testing retains automatic distribution; external beta review is separate.

## References

- [Apple: Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Apple: Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [Apple: Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [Apple: Required-reason privacy declarations](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
