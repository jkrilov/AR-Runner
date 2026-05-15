# Amber — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** QA & Fitness Domain
- **Joined:** 2026-05-14T18:30:31.658Z

## Learnings

<!-- Append learnings below -->

### 2026-05-14T16:28:08-04:00 — macOS scaffold validation, three concrete cracks caught

First Mac build of the v0.1 scaffold after Windows authoring. Toolchain: xcodegen 2.45.4, Apple Swift 6.3.2, Xcode 26.5 (17F42). 6 / 6 ARRunnerCore tests pass, all four xcodebuild targets succeed, Swift 6 strict concurrency is silent. Notes for future me and the team:

- **`application.watchapp2` is a trap on modern Xcode.** It's the legacy WatchKit-App-with-Extension product type from before watchOS 7. xcodegen will happily emit it because `project.yml` asked, but xcodebuild then double-produces the binary (`CopyAndPreserveArchs` collides with the WKApplication packaging step) and the build fails with `Multiple commands produce '...ARRunnerWatch.app/ARRunnerWatch'`. Modern single-target watchOS apps must use `type: application` + `platform: watchOS` + `WKApplication: true` in Info.plist.
- **Shared widget appex + multi-host = Apple parent-prefix wall.** A single `app-extension` target with `platform: auto` and `supportedDestinations: [iOS, watchOS]` can't satisfy Apple's "embedded binary bundle ID must be prefixed with parent app bundle ID" rule for *both* `com.arrunner.phone` and `com.arrunner.watch` parents. Fix is to split into per-platform targets that share a single source directory — preserves "one widget codebase" while giving each `.appex` the right prefix. Pattern captured as a skill (`.squad/skills/xcodegen-shared-widget-per-platform/`).
- **`WidgetFamily.systemSmall` is iOS-only.** When sharing widget sources between iOS and watchOS, the `supportedFamilies` list MUST be gated with `#if os(watchOS)`. Trivial but the kind of thing that bites once and you don't forget.
- **xcodegen regenerates `Config/`.** The Info.plist and entitlements files in `Config/` are derived from `project.yml` on every `xcodegen generate`. Gitignore them along with `*.xcodeproj/`. The dev-setup doc's reference to `AR-Runner.xcworkspace` was wrong — xcodegen only produces `AR-Runner.xcodeproj` for this project layout.

## Archive — Earlier v0.1 Build & CI Validation Work (2026-05-14)

### Condensed Summary

Three separate validation sprints identified and fixed critical scaffold bugs:

1. **watchOS Product Type Trap:** `application.watchapp2` is legacy (pre-watchOS 7). Causes build collision on xcodebuild. Fixed with `type: application` + `platform: watchOS` + `WKApplication: true` in Info.plist.

2. **Shared Widget Bundle ID Prefix Rule:** Multi-host widget appex can't satisfy Apple's "embedded binary bundle ID must prefix parent" rule for both watch and phone. Fixed by splitting into per-platform targets that share source directory. Pattern captured in `.squad/skills/xcodegen-shared-widget-per-platform/`.

3. **WidgetFamily.systemSmall iOS-Only Gate:** Missing `#if os(watchOS)` for family list causes CI failure. Trivial gate; critical to remember.

4. **xcodegen Config/ Regeneration:** Info.plist and entitlements derived from `project.yml` on every generate; must gitignore alongside `.xcodeproj`. Dev-setup doc corrected (workspace reference was wrong; `.xcodeproj` is output).

5. **Swift 6 Strict Concurrency Validation:** Zero data-race warnings across scaffold. Actor discipline (WorkoutController, WatchConnectivityService, GlassesService as actors; GlassesFrameTransport as Sendable; app entries as @MainActor) is already paying dividends.

**Repro process:** Five-command validation script in `docs/dev/macos-build-validation.md`. Anyone else validating across macOS matches your results.

**For Weiss (ActiveLook SDK):** Use `@preconcurrency import` per D8; keep concrete implementations in watch app target, not ARRunnerCore.

**For Laughlin:** "No AppIntents.framework" warning is benign until foreground-launch wiring lands.

