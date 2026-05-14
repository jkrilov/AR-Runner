# macOS Build Validation — v0.1 Scaffold

**Date:** 2026-05-14T16:28:08-04:00
**Validator:** Amber (QA & Fitness Domain)
**Branch:** `chore/macos-build-validation`
**Verdict:** 🟢 Green — full scaffold builds clean on macOS after surgical fixes.

## Toolchain used

| Tool | Version | Path |
| --- | --- | --- |
| xcodegen | 2.45.4 | `/opt/homebrew/bin/xcodegen` |
| Swift | Apple Swift 6.3.2 (swiftlang-6.3.2.1.108) | `/usr/bin/swift` |
| Xcode | 26.5 (Build 17F42) | `/usr/bin/xcodebuild` |
| Host | macOS / arm64 |  |
| SDKs exercised | watchsimulator26.5, iphonesimulator26.5 |  |

## Outcomes

### ARRunnerCore (SPM) — `swift test`

🟢 **6 / 6 tests pass.** Build clean, zero Swift 6 strict-concurrency warnings.

| Test suite | Tests | Result |
| --- | --- | --- |
| `ARMetadataStoreTests` | 1 | ✅ pass |
| `HUDLayoutTests` | 1 | ✅ pass |
| `SportTypeTests` | 1 | ✅ pass |
| `WCMessageTests` | 1 | ✅ pass |
| `WorkoutMetricTests` | 1 | ✅ pass |
| `WorkoutSessionTests` | 1 | ✅ pass |

Each suite is currently a single `testCodableRoundTrip`. That's adequate for a v0.1 scaffold — once Laughlin and Weiss start landing real logic, suites will grow.

### App targets — `xcodebuild` (CODE_SIGNING_ALLOWED=NO)

| Scheme | Destination | Result |
| --- | --- | --- |
| `ARRunnerWatch` | `generic/platform=watchOS Simulator` | 🟢 BUILD SUCCEEDED |
| `ARRunnerPhone` | `generic/platform=iOS Simulator` | 🟢 BUILD SUCCEEDED |
| `ARRunnerWidgetsPhone` | `generic/platform=iOS Simulator` | 🟢 BUILD SUCCEEDED |
| `ARRunnerWidgetsWatch` | `generic/platform=watchOS Simulator` | 🟢 BUILD SUCCEEDED |

The only build-time noise is an informational message:
`appintentsmetadataprocessor: Metadata extraction skipped. No AppIntents.framework dependency found.`

This is expected — `StartWorkoutIntent` lives in the widget extension, and the parent apps don't directly link AppIntents.framework. Not a blocker. Will resolve naturally when Laughlin wires the foreground intent into a parent target or adds an explicit `import AppIntents` to the watch app.

### Swift 6 strict concurrency

🟢 **No concurrency warnings or errors anywhere in the scaffold.** Both `swift test` and `xcodebuild` runs are silent on `Sendable`, isolation, and data-race diagnostics. The scaffold was clearly authored with D8 in mind:

- `WorkoutController`, `WatchConnectivityService`, and `GlassesService` are all `actor`s.
- `GlassesFrameTransport` protocol is marked `Sendable`.
- `WCMessage`, `WorkoutSession`, etc. are value types.
- Watch & phone app entry types are `@MainActor`.

This was the highest-risk surface for the macOS port and it's clean. Weiss and Laughlin can build on this without retrofitting concurrency.

## Fixes applied (scaffold-level, surgical)

All in this PR:

### 1. ARRunnerWatch — replaced legacy `application.watchapp2` target type

**Symptom:** `error: Multiple commands produce '...ARRunnerWatch.app/ARRunnerWatch'` (the `CopyAndPreserveArchs` step collided with the WKApplication packaging step).

**Cause:** `application.watchapp2` is the legacy WatchKit-App + Extension product type (pre-watchOS 7). Modern single-target watchOS apps use plain `application` with `platform: watchOS`.

**Fix:** In `project.yml`, changed `type: application.watchapp2` → `type: application`, added `WKApplication: true` to the Info.plist (the modern single-target marker key), and set `TARGETED_DEVICE_FAMILY: '4'` (watchOS family).

### 2. ARRunnerWidgets — split shared appex into per-platform targets

**Symptom:** `error: Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier. Embedded: com.arrunner.widgets, Parent: com.arrunner.phone`.

