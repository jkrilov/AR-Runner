# Version-bump diagnosis (rc1, rc2 uploaded as 1.0/3 instead of 0.3.0/16,17)

**Author:** Laughlin
**Date:** 2026-05-18T15:29-04:00
**Status:** Root cause confirmed by reproduction.

## Symptom

- `project.yml` has `MARKETING_VERSION: 0.3.0`, `CURRENT_PROJECT_VERSION: 17`.
- Workflow `release-testflight.yml` passes both as build settings on the
  `xcodebuild ... archive` command line.
- Apple's "ready to test" emails and TestFlight UI continue to show
  **AR-Runner 1.0 (3)** — frozen since the very first successful upload many
  rcs ago. Newer uploads silently don't appear in TestFlight.

## Root cause (one line)

**The `Config/*-Info.plist` files contain literal `CFBundleShortVersionString
= "1.0"` and `CFBundleVersion = "1"`. Those literals are baked into the IPA;
the `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` xcodebuild build settings
are never substituted into the Info.plist because the plist values are not
`$(VAR)` references and `GENERATE_INFOPLIST_FILE` is OFF (we use external
Info.plists).**

## Evidence

1. Source (== xcodegen-emitted) Info.plists, post-`xcodegen generate`:

   ```text
   === Config/ARRunnerPhone-Info.plist ===
     "CFBundleShortVersionString" => "1.0"
     "CFBundleVersion" => "1"
   === Config/ARRunnerWatch-Info.plist === (same)
   === Config/ARRunnerWidgetsPhone-Info.plist === (same)
   === Config/ARRunnerWidgetsWatch-Info.plist === (same)
   ```

2. `project.yml` declares the versions correctly under `settings.base`
   (lines 16-17) and the CLI passes them again at archive time
   (release-testflight.yml lines 334-335, 349-350). Generated pbxproj
   contains `MARKETING_VERSION = 0.3.0` and `CURRENT_PROJECT_VERSION = 17`
   in the project-level Release config.

3. None of the four `info.properties` blocks in `project.yml` list
   `CFBundleShortVersionString` or `CFBundleVersion`. xcodegen therefore
   writes its built-in defaults (`1.0` and `1`) into the source plists.

4. Xcode's "Process Info.plist" build phase only substitutes
   `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` into the plist when
   either (a) `GENERATE_INFOPLIST_FILE = YES` (we explicitly set
   `INFOPLIST_FILE` per target, so this is NO), or (b) the plist value is
   a `$(VAR)` placeholder. Neither is true today, so the literals win.

## Secondary bug uncovered while fixing

`MARKETING_VERSION` is currently set from `${TAG#v}` in the workflow, so for
tag `v0.3.0-rc2` it becomes `0.3.0-rc2`. App Store Connect rejects
non-numeric `CFBundleShortVersionString` values (must be `N`, `N.N`, or
`N.N.N`). Once we wire variable substitution end-to-end, the `-rcN` suffix
would start reaching Apple and would be hard-rejected at altool upload.
Workflow must strip `-rcN` from the marketing version before passing it
through. (Build number stays `${GITHUB_RUN_NUMBER}` — that's already an
integer and is fine.)

## Why "1.0 (3)" specifically

Build 3 was the `github.run_number` at the time of the first
ITMS-accepted upload (an early v0.2.0 rc). Apple's TestFlight bound the
app record to "1.0" (the literal plist value) at that moment. Every
subsequent upload either:

- carried the same literal `1.0` / `1` and was rejected as a duplicate
  build, OR
- (less likely) was outright rejected for the non-numeric
  `MARKETING_VERSION` once that path ever flowed through.

Either way, TestFlight stayed pinned to the first record. The CI logs
say "Artifact ARRunnerPhone-0.3.0-rc2-17.ipa uploaded" — but that string
is the GitHub Actions artifact filename built from workflow variables,
NOT the version embedded in the binary's Info.plist.

## Fix

### Patch 1 — `project.yml` (Pattern A: variable substitution)

For each of the four targets, add to `info.properties`:

```yaml
CFBundleShortVersionString: $(MARKETING_VERSION)
CFBundleVersion: $(CURRENT_PROJECT_VERSION)
```

`settings.base.MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` remain as
local-build defaults; CI overrides them on the `xcodebuild` CLI for
release archives.

### Patch 2 — `.github/workflows/release-testflight.yml`

Strip `-rcN` (and any other prerelease suffix) from the marketing
version before passing to `xcodebuild`:

```bash
RAW_VERSION="${TAG#v}"               # 0.3.0-rc3
MARKETING="${RAW_VERSION%%-*}"        # 0.3.0
```

Use `MARKETING` for `MARKETING_VERSION=` on the xcodebuild CLI; keep the
full `RAW_VERSION` (or tag) for artifact names and logs.

## Verification

After both patches + `xcodegen generate`:

```text
=== ARRunnerPhone (regenerated) ===
  "CFBundleShortVersionString" => "$(MARKETING_VERSION)"
  "CFBundleVersion" => "$(CURRENT_PROJECT_VERSION)"
```

(All four targets.) Then on CI the xcodebuild build-settings dump must
show `MARKETING_VERSION = 0.3.0` (NOT `0.3.0-rc3`) and
`CURRENT_PROJECT_VERSION = 18` (run_number); the post-archive Info.plist
inside `build/ARRunnerPhone.xcarchive/Products/Applications/*.app/Info.plist`
must read the same values literally; altool's "Authenticating with the App
Store..." log must reference `AR-Runner 0.3.0 (18)`.
