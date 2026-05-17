# Skill: iOS TestFlight CI via GitHub Actions

**Owner:** Richards
**Created:** 2026-05-15
**Last updated:** 2026-05-17T17:44:28-04:00

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
| 2026-05-17 | rc2 (run 25990326363): archive failed with "conflicting provisioning settings ... code signing identity iphoneos*]=Apple Distribution has been manually specified" | Two compounding bugs: (a) xcodebuild's CLI setting parser does NOT support `SETTING[sdk=...]=value` conditional syntax — it mis-parses into a literal value of `iphoneos*]=Apple Distribution` that overwrites the bare key; (b) pinning bare `CODE_SIGN_IDENTITY=...` on the CLI is rejected by Xcode as "manually specified" when `CODE_SIGN_STYLE=Automatic`, even though it's the *correct* identity. | PR #24: removed both CLI args from `release-testflight.yml`; instead append `CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution` and `[sdk=watchos*]` to `Config/Signing.xcconfig` after `bootstrap-signing.sh` and before `xcodegen generate`. xcconfig accepts the conditional syntax; xcconfig values are project config, so Xcode doesn't flag them as "manually specified". Partial fix — still left `CODE_SIGN_STYLE=Automatic` on CLI, causing rc3. |
| 2026-05-17 | rc3 (run 25991312727): TWO errors — (1) ARRunnerWidgetsPhone "conflicting provisioning settings … automatically signed for development, but a conflicting code signing identity Apple Distribution has been manually specified"; (2) ARRunnerPhone "Your team has no devices" + "No iOS App Development provisioning profiles" | `CODE_SIGN_STYLE=Automatic` still on the `xcodebuild` CLI (highest precedence) while `CODE_SIGN_IDENTITY=Apple Distribution` was correctly placed in xcconfig (project-config level). The CLI override elevated signing style above the xcconfig identity, making Xcode treat the identity as a conflicting manual override on extension targets (widget) and falling back to Development-profile resolution on the main target (no devices). | PR #25: removed `CODE_SIGN_STYLE=Automatic` from the `xcodebuild archive` CLI entirely. Both `CODE_SIGN_STYLE` and `CODE_SIGN_IDENTITY` now live exclusively in the xcconfig at the same precedence level — Xcode treats them as consistent project configuration. **Insufficient — see rc4 row below.** |
| 2026-05-17 | rc4 (run 26003539754): TWO errors — both ARRunnerPhone and ARRunnerWidgetsPhone fail with "automatically signed for development, but a conflicting code signing identity Apple Distribution has been manually specified" | Two compounding bugs surfaced after rc3 cleared the CLI: (1) `xcodebuild archive` from the CLI with `CODE_SIGN_STYLE=Automatic` **always** resolves to `Apple Development` identity by default — the GUI archive action auto-promotes to Distribution, the CLI does not. The xcconfig's `Apple Distribution` pin is then treated as a conflicting "manually specified" override. (2) `project.yml settings.base.CODE_SIGN_STYLE: Automatic` causes xcodegen to bake `CODE_SIGN_STYLE = Automatic` into the project-level `pbxproj`, which has **higher precedence than xcconfig** — so simply appending `CODE_SIGN_STYLE = Manual` to xcconfig has no effect until the project-base pin is removed. The widget extension is hit by the same conflict because xcconfig identity applies project-wide. | PR #26: (a) replaced `CODE_SIGN_STYLE: Automatic` with `CODE_SIGN_STYLE: $(inherited)` in `project.yml settings.base` so xcconfig drives style; (b) changed `release-testflight.yml` xcconfig append from "identity-only" to `CODE_SIGN_STYLE = Manual` + `CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution` + `[sdk=watchos*]`. Manual makes the archive intent explicit; `-allowProvisioningUpdates` + ASC API key fetches/creates the App Store distribution profile for each bundle ID on demand. |

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

> **Never set `CODE_SIGN_IDENTITY` OR `CODE_SIGN_STYLE` on the xcodebuild command line** for archive builds with automatic signing. Both must live in the xcconfig — that's the only place where: (a) the `[sdk=...]` conditional syntax is honored, (b) `CODE_SIGN_IDENTITY` doesn't trip the "manually specified" check, and (c) `CODE_SIGN_STYLE` doesn't elevate to override precedence causing the identity in xcconfig to appear as a conflicting manual override. **Three rc failures (rc1, rc2, rc3) confirm this independently.**