**Cause:** Apple's bundle-identifier rule requires app-extension IDs to start with the host app's ID. A single shared widget extension can't satisfy both `com.arrunner.phone.*` and `com.arrunner.watch.*` parents at once.

**Fix:** Replaced the single `ARRunnerWidgets` target with two thin per-platform targets — `ARRunnerWidgetsPhone` (`com.arrunner.phone.widgets`, iOS) and `ARRunnerWidgetsWatch` (`com.arrunner.watch.widgets`, watchOS) — that **share the same `ARRunnerWidgets/` source directory**. This preserves Laughlin's intent of one source of truth for the widget + `StartWorkoutIntent` (documented in `decisions.md`, 2026-05-14T15:44:37-04:00) while satisfying Apple's parent-prefix validation.

### 3. StartWorkoutWidget.swift — gated `WidgetFamily.systemSmall` for watchOS

**Symptom:** `error: 'systemSmall' is unavailable in watchOS`.

**Cause:** `.systemSmall` is iOS-only; watchOS uses `.accessoryRectangular` and friends.

**Fix:** Extracted `supportedFamilies` to a static computed property with `#if os(watchOS)` gating. iOS keeps `[.systemSmall, .accessoryRectangular]`; watchOS gets `[.accessoryRectangular]`.

### 4. `.gitignore` — added xcodegen-derived artifacts

`*.xcodeproj/`, `*.xcworkspace/`, `Config/` (xcodegen regenerates plists + entitlements from `project.yml`), `.build/`, `DerivedData/`, `.swiftpm/`, `xcuserdata/`, `*.xcuserstate`.

### 5. `docs/dev/setup.md` — corrected workspace reference

The doc claimed `xcodegen generate` produces `AR-Runner.xcworkspace`. It actually produces `AR-Runner.xcodeproj` (no separate workspace file). Updated the instructions to match reality and noted that the `Config/` plists and entitlements are derived and gitignored.

## What did NOT need fixing

- All ARRunnerCore models (`WorkoutSession`, `HUDLayout`, `WorkoutMetric`, `SportType`, `ARMetadataStore`, `WCMessage`, `GlassesFrameTransport`).
- Watch and phone app shells (`@MainActor` + `actor` discipline holds).
- Test coverage scope (6 happy-path Codable round-trips — appropriate for scaffold depth).
- HealthKit / Bluetooth / app-group entitlements — the strings render correctly from `project.yml`.

## Blockers / follow-ups for Joe and the team

None at scaffold level. Items below are **future-work flags**, not gates on the next feature branches.

1. **Signing & capabilities verification (Joe):** All builds in this validation used `CODE_SIGNING_ALLOWED=NO`. Before on-device runs, Joe needs to wire the dev team to `DEVELOPMENT_TEAM` in `project.yml` (or via an `.xcconfig`) and confirm HealthKit, BLE, and App-Group entitlements provision correctly under his account. The capability *declarations* are correct; only signing is unverified.
2. **AppIntents metadata extraction (Laughlin):** Once `StartWorkoutIntent` is invoked from the parent app's launch flow, the parent target should `import AppIntents` (or otherwise pull the framework into its link graph) so SSU metadata extraction stops being skipped. Cosmetic for now.
3. **Watch widget surface (Laughlin):** The watch widget currently registers `.accessoryRectangular`. When the Smart-Stack launch surface is wired up (per D7), confirm the family list still matches what the Smart Stack picker expects in watchOS 11.
4. **BLE wrapper (Weiss):** No scaffold-level concerns surfaced for the upcoming `ActiveLookGlasses` actor. The `GlassesFrameTransport` protocol is `Sendable`, which is exactly what the spike memo asked for. Recommendation when integrating the iOS SDK: use `@preconcurrency import` at the boundary (per D8), drop concrete transport conformances in the watch app target, not in ARRunnerCore.

## Repro instructions (for the next person off Windows)

```bash
# from repo root
brew install xcodegen        # if not already installed
xcodegen generate            # produces AR-Runner.xcodeproj + Config/*.plist + Config/*.entitlements (all gitignored)

# unit tests
cd ARRunnerCore && swift test && cd ..

# app builds (no signing)
xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerPhone \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerWidgetsPhone \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerWidgetsWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expect: 6 / 6 tests pass, 4 / 4 builds succeed, zero Swift 6 concurrency warnings.
