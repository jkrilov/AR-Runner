# TestFlight CI Session Kickoff — 2026-05-16T20:32:00Z

## Request

Joe requested a CI pipeline for TestFlight (pre-release distribution). Context: v0.2 watch app is complete and tested in the simulator with HealthKit integration. His iPhone is not in developer mode, making TestFlight the testing/validation path. Joe wants secrets in GitHub (not local), tag-based release flow, and native tooling (no fastlane).

## What Shipped (PR #21)

Richards delivered end-to-end TestFlight CI:

1. **Workflow:** `.github/workflows/release-testflight.yml`
   - Triggered by pre-release tags: `v*.*.*-*` (e.g., `v0.2.0-rc1`, `v0.2.0-beta3`)
   - Runs serially (concurrency group: release-testflight, no cancel-in-progress)
   - Uses xcodebuild with -allowProvisioningUpdates + App Store Connect API key

2. **Signing Config:** `Config/Signing.xcconfig` (gitignored) + `scripts/bootstrap-signing.sh`
   - Idempotent: with no env, creates placeholder; with `APPLE_TEAM_ID` secret, writes team ID
   - `project.yml` references via configFiles; both support local and CI paths

3. **Version Strategy:** Marketing version from tag; build number from `$GITHUB_RUN_NUMBER`
   - Ensures monotonically increasing build IDs on ASC without state tracking
   - Allows flexible pre-release versioning (alpha, beta, rc, etc.)

4. **Documentation:** `docs/dev/testflight-setup.md`
   - Part A: Manual Apple Developer Portal steps (register bundle IDs, create ASC app record, export cert, create API key)
   - Part B: 7 GitHub Secrets with copy-paste CLI for base64 encoding

5. **Skill:** `.squad/skills/ios-testflight-ci-via-actions/` (reference architecture)

## What Joe Needs to Do Next

**One-time setup (before first workflow run):**
1. `docs/dev/testflight-setup.md` Part A: Register 4 bundle IDs, create ASC app, export cert, create ASC API key (App Manager role)
2. `docs/dev/testflight-setup.md` Part B: Add 7 secrets to GitHub repo (Team ID, ASC API credentials, cert + password, keychain password)
3. Merge PR #21
4. Cut first pre-release tag: `v0.2.0-rc1`

The workflow will then build, sign, and push to TestFlight automatically.

## Seven Secrets

1. `APPLE_TEAM_ID`
2. `APP_STORE_CONNECT_API_KEY_ID`
3. `APP_STORE_CONNECT_API_ISSUER_ID`
4. `APP_STORE_CONNECT_API_KEY_P8`
5. `BUILD_CERTIFICATE_P12_BASE64`
6. `BUILD_CERTIFICATE_P12_PASSWORD`
7. `KEYCHAIN_PASSWORD`

All documented in the setup guide with exact CLI commands.

## Decision Reference

Seven decisions locked in `.squad/decisions.md` (D-RICHARDS-TF-1 through D-RICHARDS-TF-7):
- xcodebuild + ASC over fastlane match
- Tag patterns: pre-release vs. full release
- Version strategy (tag + run ID)
- Signing config (gitignored xcconfig)
- Secrets layout
- Serial concurrency (no cancellation)
- Xcode 16.4 / macos-15 pinning

## What's Out of Scope

- App Store submission flow (v1+)
- fastlane adoption
- Beta-tester automation (manual in ASC for now)
- Notarization (iOS/watchOS don't need it)

## Next Steps

When Joe completes the portal setup and adds secrets, the pipeline is live. Tag and ship.