### CI Swift 6.0 Toolchain Gotcha

PR #3 caught hard error: `error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6`

- Root: Scaffold had redundant `.enableUpcomingFeature("StrictConcurrency")`
- Local Swift 6.3.2 tolerates; CI Swift 6.0 rejects
- Fix: Removed explicit flag; Swift 6 language mode is source of truth
- Lesson: Smoke-test against CI toolchain version, not just local

### CI Workflows: xcodebuild -downloadPlatform Failure Analysis

PR #3 revision after Richards's `-downloadPlatform watchOS` attempt failed three CI checks:

- **Problem:** `xcodebuild -downloadPlatform` exits 70 with auth failure on GitHub runners (requires Apple ID session)
- **Solution:** Pin Xcode 16.4 via `maxim-lobanov/setup-xcode@v1`; pre-installed runtimes cover D2 minimums (iOS 18 / watchOS 11)
- **Lesson:** Runner image manifest is source of truth for installed runtimes; both SDKs and simulators must be present
- **Asymmetry:** watchOS app-scheme strict, widget-extension lenient (same on iOS); one Xcode pin fixes both
- **Cost win:** Dropping `-downloadPlatform` saves 3–5 min per watchOS cell

### PR #4 Nit Follow-Up (Cross-Reviewer)

Addressed Killian's three 🟡 nits on `chore/public-repo-prep`:
1. README.md — hyperlinked first ActiveLook mention
2. CONTRIBUTING.md — added Releases-page pointer
3. CODE_OF_CONDUCT.md — minimal Contributor Covenant v2.1 reference


**Root cause:** Scaffold included redundant `.enableUpcomingFeature("StrictConcurrency")` in `ARRunnerCore/Package.swift`. Local Swift 6.3.2 silently tolerates it; CI Swift 6.0 treats as hard error. This is the classic toolchain-version gap — your smoke test couldn't catch this because you tested locally against 6.3.2.

**Fix applied (350eae0):** Removed the explicit flag. Swift 6 language mode (`swift-tools-version: 6.0` + `.swiftLanguageMode(.v6)`) is the single source of truth.

**Key lesson for future smoke tests:** When validating across platforms, verify against the CI toolchain version (6.0), not just local. Deprecated flags, newly-removed APIs, and other version-specific changes will silently pass local build but hard-fail CI. Treat CI as the authoritative compiler.

**Action:** Your local smoke-test process is still valuable — it caught the earlier three bugs. This one slipped through because the local toolchain was too permissive. Consider adding a "CI toolchain simulation" step for future validation sprints.
### 2026-05-14T17:33:30-04:00 — CI fix: Xcode pin replaces failing `-downloadPlatform watchOS`

PR #3 had three red checks after Richards's runtime-install attempt landed (`079cb73`). I owned the revision. Notes for next time:

