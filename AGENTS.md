# Project workflow

- Read current files before editing; multiple agents can work in this checkout. Preserve concurrent changes.
- `project.yml` is the Xcode project source. Use `./scripts/dev` for routine iOS work so XcodeGen/builds share a cooperative lock.
- New releases use `./scripts/dev archive` for small updates (patch increment, e.g. 1.0.1), or `./scripts/dev archive big` for big updates (e.g. 1.1.0). The wrapper advances visible version and build in `project.yml`; commit those release settings. Retry uploads with the same archive to keep its version.
- `./scripts/dev run` builds, verifies signing, installs, and launches. Never disable signing for Apple login or Keychain verification.
- Do not start `./scripts/dev test` or simulator UI automation automatically. Luke must explicitly request it. For manual verification, open the app normally and use actual sign-in; preview mode is not a substitute for signed-in verification.
- When requested, `./scripts/dev test` uses a separate build folder. Do not shut down or erase the user's simulator, and do not uninstall the app to refresh a build.
- `./scripts/dev check` runs backend type checks, Workers tests, and a deployment dry run. It does not deploy or perform paid inference.
- Use `./scripts/dev doctor` for tool/dependency diagnostics. Logs are under `.dev/logs`.
- Server secrets belong in protected, ignored `.dev.vars` or Cloudflare secrets. Never print them, embed them in Swift/configuration, or rotate them incidentally.
- Coordinate changes to shared authentication, billing/account storage, and deployment files. See `APPLE_SIGNIN.md` and `backend/DEPLOYMENT.md` for setup and deployment state; verify current code before relying on older results.