---

## ⚠️ CRITICAL TRAP: CLI `CODE_SIGN_STYLE=Automatic` Shadows xcconfig Identity

### Symptom (rc3 pattern — two errors at once)

1. Extension targets: `"<target> has conflicting provisioning settings. <target> is automatically signed for development, but a conflicting code signing identity Apple Distribution has been manually specified."`
2. Main app target: `"Your team has no devices…"` + `"No profiles for '...' were found: Xcode couldn't find any iOS App Development provisioning profiles"`

### Why it happens

`CODE_SIGN_STYLE=Automatic` on the `xcodebuild` command line has **highest precedence** — it overrides xcconfig, project settings, and target settings. When Xcode sees `CODE_SIGN_STYLE` at CLI level but `CODE_SIGN_IDENTITY` at a lower xcconfig level, the settings are at mismatched precedence tiers:

- **Widget/extension targets**: Xcode enters automatic-signing mode (from CLI) and considers the xcconfig identity a "manually specified" conflict → ERROR.
- **Main app target**: The automatic-signing mode at CLI level ignores or deprioritizes the xcconfig identity, falls back to Development identity → tries to mint a Development profile → fails because CI has no registered devices → ERROR.

The xcconfig alone would work perfectly (PR #24's theory was correct), but the CLI override destroys the precedence alignment that makes it work.

### The fix

**Remove all signing-related build settings from the xcodebuild command line.** Let them live in the xcconfig exclusively:

```
# In Config/Signing.xcconfig (written by CI before xcodegen generate):
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution
CODE_SIGN_IDENTITY[sdk=watchos*] = Apple Distribution
```

The only signing-related setting that can safely remain on the CLI is `DEVELOPMENT_TEAM` (a secret injected at runtime, treated as a simple value, not a mode selector).

### Confidence

**High** — three independent failure modes (rc1, rc2, rc3) all trace to the same root: putting signing configuration on the xcodebuild CLI instead of in the xcconfig. Each attempt to "fix it on the CLI" created a new failure mode; the xcconfig-only approach eliminates the entire class.

---

## ⚠️ TRAP: xcodegen Injects Target-Level `CODE_SIGN_IDENTITY` for iOS App Targets

### What happens

xcodegen auto-generates `CODE_SIGN_IDENTITY = "iPhone Developer"` in the target-level build settings for `type: application` + `platform: iOS` targets. This has **higher precedence** than the project-level xcconfig (`Config/Signing.xcconfig`), silently overriding `CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution`.

Widget extension targets (`type: app-extension`) are NOT affected — xcodegen doesn't inject the identity for them.

### The fix

In `project.yml`, set `CODE_SIGN_IDENTITY: $(inherited)` in the iOS application target's settings:

```yaml
ARRunnerPhone:
  type: application
  platform: iOS
  settings:
    base:
      CODE_SIGN_IDENTITY: $(inherited)
```

This generates `CODE_SIGN_IDENTITY = "$(inherited)"` in the pbxproj, which defers to the project-level xcconfig. For CI, the xcconfig contains the Distribution pin; for local dev, it inherits Xcode's default (`Apple Development`).

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

## ⚠️ CRITICAL TRAP (rc4): CLI Archive + Automatic Style → Development Identity → xcconfig Distribution Pin Conflicts

### Symptom (rc4 — run 26003539754)

Every signed iOS target — main app AND widget extension AND any other extension — fails archive with:

```
error: <target> has conflicting provisioning settings. <target> is automatically
signed for development, but a conflicting code signing identity Apple
Distribution has been manually specified. Set the code signing identity value
to "Apple Development" in the build settings editor, or switch to manual
signing in the Signing & Capabilities editor.
```

…even when `CODE_SIGN_STYLE` is NOT on the xcodebuild CLI (rc3's fix), and even when `CODE_SIGN_IDENTITY = Apple Distribution` lives in xcconfig (the supposed-safe location).

### Why it happens — two compounding precedence bugs

1. **CLI `xcodebuild archive` + Automatic style always resolves to Apple Development identity.** The Xcode.app GUI archive action promotes automatic signing to Distribution because it knows "this is an archive intended for App Store / Ad Hoc". The CLI has no such promotion logic. With automatic style on the CLI, Xcode resolves identity = `Apple Development` and then sees the xcconfig's `Apple Distribution` pin as a conflicting manual override.

2. **xcodegen bakes `CODE_SIGN_STYLE = Automatic` into the project-level pbxproj when `project.yml settings.base.CODE_SIGN_STYLE: Automatic` is set.** Project-level pbxproj has **higher precedence than xcconfig** in Xcode's build settings hierarchy. So even if you append `CODE_SIGN_STYLE = Manual` to xcconfig, the project-level Automatic still wins. xcconfig changes are silently ignored.

The combination is invisible from xcconfig alone — `cat Config/Signing.xcconfig` shows the Manual line; `xcodebuild -showBuildSettings` shows `CODE_SIGN_STYLE = Automatic`. You have to grep the generated pbxproj or use `-showBuildSettings` to see the actual resolved value.

### The fix — both layers must change together

**Layer 1 — project.yml** (so xcconfig style is allowed to win):

```yaml
settings:
  base:
    # CODE_SIGN_STYLE intentionally NOT pinned. $(inherited) makes xcconfig
    # the source of truth; if you pin Automatic here, xcodegen bakes it into
    # the project-level pbxproj and shadows any xcconfig CODE_SIGN_STYLE.
    CODE_SIGN_STYLE: $(inherited)
```

**Layer 2 — CI's xcconfig append** (so the Release archive uses Manual):

```bash
cat >> Config/Signing.xcconfig <<'EOF'
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution
CODE_SIGN_IDENTITY[sdk=watchos*] = Apple Distribution
EOF
```

Manual signing + `-allowProvisioningUpdates` + ASC API key tells Xcode: "use exactly this identity, and fetch or create the matching App Store distribution profile from the developer portal on demand". No more Development-identity fallback, no more conflict.

### Why Manual is the right answer (not "try harder with Automatic")

Three rc failures in a row tried to make Automatic work for CLI archive. Each one revealed a new shadowing/precedence trap. The root cause is structural: **automatic signing's identity decision depends on the action's intent (build vs archive vs export), and the xcodebuild CLI can't communicate "this is for App Store distribution" to automatic-signing resolution.** The GUI does. The CLI doesn't. Manual signing sidesteps the inference entirely — you state the identity, Xcode honors it.

### Local dev unaffected

`bootstrap-signing.sh` writes only `CODE_SIGN_STYLE = Automatic` (Debug + local dev). The `Manual` + `Apple Distribution` lines are appended **only by `release-testflight.yml` at CI time**, on a fresh CI-owned xcconfig. Joe's local Personal Team + Apple Development device debugging keeps working — verified by `xcodebuild -showBuildSettings -configuration Debug -sdk iphoneos` resolving to `Apple Development` + `Automatic` after the project.yml change.

### Rule (durable, confidence: high)

> **For CLI `xcodebuild archive` to App Store: use Manual signing with Apple Distribution identity, both set in xcconfig. Do NOT pin `CODE_SIGN_STYLE: Automatic` at `project.yml settings.base` — leave it `$(inherited)` so xcconfig wins.** Automatic signing for CLI archive is a four-iteration trap; Manual is one line of xcconfig and works on the first run.

### Confidence

**High** — fourth iteration (rc1 → rc2 → rc3 → rc4) on the same problem, with three independent root causes (CLI parser, CLI precedence shadow, project-base precedence shadow + CLI archive identity default). The xcconfig-only-Manual approach eliminates the entire class.

---

## Open Question: Should PR CI probe-build Release?

`ci-build.yml` only builds Debug for the simulator. Release config differs in `-O` optimization level, signing config, and sometimes in warnings-as-errors behavior — meaning a Release-only build error (or a Release-only signing misconfig like the rc1/rc2/rc3/rc4 traps) won't surface until the TestFlight workflow runs, by which point the version tag is already burned. **Four data points now** (rc1 signing identity, rc2 CLI parsing, rc3 CLI-precedence shadow, rc4 project-base-precedence shadow + CLI archive identity default) support adding a `xcodebuild archive -configuration Release CODE_SIGNING_ALLOWED=NO` job to PR CI — or at minimum a `-showBuildSettings | grep CODE_SIGN` assertion that catches precedence regressions at PR time. Trade-off: ~3-4 extra minutes per PR vs. burning a version tag per signing iteration. See D-RICHARDS-TF-8 (proposed); re-amplified by D-RICHARDS-TF-10 (rc4).