- **`xcodebuild -downloadPlatform <platform>` does NOT work unattended on GitHub-hosted runners.** Exits 70 with `Finding content...Unable to connect to simulator.` That's Apple's "command requires an interactive Apple ID auth session or sudo" error. Anyone reaching for `-downloadPlatform` in CI hits this wall. Do not use it. Pin a Xcode that already bundles the runtime, or use `xcrun simctl runtime add` with a cached DMG, or `mxcl/xcodes-action@v1` if you want the auth-free download flow.
- **Pinning Xcode by symlink path (`/Applications/Xcode_16.app`) is brittle.** That path can shift across runner image revisions. Pin explicitly with `maxim-lobanov/setup-xcode@v1` + `xcode-version: '16.4'`. Same shape every run, regardless of which Xcode the image symlinks to.
- **Runner image manifest is the source of truth for "what simulator runtimes ship pre-installed."** Cross-check both `Installed SDKs` *and* `Installed Simulators` sections of `actions/runner-images/.../macos-15-Readme.md`. An SDK present without its matching simulator runtime is a destination-resolution trap. As of 2026-05, macos-15's default is Xcode 16.4 with iOS 18.5 + watchOS 11.5 simulators pre-baked — both ≥ our D2 minimums (iOS 18 / watchOS 11), so no download step is needed at all.
- **`Ineligible destinations:` in xcodebuild errors is an *enumeration*, not a destination-spec diagnosis.** The task brief told me `name:Any iOS Device` was a smoking gun that the destination string had been mangled to `generic/platform=iOS` (real device). It wasn't. Reading the full error block — including `error:iOS 18.0 is not installed. To use with Xcode, first download and install the platform` — is what surfaced the real cause. When the runtime is missing, the only candidate destination that survives enumeration is the real-device placeholder; that's what gets logged. Look at the `error:` field, not just the `name:` field.
- **Asymmetric resolver leniency between scheme types is real and bites both platforms.** Richards already documented the watchOS variant (app-scheme strict, widget-extension scheme lenient). Same shape on iOS: `ARRunnerPhone` passed under the missing iOS 18.0 runtime; `ARRunnerWidgetsPhone` did not. Same root cause; same fix; one knob (Xcode pin) covers both.
- **Local Mac toolchain (Xcode 26.5 / Swift 6.3.2) remains the source of truth for destination *strings*.** CI runner image manifest is the source of truth for *runtime availability*. Two different sources, two different questions. Don't conflate them.
- **Cost win as a side effect:** dropping the `-downloadPlatform` step saves ~3–5 min wall-clock per watchOS cell. macOS minutes are billed at 10x Linux on private repos.

- 2026-05-15 — Lesson: when introducing a new Apple-platform xcodebuild workflow, include the `maxim-lobanov/setup-xcode@v1` Xcode 16.4 pin from day one. The macos-15 runner's default `xcode-select` toolchain advertises watchOS 11.0 / iOS 18.0 runtimes that aren't actually installed, so any generic-simulator destination fails with `xcodebuild error 70`. Discovered first in `ci-build.yml`, repeated in `codeql.yml` (PR #3) — don't make me find this a third time.

## 2026-05-15 — PR #4 nit follow-up (cross-reviewer)
Addressed Killian's 3 🟡 nits on PR #4 (chore/public-repo-prep) as the fresh-eyes implementer per reviewer-separation spirit:
1. README.md — hyperlinked first ActiveLook mention to https://www.activelook.net.
2. CONTRIBUTING.md — added Releases-page pointer so outside readers know how to detect v0.1.
3. CODE_OF_CONDUCT.md — new minimal file pointing to Contributor Covenant v2.1.
Sanity-checked `swift build` in ARRunnerCore (clean). One commit; Joe to merge.

### 2026-05-15T12:51:36-04:00 — Integration mocks v0.1 (feat/integration-mocks)
Built the testing scaffolding for downstream wiring of glasses + HealthKit without real hardware. Three production seams added to `ARRunnerCore` (kept additive to avoid clashing with Weiss's `feat/ble-wrapper` and Laughlin's `feat/workout-controller`):
- `Protocols/GlassesConnection.swift` — `GlassesConnectionState` enum + `GlassesConnectionObserver` protocol (separate from existing `GlassesFrameTransport` so Weiss's richer protocol can subsume on merge without my PR fighting it).
- `Protocols/HealthKitSubstrate.swift` — minimal `HealthKitSubstrate` protocol Laughlin's controller can adopt; exposes stable `workoutID` (D9), lifecycle phases, async metric stream.
- `Workout/WorkoutController.swift` — actor orchestrator wiring substrate + transport + metadata store; D4 happy path lives here.

Mocks (test target):
- `MockGlassesFrame` — actor double with recorded writes/layouts, explicit `simulateDisconnect/simulateReconnect`, one-shot failure injection (`failNextConnect`/`failNextLayoutPush`/`failNextMetricUpdate`), multi-subscriber connection-state stream that replays current state on subscribe.
- `FakeHealthKitSubstrate` — actor with deterministic scenario replay (`steadyRun` / `intervals` / `explicit` / `ended`), stable workout UUID for D9 side-store tests, `isScenarioComplete` poll for tests that need to await replay.
- `InMemoryARMetadataStore` — drop-in `ARMetadataStore` for D9 assertions without filesystem.

