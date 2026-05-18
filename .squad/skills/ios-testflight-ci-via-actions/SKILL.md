# Skill: iOS TestFlight CI via GitHub Actions

**Owner:** Richards
**Created:** 2026-05-15
**Last updated:** 2026-05-17T23:16:00Z

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

## ⚠️ CRITICAL TRAP (rc5): Manual Signing Works, But Provisioning Profile Lacks Required Entitlements

### Symptom (rc5 — run 26004285341)

After fixing the rc4 manual-signing trap, archive now fails per-target with messages of the form:

```
error: "<TargetName>" requires a provisioning profile with the App Groups feature.
       Select a provisioning profile in the Signing & Capabilities editor.

error: "<TargetName>" requires a provisioning profile with the App Groups and
       HealthKit features. Select a provisioning profile in the Signing &
       Capabilities editor.
```

Crucially, NO "conflicting provisioning settings" / "automatically signed for development" wording — that family of error is gone. Manual signing is engaged correctly. This is a different layer: the **provisioning profile content** does not satisfy the **entitlements file**.

### Why it happens

`-allowProvisioningUpdates` + an App Store Connect API key lets `xcodebuild` mint an Apple Distribution provisioning profile on demand. But the minted profile only includes capabilities **enabled on the App ID itself in the Apple Developer portal**. If the target's `.entitlements` file declares (e.g.) `com.apple.developer.healthkit = true` but the App ID record on developer.apple.com does NOT have the HealthKit capability checked, the freshly-minted profile will lack the HealthKit entitlement, and the archive step rejects it with the message above.

The repo files (entitlements, Info.plist, project.yml) can be perfectly correct and this still fails. The truth lives in the portal, not the repo.

### The fix — portal action, not code change

For every iOS/watchOS App ID that the archive will sign, ensure the App ID declares **every capability** that appears in the corresponding `.entitlements` file:

1. <https://developer.apple.com/account/resources/identifiers/list>
2. Open each App ID.
3. Tick every capability the entitlements file uses (App Groups, HealthKit, Sign in with Apple, Push, etc.).
4. For App Groups, click "Edit" next to the capability and assign the specific group identifier(s) the entitlements file references. Register the group itself first under Identifiers → "App Groups" filter if it doesn't exist.
5. Save the App ID.

Then re-run the archive. Do **not** download or install profiles manually — `-allowProvisioningUpdates` will mint fresh profiles that now include the capabilities. Do **not** add `PROVISIONING_PROFILE_SPECIFIER` to the workflow; it couples the CI to manually-named profiles and is only worth doing if the team must operate without an Admin-scoped ASC API key.

### Pre-flight runbook addition

Before tagging an rc:

```bash
# Inventory entitlements declared in the repo.
for f in Config/*.entitlements; do
  echo "=== $f ==="
  /usr/libexec/PlistBuddy -c "Print" "$f" 2>/dev/null || cat "$f"
done
```

For each target's bundle ID, manually confirm the corresponding App ID in the portal has at least the union of these capabilities. (If we ever script this with the ASC API, log a follow-up.)

### Rule (durable, confidence: high)

> **Manual-signed CLI archive errors of the form `"<Target>" requires a provisioning profile with the <Capability> feature` mean the App ID in the developer portal does not have that capability enabled.** Fix in the portal; do not touch the workflow. `-allowProvisioningUpdates` only mints profiles for capabilities the App ID already declares.

### Confidence

**High** — fifth iteration on this signing-pathway chain (rc1 → rc5), each iteration revealing a distinct layer (CLI identity default → CLI parser → CLI precedence → project-base precedence + identity-default → portal-side capability registration). Five distinct root causes, five fixes, each terminal to its symptom class.

---

## ⚠️ RETRACTED (rc6 first-pass): "Cached stale Distribution profile" diagnosis was wrong

The original rc6 entry in this skill claimed `-allowProvisioningUpdates` was reusing stale Distribution profiles for the iOS bundle IDs, and offered an "asymmetric Watch-pass / iOS-fail" fingerprint as the smoking gun. **Both claims were disconfirmed.**

