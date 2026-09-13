# Returning-user launch

September 13, 2026. Luke reported that opening the app while already signed in felt rough and asked
for research into smoother loading. These findings come from the current launch code, not an
Instruments recording or a measured signed-in launch.

## Findings

- `ContentView` initially selected `SignInView` because authentication had not yet been restored.
  Restoration then replaced that screen with chat.
- Chat was constructed before token renewal finished. Its photo loaded in a separate view task,
  and its first ESV verse appeared later without a transition.
- Each `ChatView` initializer created a quoter/cache and a `ChatStore`. The store immediately read
  every conversation file on the main actor. SwiftUI can initialize view values repeatedly even
  when it preserves their state.
- Independent launch/activation tasks could overlap. Activation could repeat the Apple credential
  check and usage refresh that restoration had just performed.
- The carousel replaced its verse immediately on every foreground activation.
- The generated system launch screen used the system background; the app used different grays.

## Implemented behavior

The system launch screen and app share the `AppBackground` light/dark asset. A neutral progress
screen stays visible while the initial session is resolved. Only a resolved signed-out state
displays sign-in. Apple verification, renewal, expiry, revocation, and deletion rules still apply.

Overlapping activations await one session task, including when an earlier scene task is cancelled.
Restoration checks Apple once; later foreground activations continue to check for revocation.
Usage refresh runs in the background.

`ChatHomeView` prepares resources once per account. Conversation indexing, photo loading, passage
cache decoding, and opening the bundled Bible happen outside the main actor. The prepared index
retains unreadable-file notices, and chat still opens to a fresh conversation with saved chats in
History. Prepared resources are discarded if that account's view disappears during loading.

Chat lays out behind the loading screen with interaction and accessibility hidden. Once local
preparation finishes, the first ESV request gets **up to 1.5 seconds** before chat is revealed. A
completed request, including an unavailable result, releases it immediately. This is an upper
bound for optional verse loading, not a minimum delay or a timeout for authentication. If the
request is slower, the composer becomes available and the verse placeholder remains until its
request finishes. The existing authentication request timeout remains 25 seconds.

The reveal uses a **0.25-second fade**, disabled by Reduce Motion. A late first verse also fades
in. Returning from the background keeps the visible verse and restarts its ten-second cycle;
it does not replay startup. A new launch still chooses a fresh ESV verse from the complete Bible,
excluding the last reference. No additional passage cache or stored ESV text was introduced.

## Verification

- `./scripts/dev build`: passed; Apple sign-in and Keychain entitlements verified.
  Log: `.dev/logs/build-Debug-20260913-163003-58364.log`.
- `./scripts/dev build-tests`: passed compilation of the signed test bundles, including new
  activation overlap/cancellation and prepared-history regression cases.
  Log: `.dev/logs/ios-test-build-20260913-163029-59469.log`.
- `./scripts/dev run`: final signed build installed and launched normally in the iPhone 17
  simulator. Log: `.dev/logs/build-Debug-20260913-163228-65913.log`.
- `git diff --check`: passed.
- iOS tests, simulator UI automation, visual signed-in verification, and Instruments measurements
  were not run. The project requires Luke's explicit request for tests and simulator UI automation.

Manual follow-up: cold launch with a valid saved session; launch with an expired access token;
slow/offline passage loading; background/foreground during restoration; saved photo; large history;
light/dark appearance; Reduce Motion. Use Instruments' App Launch template to measure real startup
and main-thread stalls before claiming a latency improvement. The system launch screen follows
device appearance; a saved in-app appearance override applies once SwiftUI starts.

## Apple guidance

- [Launching](https://developer.apple.com/design/human-interface-guidelines/launching): keep launch
  brief and make the launch screen resemble the first app screen.
- [Loading](https://developer.apple.com/design/human-interface-guidelines/loading): show placeholders
  and progress when needed, and keep other actions available during background loading.
- [Reducing launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time):
  prepare the initial view's data, defer other work, keep the main thread available, and measure
  the launch and subsequent preparation rather than judging only the first frame.
- [UILaunchScreen](https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen):
  configure the system launch background with the `UIColorName` asset name.
