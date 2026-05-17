# Skill: iOS TestFlight CI via GitHub Actions

**Owner:** Richards
**Created:** 2026-05-15
**Last updated:** 2026-05-17T07:44:23-04:00

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
| 2026-05-17 | rc1 (run 25989849479): archive failed with "no devices" / "no profiles for com.arrunner.phone" | xcodegen-generated pbxproj inherits Xcode's project-template default `CODE_SIGN_IDENTITY = "Apple Development"`. With `CODE_SIGN_STYLE=Automatic` + `xcodebuild ... archive`, that default wins and `-allowProvisioningUpdates` tries to mint a *Development* profile, which needs registered devices (CI has none). | PR #23: attempted CLI pin `CODE_SIGN_IDENTITY="Apple Distribution"` + conditional. Wrong fix — see next row. |
| 2026-05-17 | rc2 (run 25990326363): archive failed with "conflicting provisioning settings ... code signing identity iphoneos*]=Apple Distribution has been manually specified" | Two compounding bugs: (a) xcodebuild's CLI setting parser does NOT support `SETTING[sdk=...]=value` conditional syntax — it mis-parses into a literal value of `iphoneos*]=Apple Distribution` that overwrites the bare key; (b) pinning bare `CODE_SIGN_IDENTITY=...` on the CLI is rejected by Xcode as "manually specified" when `CODE_SIGN_STYLE=Automatic`, even though it's the *correct* identity. | PR #24: removed both CLI args from `release-testflight.yml`; instead append `CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution` and `[sdk=watchos*]` to `Config/Signing.xcconfig` after `bootstrap-signing.sh` and before `xcodegen generate`. xcconfig accepts the conditional syntax; xcconfig values are project config, so Xcode doesn't flag them as "manually specified". |

---

## ⚠️ CRITICAL TRAP: xcodebuild CLI doesn't parse `SETTING[sdk=...]=value`

### What happens

You learn (rightly) that the project default `CODE_SIGN_IDENTITY = "Apple Development"` is wrong for an archive build and try to override it on the xcodebuild command line:

```bash
xcodebuild ... \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  "CODE_SIGN_IDENTITY[sdk=iphoneos*]=Apple Distribution" \
  archive
```

xcodebuild echoes back:

```
Build settings from command line:
    CODE_SIGN_IDENTITY = iphoneos*]=Apple Distribution
```

The conditional form **silently mis-parses and overwrites the bare value** with garbage. Then Xcode fails the archive with:

```
error: <target> has conflicting provisioning settings. <target> is automatically
signed, but code signing identity iphoneos*]=Apple Distribution has been
manually specified.
```

### Two separate things going wrong

1. **`SETTING[sdk=...]=value` is xcconfig-only syntax.** It works in `.xcconfig` files and in the Build Settings editor — never on the xcodebuild command line. There is no error or warning; xcodebuild treats `CODE_SIGN_IDENTITY[sdk` as the setting name and `iphoneos*]=Apple Distribution` as the value.
2. **`CODE_SIGN_IDENTITY` + `CODE_SIGN_STYLE=Automatic` on the CLI = "conflicting provisioning settings".** Xcode treats *any* CLI-set `CODE_SIGN_IDENTITY` as a manual override that conflicts with automatic signing, regardless of whether the value is correct. This applies to every signed target (app, watch app, widgets, watch widgets) — they all fail.

### The fix

Put the identity override in `Config/Signing.xcconfig` (or whatever xcconfig your `configFiles:` references). xcconfig values are treated as project config, so Xcode does NOT flag them as "manually specified". Use the conditional form to keep simulator builds unaffected:

```
CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution
CODE_SIGN_IDENTITY[sdk=watchos*] = Apple Distribution
```

In CI, append these lines after `bootstrap-signing.sh` and before `xcodegen generate`. Don't put them in the script itself — local dev with a Personal Team needs `Apple Development` for device debugging.

### Rule (durable)

> **Never set `CODE_SIGN_IDENTITY` on the xcodebuild command line** when `CODE_SIGN_STYLE=Automatic`. Put it in an xcconfig — that's the only place where the `[sdk=...]` conditional syntax is honored and where it doesn't trip the "manually specified" check.

---

## ⚠️ CRITICAL TRAP: Automatic Signing Picks Development Identity on CLI Archive

### Symptom
`xcodebuild ... archive` with `CODE_SIGN_STYLE=Automatic` + `-allowProvisioningUpdates` fails with:
```
error: Communication with Apple failed: Your team has no devices from which to generate a provisioning profile.
error: No profiles for 'com.example.app' were found: Xcode couldn't find any iOS App Development provisioning profiles matching 'com.example.app'.
```
…even though the keychain has a valid **Apple Distribution** cert and `-configuration Release` is set.

### Why it happens
From the CLI (unlike Xcode.app's Product → Archive), automatic signing honors the build setting `CODE_SIGN_IDENTITY` literally. xcodegen-generated projects don't set it, so it inherits Xcode's project template default: `"Apple Development"`. Once that's in effect, `-allowProvisioningUpdates` tries to provision a Development profile, which requires registered devices on the team — CI runners have none.

### The fix (durable) — REVISED after rc2
> **Put `CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution` (and `[sdk=watchos*]`) in an xcconfig, NOT on the xcodebuild command line.**

Earlier guidance suggested pinning these on the `xcodebuild` CLI. That breaks two ways (see the trap section above): (a) xcodebuild's CLI parser mis-parses the `[sdk=...]` conditional syntax, and (b) any CLI-set `CODE_SIGN_IDENTITY` is rejected as a "manually specified" conflict with `CODE_SIGN_STYLE=Automatic`. xcconfig is the only place where both problems go away.

### Why GUI archives "just work"
Xcode.app's archive action internally promotes the signing identity to Distribution based on the action type. The CLI does not.

---

## Open Question: Should PR CI probe-build Release?

`ci-build.yml` only builds Debug for the simulator. Release config differs in `-O` optimization level and sometimes in warnings-as-errors behavior — meaning a Release-only build error (or a Release-only signing misconfig like the rc1/rc2 traps) won't surface until the TestFlight workflow runs, by which point the version tag is already burned. **Two data points now** support adding a `xcodebuild build -configuration Release CODE_SIGNING_ALLOWED=NO` job (or even an `archive` without signing) to PR CI. Trade-off: ~3-4 extra minutes per PR vs. catching this class of bug at PR time. See `decisions/inbox/richards-first-tf-run-postmortem.md` (rc1) and `decisions/inbox/richards-rc2-postmortem.md` (rc2).