- The portal Profile list (correct team selected) is **empty** — there are no cached profiles to reuse, so the reuse-if-present mechanism cannot be what's biting us here.
- The "Watch targets succeeded" claim was an inferential error: `xcodebuild archive` aborts at the **first** failed target, so the absence of a Watch-target error in the rc6 log is equally consistent with "Watch was never reached." There was no positive evidence Watch succeeded.

**Durable reasoning lesson (cross-cutting, not just signing):** when a tool has *stop-at-first-error* semantics, "no error logged for X" is NOT evidence that "X succeeded." Demand positive evidence before claiming asymmetry. This applies to xcodebuild, swift build, ld, codesign, and any pipeline that bails on first failure.

The reuse-if-present semantic of `-allowProvisioningUpdates` is still real and may bite us in a *later* rc — keep this section for that day, but do not use the "asymmetric target" fingerprint, and only suspect the cache when the portal actually shows a Distribution profile for the failing bundle ID.

The corrected rc6 diagnosis is below.

---

## ⚠️ CRITICAL TRAP (rc6, corrected): App Store Connect API key role insufficient for Distribution profile minting

### Symptom (rc6 — run 26005442467)

After applying the rc5 fix (every App ID has the required capabilities — App Groups + HealthKit as appropriate), the archive fails with:

```
error: "ARRunnerPhone" requires a provisioning profile with the App Groups and HealthKit features.
error: "ARRunnerWidgetsPhone" requires a provisioning profile with the App Groups feature.
```

AND the developer portal Profile list is **empty** for all four bundle IDs — no Distribution profile has ever been minted, despite `-allowProvisioningUpdates` being passed on every prior rc.

### Why it happens

`xcodebuild -allowProvisioningUpdates` mints Distribution profiles by calling the App Store Connect REST API under the hood (the same endpoints `fastlane sigh` and `fastlane match` use). That `POST .../profiles` call is **role-gated**:

| Role on the API key | Can read profiles | Can **create** Distribution profile |
|---|---|---|
| Developer | ✅ | ❌ |
| App Manager | ✅ | ✅ |
| Admin | ✅ | ✅ |

A **Developer**-role key can read existing profiles but is denied on profile creation. `xcodebuild` does not surface the underlying 403 as a useful error — it just falls through to the generic "requires a provisioning profile with the <Capability> feature" message because, from its perspective, no profile satisfying the entitlements exists. Net effect: the build looks like it's failing on capabilities (rc5-style) when it's actually failing on key role.

### Diagnostic fingerprint (corrected)

The real fingerprint is **"empty portal Profile list + correct App ID capabilities + repeated rc5-style errors"** — meaning nothing has ever been minted for any bundle ID, not just some. Do NOT use the prior "asymmetric target failure" claim; see the retracted-section notice above.

### The fix — verify and (if needed) rotate the API key

1. Open <https://appstoreconnect.apple.com/access/integrations/api>.
2. Find the row matching the **Key ID** stored as `APP_STORE_CONNECT_API_KEY_ID`.
3. Read the **Access** column.
   - If **App Manager** or **Admin** → key is fine; the trap is elsewhere (see fallback below).
   - If **Developer** → root cause confirmed. Generate a new key with **App Manager** access, update the three repo secrets (`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`), revoke the old key.
4. Re-tag. `-allowProvisioningUpdates` will now successfully mint a Distribution profile per bundle ID on first archive.

### Fallback if the key role is already sufficient

Manually pre-create one App Store Distribution profile per bundle ID in the portal (Certificates, IDs & Profiles → Profiles → +). `-allowProvisioningUpdates` will then read the existing profile rather than having to create one. This bypasses any first-time-mint edge case Apple may have for fresh App IDs. Trade-off: profiles become a manual artifact you must revoke + re-create whenever entitlements change.

### Rule (durable, replaces the prior rc6 rule)

