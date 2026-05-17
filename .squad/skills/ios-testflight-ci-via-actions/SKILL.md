# Skill: iOS TestFlight CI via GitHub Actions

**Owner:** Richards
**Created:** 2026-05-15
**Last updated:** 2026-05-16T20:09:22-04:00

---

## Purpose

Reference guide for wiring an Apple Watch + iOS app to a GitHub Actions CI/CD pipeline: automated build validation (ci-build.yml), security analysis (codeql.yml), and TestFlight distribution (release-testflight.yml). Captures patterns, pitfalls, and the specific traps that have burned us on this project.

---

## Architecture Overview

Three workflow files serve distinct roles:

| Workflow | Trigger | Runner | Purpose |
|---|---|---|---|
| `ci-build.yml` | PR + push to main | macos-15 | 4-way matrix build validation (no signing) |
| `codeql.yml` | PR + push + weekly | macos-15 | Swift security analysis via CodeQL |
| `release-testflight.yml` | manual dispatch | macos-15 | Archive, sign, upload to TestFlight |

---

## Key Decisions

### Xcode Version Pinning
Pin Xcode 16.4 via `maxim-lobanov/setup-xcode@v1`. Reason: macos-15 runners ship Xcode 16.4 with iOS 18.5 + watchOS 11.5 runtimes pre-installed. watchOS 11.0 simulator runtime is absent on the default image; `xcodebuild -downloadPlatform watchOS` exits 70 on CI (requires Apple ID auth). Pinning a version whose runtimes are pre-baked sidesteps the problem entirely.

### No-signing CI builds
All validation workflows build with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`. This means they never need a real signing certificate or provisioning profile — fast, cost-effective, and secure.

### Secrets for TestFlight
`release-testflight.yml` requires three repository secrets:
- `APPLE_TEAM_ID` — 10-char alphanumeric team identifier
- `APP_STORE_CONNECT_API_KEY` — base64-encoded .p8 key
- `APP_STORE_CONNECT_KEY_ID` + `APP_STORE_CONNECT_ISSUER_ID` — App Store Connect API credentials

---

## ⚠️ CRITICAL TRAP: Gitignored xcconfig + configFiles Reference

### What happens
If `project.yml` references a gitignored xcconfig via `configFiles`:

```yaml
configFiles:
  Debug: Config/Signing.xcconfig
  Release: Config/Signing.xcconfig
```

...and that file doesn't exist when `xcodegen generate` runs, xcodegen exits with code 1:

```
2 Spec validations errors:
  - Invalid config file "Config/Signing.xcconfig" for config "Release"
  - Invalid config file "Config/Signing.xcconfig" for config "Debug"
```

This takes down every workflow that calls `xcodegen generate` — including build validation and CodeQL — even though those workflows don't need signing at all.

### Why it's a trap
The release workflow (which sets `APPLE_TEAM_ID` and calls `bootstrap-signing.sh`) passes. The validation workflows don't call bootstrap, so they fail. The symptom is "all macOS builds fail, Linux passes" — which can look like a toolchain issue until you read the log carefully.

### The fix (Option A — always correct)

**Every workflow that calls `xcodegen generate` must first call `scripts/bootstrap-signing.sh` with no env.**

The bootstrap script is idempotent: called with no `APPLE_TEAM_ID`, it creates `Config/Signing.xcconfig` with `DEVELOPMENT_TEAM =` (empty). For no-signing CI builds, this is harmless — xcodegen resolves the reference, the empty team ID is overridden by `CODE_SIGN_IDENTITY=""`.

Add this step before `xcodegen generate` in every workflow:

```yaml
# project.yml references Config/Signing.xcconfig (gitignored). Running the
# bootstrap script with no env creates a placeholder xcconfig so xcodegen
# doesn't fail with "Invalid config file". This job builds with
# CODE_SIGNING_ALLOWED=NO so the empty DEVELOPMENT_TEAM is harmless.
- name: Bootstrap signing xcconfig
  run: ./scripts/bootstrap-signing.sh
```

### The rule (durable)
> **When introducing a gitignored xcconfig with a `configFiles` reference, EVERY workflow that runs `xcodegen generate` must bootstrap the xcconfig first — not just the release workflow.**

This applies even if the consuming workflow builds with `CODE_SIGNING_ALLOWED=NO`. xcodegen validates file existence at parse time, before any xcodebuild flags are considered.

---

## Checklist: Adding a New Workflow that Calls xcodegen

- [ ] Does `project.yml` have any `configFiles` references?
- [ ] Are any of those files gitignored?
- [ ] If yes → add `Bootstrap signing xcconfig` step before `xcodegen generate`
- [ ] Does the workflow need real signing? → set `APPLE_TEAM_ID` from secrets before bootstrap
- [ ] Is it a validation workflow? → build with `CODE_SIGNING_ALLOWED=NO`

---

## Incident Log

| Date | Issue | Root Cause | Fix |
|---|---|---|---|
| 2026-05-16 | PR #21: all 4 macOS builds + CodeQL red | `ci-build.yml` and `codeql.yml` missing bootstrap step | Added `Bootstrap signing xcconfig` step to both (commit d8339d0) |
