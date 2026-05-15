# Amber — History Archive

## Pre-2026-05-15 Learnings (Archived)

### 2026-05-14T16:28:08-04:00 — macOS scaffold validation, three concrete cracks caught

First Mac build of the v0.1 scaffold after Windows authoring. Toolchain: xcodegen 2.45.4, Apple Swift 6.3.2, Xcode 26.5 (17F42). 6 / 6 ARRunnerCore tests pass, all four xcodebuild targets succeed, Swift 6 strict concurrency is silent. Notes for future me and the team:

- **`application.watchapp2` is a trap on modern Xcode.** It's the legacy WatchKit-App-with-Extension product type from before watchOS 7. xcodegen will happily emit it because `project.yml` asked, but xcodebuild then double-produces the binary (`CopyAndPreserveArchs` collides with the WKApplication packaging step) and the build fails with `Multiple commands produce '...ARRunnerWatch.app/ARRunnerWatch'`. Modern single-target watchOS apps must use `type: application` + `platform: watchOS` + `WKApplication: true` in Info.plist.
- **Shared widget appex + multi-host = Apple parent-prefix wall.** A single `app-extension` target with `platform: auto` and `supportedDestinations: [iOS, watchOS]` can't satisfy Apple's "embedded binary bundle ID must be prefixed with parent app bundle ID" rule for *both* `com.arrunner.phone` and `com.arrunner.watch` parents. Fix is to split into per-platform targets that share a single source directory — preserves "one widget codebase" while giving each `.appex` the right prefix. Pattern captured as a skill (`.squad/skills/xcodegen-shared-widget-per-platform/`).
- **`WidgetFamily.systemSmall` is iOS-only.** When sharing widget sources between iOS and watchOS, the `supportedFamilies` list MUST be gated with `#if os(watchOS)`. Trivial but the kind of thing that bites once and you don't forget.
- **xcodegen regenerates `Config/`.** The Info.plist and entitlements files in `Config/` are derived from `project.yml` on every `xcodegen generate`. Gitignore them along with `*.xcodeproj/`. The dev-setup doc's reference to `AR-Runner.xcworkspace` was wrong — xcodegen only produces `AR-Runner.xcodeproj` for this project layout.

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

### 2026-05-15T12:51:36-04:00 — Integration mocks v0.1 (feat/integration-mocks)

Built the testing scaffolding for downstream wiring of glasses + HealthKit without real hardware. Three production seams added to `ARRunnerCore` (kept additive to avoid clashing with Weiss's `feat/ble-wrapper` and Laughlin's `feat/workout-controller`):
- `Protocols/GlassesConnection.swift` — `GlassesConnectionState` enum + `GlassesConnectionObserver` protocol (separate from existing `GlassesFrameTransport` so Weiss's richer protocol can subsume on merge without my PR fighting it).
- `Protocols/HealthKitSubstrate.swift` — minimal `HealthKitSubstrate` protocol Laughlin's controller can adopt; exposes stable `workoutID` (D9), lifecycle phases, async metric stream.
- `Workout/WorkoutController.swift` — actor orchestrator wiring substrate + transport + metadata store; D4 happy path lives here.

Mocks (test target):
- `MockGlassesFrame` — actor double with recorded writes/layouts, explicit `simulateDisconnect/simulateReconnect`, one-shot failure injection (`failNextConnect`/`failNextLayoutPush`/`failNextMetricUpdate`), multi-subscriber connection-state stream that replays current state on subscribe.
- `FakeHealthKitSubstrate` — actor with deterministic scenario replay (`steadyRun` / `intervals` / `explicit` / `ended`), stable workout UUID for D9 side-store tests, `isScenarioComplete` poll for tests that need to await replay.
- `InMemoryARMetadataStore` — drop-in `ARMetadataStore` for D9 assertions without filesystem.