> **`-allowProvisioningUpdates` can only mint Distribution profiles when the API key role is App Manager or Admin. A Developer-role key surfaces this as the generic "requires a profile with <Capability>" error — indistinguishable from the rc5 App-ID-capability bug at the xcodebuild layer.** Always confirm the API key's role in App Store Connect before chasing capability or profile-cache hypotheses. The disambiguating signal is the **portal Profile list itself**: empty list = nothing was ever minted = suspect key role; populated list with stale entitlements = suspect reuse-if-present.

### Pre-flight runbook addition (extends rc5 entry)

Before any rc that depends on a freshly-minted Distribution profile:
1. Confirm App ID capabilities match entitlements (rc5 rule, still in force).
2. Confirm the API key in use has **App Manager** or **Admin** access (this rule).
3. If you've changed entitlements on a bundle ID that already has a Distribution profile in the portal, plan to revoke that profile (the retracted rc6 entry's reuse-if-present concern remains valid — just not what was biting us *this* time).

### Cross-references (corroborating)

- Apple — [App Store Connect API roles reference](https://developer.apple.com/documentation/appstoreconnectapi/roles): defines which roles can perform `POST /profiles`.
- fastlane — [App Store Connect API permissions](https://docs.fastlane.tools/app-store-connect-api/#permissions): "the API Key should have at least the App Manager role" for profile/cert creation flows.

### Confidence

**High** for the diagnosis matching the evidence (empty portal + capabilities-correct + rc5-style error is exactly the failure mode a Developer-role key produces). The diagnosis is also falsifiable: if the key turns out to already be App Manager, this rule is wrong and we move to the manual-pre-create fallback. That's a feature, not a weakness — the previous rc6 diagnosis was unfalsifiable in practice and turned out to be wrong.

---

## Open Question: Should PR CI probe-build Release?

`ci-build.yml` only builds Debug for the simulator. Release config differs in `-O` optimization level, signing config, and sometimes in warnings-as-errors behavior — meaning a Release-only build error (or a Release-only signing misconfig like the rc1/rc2/rc3/rc4 traps) won't surface until the TestFlight workflow runs, by which point the version tag is already burned. **Four data points now** (rc1 signing identity, rc2 CLI parsing, rc3 CLI-precedence shadow, rc4 project-base-precedence shadow + CLI archive identity default) support adding a `xcodebuild archive -configuration Release CODE_SIGNING_ALLOWED=NO` job to PR CI — or at minimum a `-showBuildSettings | grep CODE_SIGN` assertion that catches precedence regressions at PR time. Trade-off: ~3-4 extra minutes per PR vs. burning a version tag per signing iteration. See D-RICHARDS-TF-8 (proposed); re-amplified by D-RICHARDS-TF-10 (rc4).



---

## ⚠️ TRAP: "requires a provisioning profile with the <X> feature" is a 3-way error

### Symptom

```
"<Target>" requires a provisioning profile with the <Capability> feature.
Select a provisioning profile in the Signing & Capabilities editor.
```

### Why it is ambiguous

xcodebuild emits this **identical string** for at least three distinct underlying causes:

1. **App ID lacks the capability** — any profile minted for that bundle ID is born without the entitlement, so no candidate profile satisfies the requirement. (rc5/TF-11 class.)
2. **Profile exists with capability, but cert mismatch** — profile's `DeveloperCertificates[]` does not contain the cert whose private key is in the signing keychain. Xcode silently rejects the profile and reports "none usable."
3. **Profile not present at all and minting failed** — earlier API failure, role insufficiency, or `-allowProvisioningUpdates` was omitted. Xcode falls through to the same string.

The error wording does NOT distinguish "no profile found" from "profile found but unusable." Do not assume.

### Rule

When this error appears, the build log alone is **not sufficient** to localize the root cause. Always run a 2-axis probe:

- **Axis 1 (App ID truth):** open the App ID in <https://developer.apple.com/account/resources/identifiers/list>; verify the Capabilities checkboxes AND that any configurable capability (App Groups, iCloud, Associated Domains) has its sub-configuration committed (e.g. App Groups must have the actual group ID *selected*, not merely defined in the master list).
- **Axis 2 (Profile ground truth):** download the `.mobileprovision` and run `security cms -D -i <file> | plutil -p -` to read both `Entitlements` (proves Axis 1 was saved) and `DeveloperCertificates[]` (lets you compare SHA1 against the `.p12` you imported in CI: `openssl pkcs12 -in dist.p12 -nokeys -passin pass:... | openssl x509 -noout -fingerprint -sha1`).

If Axis 2 entitlements are present AND its cert SHA1 matches the keychain cert SHA1, the profile is unambiguously usable; any remaining failure is a workflow bug (missing `PROVISIONING_PROFILE_SPECIFIER`, wrong keychain search list, etc.), not a portal/cert issue.

### Recall bias warning (rc7 lesson)

When the user has *just* finished a manual portal configuration session, "I clicked the box" feels like ground truth but isn't — Apple's portal silently no-ops on Save in some flows (modal dismissed without confirm, capability edit not committed before navigating away). Always trust the downloaded `.mobileprovision` over UI recall.

### Cross-reference

- D-RICHARDS-TF-11 (App ID capabilities — root of cause #1)
- D-RICHARDS-TF-12 — RETRACTED (cached-profile-reuse hypothesis disconfirmed by empty portal Profile list)
- D-RICHARDS-TF-13 — RETRACTED (API key role hypothesis disconfirmed; Joe's key is App Manager)
- D-RICHARDS-TF-14 (rc7 — this trap; 1-click portal probe with contingent profile-bytes probe)

---

## ⚠️ TRAP: `-allowProvisioningUpdates` does NOT install manual profiles

### Symptom

You have manually created App Store distribution profiles in the portal (correct bundle IDs, correct entitlements, `IsXcodeManaged: false`). The CI workflow imports the `.p12`, installs the App Store Connect API key, and runs:

```
xcodebuild ... archive -allowProvisioningUpdates \
  -authenticationKeyID ... -authenticationKeyIssuerID ... -authenticationKeyPath ...
```

Archive fails with the now-familiar:

```
"<Target>" requires a provisioning profile with the <Capability> feature.
```

…on every signed target. The error is identical to cases where the App ID lacks the capability or where the cert doesn't match — *but in this case the profile is provably correct*.

### Why it happens

`-allowProvisioningUpdates` is documented as "allow xcodebuild to communicate with Apple to **update** signing assets." In practice it **only auto-mints/updates Xcode-managed profiles** (`IsXcodeManaged: true`). It does NOT scan the App Store Connect account for matching manual profiles and download them to the runner's `~/Library/MobileDevice/Provisioning Profiles/`.

Manual profiles must be physically present in `~/Library/MobileDevice/Provisioning Profiles/` for xcodebuild to consider them. A fresh GitHub Actions macOS runner has an empty profiles directory.

So the candidate-profile set is empty → cause #3 of the 3-way error fires.

### Confirmation (rc7 forensics)

Joe ran:

```bash
security cms -D -i ~/Downloads/AR_Runner.mobileprovision
```

Profile contained:
- `application-identifier = GB66R9JAYL.com.arrunner.phone` ✅
- `com.apple.developer.healthkit = true` ✅
- `com.apple.security.application-groups = [group.com.arrunner.shared]` ✅
- `IsXcodeManaged = false`
- `DeveloperCertificates[0]` SHA1 == the single Distribution cert SHA1 in the keychain `.p12` ✅

All four profiles (phone, widgets, watch, watch widgets) verified the same way. Axis 1 and Axis 2 of the 3-way-error probe both returned clean → cause #3 (no profile on disk).

### Fix

Install profiles onto the runner **before** `xcodebuild archive`, OR use `PROVISIONING_PROFILE_SPECIFIER` per target and let xcodebuild fetch by name. Three viable strategies:

**Option A (tried rc8, FAILED — see next trap):** Download all team profiles via App Store Connect API and let the tool install them into `~/Library/MobileDevice/Provisioning Profiles/`. Implemented as a `fastlane sigh download_all` step using the existing ASC API key (assembled into a JSON file with `jq`). One step, handles all four targets uniformly, including the embedded Watch app. **Looked clean in rc8 — was vacuous.** See the "sigh download_all silent-zero" trap below.

**Option B (chosen, rc9):** Set `PROVISIONING_PROFILE_SPECIFIER` per target (in `project.yml` `configs.Release`, NOT base — leaving Debug unset preserves local Automatic-signing dev). With manual signing + `-allowProvisioningUpdates` + a valid App Manager ASC API key, xcodebuild fetches the named profile directly from App Store Connect at archive time. No local install step, no fastlane dependency, no platform-filter trap. Trade-off: profile names are hardcoded in `project.yml`; if the names change in App Store Connect, the build breaks until `project.yml` is updated.

**Option C (not used):** Apple-Actions/download-provisioning-profiles GitHub action. Equivalent to Option A in effect; same class of filter risk.

### Rule (durable)

> **If `IsXcodeManaged` is `false` on your provisioning profiles, `-allowProvisioningUpdates` alone is insufficient.** Either install the profiles into `~/Library/MobileDevice/Provisioning Profiles/` (and verify the install with a non-zero file count!) OR pin `PROVISIONING_PROFILE_SPECIFIER` per target so xcodebuild fetches by name. Option B (specifier) removes the local-install moving part entirely and is the chosen path in this repo.

### Cross-reference

- D-RICHARDS-TF-16 (rc9 — pivot to specifier; this is the live approach)
- D-RICHARDS-TF-15 (rc8 — sigh install attempt; superseded)
- D-RICHARDS-TF-14 (rc7 — 3-way-error probe; this trap is cause #3 confirmed)

---

## Trap: `fastlane sigh download_all` exits 0 with zero profiles installed

**Symptom:** rc9 forensics. The `Download & install provisioning profiles` step in rc8/rc9 ran `fastlane sigh download_all --api_key_path … --team_id … --platform ios` and exited code 0. The "step succeeded" badge was green. The following `ls -la ~/Library/MobileDevice/Provisioning Profiles/` line showed:

```
total 0
drwxr-xr-x  2 runner  staff  64 May 18 00:28 .
```

Zero profiles installed. The next step (`xcodebuild archive`) failed with the byte-identical "requires a provisioning profile with the <X> feature" error that rc5/rc6/rc7 had hit.

**Cause (most likely, not exhaustively re-probed because we pivoted):** sigh's `--platform ios` filter is exact-match against the profile's primary platform. Profiles minted in the modern App Store Connect portal for an iOS-family App ID can carry a `Platform` array of `[iOS, xrOS, visionOS]` (Apple's portal lumps the visionOS/xrOS sibling platforms in by default). sigh 2.233.0's filter matched no profile under `[iOS, xrOS, visionOS]` against `--platform ios` and quietly downloaded nothing.

Secondary candidate causes (not falsified before pivot): sigh's `api_key_path` JSON format edge cases, sigh-side scope quirks around `download_all` for App Store profiles without `--app-identifier`. We did not bother disambiguating because Option B (specifier) removed the dependency.

**Rule (durable):** When a download/fetch step claims success, **assert on the artifact, not the exit code**. Specifically, a `find … | wc -l` or `ls … | wc -l` with an explicit `[[ "$count" -gt 0 ]] || exit 1` check turns vacuous success into loud failure. Apply this to every "fetch N things from an API" step in CI, not just sigh — the silent-zero pattern is endemic to filter-aware downloaders.

**Meta-rule (extends "Am I treating silence as success?" from TF-12):** *"Am I treating a clean exit as a non-vacuous outcome?"* — Exit codes describe the tool's internal happy path. They do NOT describe whether the tool produced the artifact the next step needs. Wire artifact-count assertions into every download/install step.

### Cross-reference

- D-RICHARDS-TF-16 (rc9 — names this trap; pivot to specifier removes the dependency)
- D-RICHARDS-TF-15 (rc8 — original sigh install attempt that hit this trap)
