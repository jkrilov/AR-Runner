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

## 2026-05-15 Learnings Archive

### Multi-Agent Parallel Merge (2026-05-15T14:01:55-04:00)

Both Weiss (#5 `feat/ble-wrapper`) and Laughlin (#7 `feat/workout-controller`) merged into `main` while Amber's integration-mocks PR was still open. Branch was CONFLICTING; stub protocols duplicated by canonical types. Learned three-way collision audit pattern:

- **grep-audit type names before rebasing:** `git fetch && git log origin/main` confirmed both PRs landed. `grep -lR <stub-type-name>` against merged tree showed redeclaration errors (`GlassesConnectionState` from #5, `WorkoutHealthSubstrate` from #7). Textual conflicts ≠ redeclaration errors; both surface only on compile.
- **`git checkout --ours` for wholesale file drops:** Amber's stub `WorkoutController.swift` vanished in favour of Laughlin's full impl; `git checkout --ours` (note: rebase swaps `ours`/`theirs` from intuition) on the conflicted file took main's verbatim.
- **Adapt mocks to canonical surfaces, never reverse:** `MockGlassesFrame` lost `pushLayout`/`updateMetric(_:value:)` and picked up `selectLayout(id:)` + `updateField(_:HUDFieldUpdate)` from `GlassesFrameTransport`. `FakeHealthKitSubstrate` switched from `start`/`metrics()`/`phases()` to Laughlin's full surface.
- **Richer mock vs simpler stub — both belong:** Weiss's `StubGlassesTransport` + Laughlin's `InMemoryWorkoutHealthSubstrate` (canonical "happy-path" doubles for previews + basic coverage) live in ARRunnerCore. Amber's mocks (richer scenario controls, explicit inject-failure, pre-canned replays) live in test target. Use canonical stubs for happy path; reach for richer mocks when exercising D4 corner cases.
- **Integration test must wire mocks through the canonical controller:** `GlassesFrameTransport` doesn't live on `WorkoutController`; glasses signals reach it via `reportGlassesSignal(_:)`. Bridge from `glasses.connectionStates()`, map through `GlassesConnectivitySignal.from(_:)`, forward to controller. That bridge is what makes D4 happy path exercisable end-to-end.
- **Swift 6 region-based isolation checker bug on `Self`-capture in cross-actor closures:** Metric-formatter as `Self.formatMetric(...)` inside `Task { for await metric in stream }` triggered `error: pattern that the region-based isolation checker does not understand...`. Workaround: hoist to file-private `formatMetricImpl` so closure no longer captures non-`Sendable` `XCTestCase` subclass. Worth knowing — same bug recurred with `[glasses]` capture lists and `async` helper signatures.
- **Preserved prior Scribe commit through rebase:** Branch already had a Scribe session-log commit on top. `git rebase main` replayed both in order. No interactive surgery needed once conflicts resolved.

47/47 swift tests pass post-rebase; 6 new integration tests.

### Anticipatory Contract Tests — D4 Pattern (2026-05-15T14:33:20-04:00)

Wrote `DisconnectResilienceTests.swift` BEFORE Weiss + Laughlin implement the auto-reconnect / haptic surface. Patterns:

- **`XCTSkipIf(true, "EXPECTED-FAILING-UNTIL: ...")` is the right idiom.** Keeps CI green, leaves body compiled + live (no bit-rot), makes "delete this line when impl lands" obvious. Better than commenting out, better than skipping suite.
- **Contract gaps belong in test docstring AND inbox entry.** Test tells reviewer "here's expected"; inbox tells implementing agent "here's menu of fixes." Both cross-link via test name.
- **Always `waitUntil` for bridge task before asserting controller state.** Bridge `Task { for await state in stream }` runs on own scheduler; test thread races it. Every cross-actor forwarding assertion goes inside `waitUntil { … }` polling consuming side's state, not producing side.
- **Test "exactly N" contract on both ends.** For multi-cycle disconnect/reconnect, assert N drops on transport's `statusEvents()` AND N count increments on `controller.recordedDisconnectCount()`. Mismatches surface the haptic-1:1 contract violations.
- **Don't nuke unstaged WIP from another agent's branch.** Weiss's v0.2 BLE work arrived with my working tree (was on `feat/v02-ble-activelook` HEAD). Stashed with label `weiss-wip-on-ble-activelook` instead of nuking; restore with `git stash apply` after switching back.
- **Resilience contract gaps identified:** auto-reconnect absent on `GlassesFrameTransport` (Weiss); no layout auto-re-apply post-reconnect (Weiss); `glassesDisconnectCount` global not session-scoped (Laughlin); no dedicated `controller.alerts` stream for haptic triggers (Laughlin); `reportGlassesSignal` mutates state even in `.ended` phase (Laughlin, low pri).

PR #8: 7 anchoring + 3 skip-marked tests. `swift test` → 57 pass / 3 skipped / 0 fail.

### Linux-Only Flake Debugging (2026-05-15T15:05:00-04:00)

`test_DisconnectMidWorkout_KeepsRecordingIntoSubstrate` passed all macOS cells but failed `swift test (ARRunnerCore, Linux)` with `XCTAssertTrue failed - Pre-disconnect HUD writes did not arrive`.

**Wrong hypothesis (didn't fix):** Assumed substrate replay (24 emits via Task) drained before glasses connected; on Linux the bridge got nothing. Reordered setup to connect-first, pushed, CI failed identically.

**Real root cause:** Single-consumer `AsyncStream`. `WorkoutController.start(...)` does `for await metric in substrate.metricEvents`, and the test bridge *also* did `for await`. Runtime picks one waiter. On macOS Darwin the bridge won often; on Linux swift-corelibs the controller drained all 24 first.

**Right fix:** Bridge from `controller.metrics` (controller's published outbound stream) instead of substrate raw. Production-correct too — HUD mirrors what controller publishes, not substrate raw-emits. Controller's forwardingTask republishes via `metricContinuation.yield(metric)`, so bridge sees every ingested metric.

**Generalisable rule:** Never let integration test *also* subscribe to the same upstream stream as the controller's own forwardingTask. Subscribe to controller's *outbound* stream. If controller doesn't expose one, that's a contract gap to flag.

**Diagnostic workflow:** `gh run view <id> --log-failed | grep -iE "(failed|XCTAssert|error:)"` extracts failing test + assertion from noisy CI tail. Don't stop at "plausible cause" — verify on the failing platform before pushing.

### Anticipatory Contract Tests — v0.2 #5 Variant (2026-05-15T16:49:00-04:00)

Wrote `Glasses/RunningHUDPresetTests.swift` (5 tests) BEFORE Weiss's `RunningHUDPreset` enum lands. Variant: type-doesn't-exist-yet vs method-missing-on-existing-type.

- **Solution:** Keep every body as `// CONTRACT-BODY:` commented-out sketch under `XCTSkipIf(true, ...)`. Compiles (no symbol refs), appears in report as skip (CI-visible pending work), leaves assertion structure for reviewer + implementing agent.
- **Domain-semantic assertions matter:** Four tests are technical-contract (existence, default, distinctness, shippability). Fifth is fitness-domain — `.minimal` has HR but not cadence, `.dataDense` has cadence, `.standard` is between. Without it, the presets reduce to rawValue strings; future refactor could collapse them into aliases. Every preset/profile/mode enum needs a test locking *meaning* of each variant, not just distinctness.
- **Resist over-specifying descriptor return type:** Weiss hasn't shipped `layoutDescriptor()` yet. Contract bodies use adapter (`metrics(of preset:) -> Set<MetricKind>`) that reviewer adapts to Weiss's shape. Locks *contract* (each preset has metrics; no preset empty; no two identical) without locking *shape* (HUDLayout vs raw bytes).
- **Negative-default assertions are higher-signal:** Assert `default != .minimal && default != .dataDense` instead of `default == .standard`. If Weiss renames `.standard` → `.balanced`, negative version still passes; positive would fail and trigger needless test edit.
- **`XCTSkipIf(true, ...)` survived second outing unchanged:** Same idiom, skip-count semantics, one-line removal workflow. Confidence bump medium → high in the SKILL is justified.

Full suite: 71 tests / 8 skipped (3 prior D4 + 5 new) / 0 fail.


