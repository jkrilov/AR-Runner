# Watch / Swift / HealthKit Audit — 2026-05-16

**Auditor:** Laughlin (watchOS Dev) · **Model:** claude-opus-4.7-1m
**Scope:** ARRunnerWatch, ARRunnerPhone, ARRunnerWidgets, watchOS-touching parts of ARRunnerCore. Excludes ActiveLook/BLE (Weiss) and CI/dependency currency (Richards).
**Mode:** Read-only.

## Summary

The codebase is in good shape against the 2026 bar. Swift 6 strict concurrency is honoured throughout: zero `try!`, zero force-unwraps in non-test code, no `ObservableObject`/`@StateObject`/`NavigationView` legacy, `@Observable` macro used correctly on both view-models, `NavigationStack` everywhere, `WorkoutController` is a real `actor` with `nonisolated let` stream properties (matches our `swift6-actor-asyncstream-protocol` skill).

Two real bugs and three architectural debt items deserve attention:

1. **HealthKit energy samples are mis-classified as `.duration`** in `HealthKitWorkoutSubstrate.metric(for:)` — live HK kcal never reaches the view-model or controller aggregator. (See **HealthKit Usage §1**.)
2. **`StartWorkoutIntent.perform()` is a no-op TODO** — the widget Start button doesn't actually launch into the run flow. (See **watchOS-Specific §3**.)
3. Substrate switch uses optional-pattern matching on `HKQuantityType.quantityType(forIdentifier:)` (an `Optional` returning lookup) inside a `switch type` over a non-optional — works today but silently skips if Apple ever returns nil. (See **HealthKit Usage §2**.)

The remaining items are modernization (Duration-based sleep, `AppIntentTimelineProvider`, bounded async streams) and one HK UX gap (denied-auth has no surfaced CTA).

## Swift 6 Concurrency

**Solid.**

- `WorkoutController` is `actor`, no `@unchecked Sendable`, `nonisolated let states/metrics` is correct for stream exposure (`ARRunnerCore/Sources/ARRunnerCore/Workout/WorkoutController.swift:21,55,59`).
- `WorkoutViewModel` is `@MainActor @Observable`, all stream consumers use `Task { [weak self] in }` with self-capture only inside the closure body (`ARRunnerWatch/Workout/WorkoutViewModel.swift:24-26, 233-244, 318-328`). Clean.
- `WorkoutMirrorViewModel` mirrors the same pattern (`ARRunnerPhone/Views/WorkoutMirrorViewModel.swift:15-17, 43-54`). Clean.
- `@unchecked Sendable` is used in 3 places, all justified:
  - `HealthKitWorkoutSubstrate` (`ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift:21`) — NSObject + `OSAllocatedUnfairLock` around mutable state; HK delegate callbacks come on arbitrary queues. ✓
  - `WatchConnectivityService` (watch, `ARRunnerWatch/Sync/WatchConnectivityService.swift:19`) — WCSession delegate, immutable state after init. ✓
  - `WatchConnectivityService` (phone, `ARRunnerPhone/Sync/WatchConnectivityService.swift:21`) — same shape. ✓
- One `nonisolated` usage outside Core (`ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift:80`) — Weiss's surface, out of scope.

**Minor:** `WorkoutController.metrics` is `AsyncStream(bufferingPolicy: .unbounded)` (`WorkoutController.swift:80-82`). If a downstream consumer (e.g. `WorkoutViewModel.metricTask`) stalls, the controller's buffer grows for the entire workout. Effort S, impact low — switch to `.bufferingNewest(64)` for live-only data.

## SwiftUI Modernization (2026)

**No legacy patterns.**

- `@Observable` on both view-models, `@State` (not `@StateObject`) on the SwiftUI side (`WorkoutView.swift:9-13`, `WorkoutMirrorView.swift:13-17`).
- `NavigationStack` in both apps (`ARRunnerWatchApp.swift:14`, `RootView.swift:10,17,27`).
- `containerBackground(.fill.tertiary, for: .widget)` is current widget API (`StartWorkoutWidget.swift:44`).
- `Image(systemName:).foregroundStyle(.red)` everywhere — `.foregroundStyle` not `.foregroundColor`. ✓
- `.confirmationDialog` finish menu uses the modern `titleVisibility:`/role-based button API (`WorkoutView.swift:28-38`).

**Watch out:** `WorkoutView`'s `@State private var viewModel = WorkoutViewModel(substrateFactory: { HealthKitWorkoutSubstrate() }, …)` (`WorkoutView.swift:9-13`) means the `#Preview` (`:160-164`) constructs a real `HealthKitWorkoutSubstrate` — fine today (no HK calls happen until `start()`), but a future eager init in the substrate would crash previews. Consider an `init(viewModel:)` overload for previews. Effort S, impact low.

## HealthKit Usage

### 1. Active energy mapped to wrong `WorkoutMetric.kind` — BUG (real)

`HealthKitWorkoutSubstrate.metric(for:)` (`ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift:271-272`):

```swift
case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
    return WorkoutMetric(kind: .duration, value: …, unit: "kcal", …)
```

Energy is yielded as `.duration`. Consequences:

- `WorkoutController.ingest(metric:)` (`WorkoutController.swift:223-234`) routes `.duration` to `break` → `lastEnergyKilocalories` is never populated → `makeSummary` relies entirely on `result.totalActiveEnergyKilocalories` from the final `HKWorkout`. Works today because `HKWorkout.totalEnergyBurned` is usually populated on `finishWorkout()`, but the live aggregate is dead code.
- `WorkoutViewModel.apply(metric:)` (`WorkoutViewModel.swift:348-358`) `default: break`s → live HK kcal is never displayed; the UI's "flame" metric is only fed by the local `EnergyAccumulator` (heart-rate estimate, decision #4). On users with no `bodyProfile`, kcal stays `nil` for the entire run even if HK is publishing it.

**Fix:** Add `case energy` (or `.activeEnergy`) to `WorkoutMetric.MetricKind` in Core, route it through the substrate, controller, and view-model. Effort S, impact medium.

### 2. Optional pattern match in `metric(for:)` switch — latent

`switch type { case HKQuantityType.quantityType(forIdentifier: .heartRate): … }` (`HealthKitWorkoutSubstrate.swift:264-272`) pattern-matches a non-optional `HKQuantityType` against an `HKQuantityType?` literal. Today all five identifiers resolve, but if Apple ever deprecates one the lookup returns `nil`, the `case` silently never matches, and the metric is dropped without warning. Switch on `type.identifier` (a `String`) and compare against `HKQuantityTypeIdentifier.heartRate.rawValue` etc. Effort S, impact low.

### 3. Defensive double-authorization on every Start — minor

`requestAuthorization` is called from `ARRunnerWatchApp.task` (`ARRunnerWatchApp.swift:17-25`) and again from `HealthKitWorkoutSubstrate.begin()` (`HealthKitWorkoutSubstrate.swift:108`). The defensive re-call is documented and intentional — keep it — but it adds an awaitable hop to every Start tap even when permission was granted at launch. Consider gating on `healthStore.statusForAuthorizationRequest(toShare:read:)` to skip the round-trip when the answer is known.

### 4. Authorization denial has no user-facing surface — UX gap

`ARRunnerWatchApp` calls `try? await HealthKitWorkoutSubstrate.requestAuthorization()` (`ARRunnerWatchApp.swift:23`). If the user taps Don't Allow, the error is swallowed; later `viewModel.start()` will fail with a `String(describing: error)` failure surfaced as `.failed`, which is the only "fix me" path. There is no `Open Health Settings` button. Effort M, impact medium for v0.3.

### 5. Observer / background-delivery — not present

No `HKObserverQuery`, `HKAnchoredObjectQuery`, or `enableBackgroundDelivery(for:)`. Correct for a foreground-workout-only v0.2. No leaks. Flag for v1.0 if we ever want resting-HR or daily-step complications.

### 6. `HKLiveWorkoutBuilder` lifecycle — well-handled

`begin → beginCollection → endCollection → finishWorkout` order matches Apple's reference flow (`HealthKitWorkoutSubstrate.swift:131-184`). Delegate methods correctly forward via thread-safe continuations. `HKError.errorCode 7` (no auth) preflight is documented inline (`:104-108`) and matches the `healthkit-error-7-preflight-diagnostic` skill.

**Leak:** `state.session/builder` is never zeroed after `end()` (`HealthKitWorkoutSubstrate.swift:170-200`). Substrate retains `HKWorkoutSession` + builder until the substrate itself is released. Real-world impact is bounded — `WorkoutViewModel` builds a fresh substrate per Start via `substrateFactory()` (`WorkoutViewModel.swift:113`) — but a stricter `state.withLock { $0.session = nil; $0.builder = nil }` after success would tighten the window. Effort S, impact low.

## watchOS-Specific Patterns

### 1. `Task.sleep(nanoseconds:)` is the pre-5.7 form — modernize

Two tickers use `try? await Task.sleep(nanoseconds: 1_000_000_000)`:
- `WorkoutViewModel.startElapsedTicker` (`WorkoutViewModel.swift:365`)
- `WorkoutViewModel.startMirrorTicker` (`WorkoutViewModel.swift:386`)
- `WorkoutMirrorViewModel.start` stale poller (`WorkoutMirrorViewModel.swift:51`)

Prefer `try? await Task.sleep(for: .seconds(1))` (Duration-based API, watchOS 11+). Same behaviour, fewer magic constants, cancellation-aware. Effort S, impact low.

### 2. WidgetKit `TimelineProvider` uses pre-async callback form

`StartWorkoutProvider` (`ARRunnerWidgets/StartWorkoutWidget.swift:12-26`) implements the completion-handler `TimelineProvider`. In 2026 the idiomatic form is `async TimelineProvider` or `AppIntentTimelineProvider`. More importantly: this widget's entry is a `Date` literal that never changes, but `getTimeline` schedules a 30-minute refresh (`:23`). That's pure background-budget burn. Set `policy: .never` until the entry actually has dynamic content. Effort S, impact low.

### 3. `StartWorkoutIntent.perform()` is a TODO — BUG

`ARRunnerWidgets/StartWorkoutIntent.swift:11-14` returns `.result()` immediately and never routes to the workout flow. The widget's Start button foregrounds the app (because `openAppWhenRun = true`) but the watch lands on `WorkoutView` in `.idle`; the user still has to tap Start Run. v0.2 Story 1 acceptance ("user can start workout from Smart Stack widget") is not actually met. Effort M, impact high.

### 4. `WidgetCenter.shared.reloadAllTimelines()` never called

When the watch completes a workout (`WorkoutViewModel.confirmSave`/`confirmCancel`), no widget refresh fires. Fine for the current static entry; a blocker the moment any widget becomes workout-aware. Effort S, impact low — note for future.

### 5. Lock-screen complication not present

Per Joe's v0.2 Story 4 ("lock-screen complication visible during workout") — no `accessoryCorner`/`accessoryInline` widget family yet (only `accessoryRectangular`, `StartWorkoutWidget.swift:62`), no workout-active timeline entry, no `WidgetCenter` reload from `WorkoutController` transitions. **Planned work, not regression.** Effort L, impact high (v0.2 scope).

### 6. WCSession three-tier delivery is correct

`WatchConnectivityService.transmit` (`ARRunnerWatch/Sync/WatchConnectivityService.swift:62-104`) implements the documented `sendMessageData` → `updateApplicationContext` → `transferUserInfo` fallback (matches our `wcsession-three-tier-delivery` skill). Both `preferLatestOnly` and `preferQueued` are honoured. Phone-side ingest decodes via `JSONDecoder` and uses `bufferingNewest(8)` so a stalled Live tab drops old ticks — correct for "now"-only mirror UX.

### 7. WKCompanion bundle-id prefix — Joe-owned

`project.yml` controls the watch/phone/widget bundle IDs; out of code scope. Skill `wkcompanion-bundle-id-prefix-rule` documents the rule.

## Swift Idioms & Clean Code

- **No force-unwraps in non-test app code.** Only one `nil` check (`ActiveLookGlassesAdapter.swift:273`) was flagged by the regex, and it's `!= nil` (no unwrap). ✓
- **No `try!`.** ✓
- **Error handling** is consistent: `throws` for substrate/controller surface, `Result`-style is not used (good — `throws` is idiomatic in 2026 Swift). Failures are flattened to `String(describing: error)` for the UI's `.failed(String)` (`WorkoutViewModel.swift:137-138, 149, 159, 188, 203`). Acceptable for v0.2; consider a typed `LaunchError` for `.failed` in v0.3 so SwiftUI can show actionable messages (e.g. distinguish HK-denied from BLE failure from substrate I/O).
- **SPDX headers** present on every file. ✓
- **`os.Logger` with `privacy: .public`** used correctly in both WCSession services for non-PII transport diagnostics. ✓
- **`@discardableResult`** on `WorkoutController.start` / `.end` — appropriate, callers in `WorkoutViewModel` do consume the values (`:130, 182`).
- **Dependency injection via closure factories** (`@Sendable () -> any WorkoutHealthSubstrate`, `WorkoutViewModel.swift:71-72, 86-91`) is the right Swift 6 pattern — keeps `Sendable` boundaries explicit and previews testable. ✓

**Minor:** `WorkoutViewModel.apply(metric:)` (`:348-358`) drops `cadence`, `elevation`, `pace`, `duration` (and energy — see HK §1). If we add those metric kinds for the HUD layout, this needs expansion or a `default: ignored` log. Effort S, impact low.

## Dependency / API Currency (2026)

Richards owns the manifest/SDK currency sweep. Swift-language API surface this audit touched (Swift 6.0 / watchOS 11 / iOS 18 minimum, watchOS 12 GA shipped May 2026):

- `@Observable`, `NavigationStack`, `.foregroundStyle`, `containerBackground` — all current.
- `OSAllocatedUnfairLock<MutableState>` — current (replaces the bare `os_unfair_lock` C API). ✓
- `Task.sleep(nanoseconds:)` — works but superseded by `Task.sleep(for: Duration)` (see watchOS §1).
- `TimelineProvider` callback form — works but superseded by async / `AppIntentTimelineProvider` (see watchOS §2).
- watchOS 12 APIs (e.g. `WKExtendedRuntimeSession` improvements, expanded App Intent shortcuts) not yet adopted — appropriate, scope expansion for v0.3.
- HealthKit 2026 has no public-API churn that affects our surface; `HKLiveWorkoutBuilder` flow is unchanged from watchOS 10.

## Top 5 Debt Items (Prioritized)

| # | Item | Effort | Impact | Where |
|---|------|--------|--------|-------|
| 1 | `StartWorkoutIntent.perform()` is a TODO — widget Start button doesn't actually start a run (v0.2 Story 1 acceptance gap) | **M** | **High** | `ARRunnerWidgets/StartWorkoutIntent.swift:11-14` |
| 2 | HK active energy mis-mapped to `.duration` — live kcal from HealthKit never reaches UI/controller aggregate | **S** | **Med** | `ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift:271-272` + add `.energy` to `WorkoutMetric.MetricKind` |
| 3 | HK auth-denied UX gap — `try?` swallows error at launch, user gets only a stringified `.failed` on Start tap (no Settings CTA) | **M** | **Med** | `ARRunnerWatch/ARRunnerWatchApp.swift:23`, `WorkoutView.swift:117-121` |
| 4 | Modernize tickers + widget provider to Duration sleeps and async `TimelineProvider` (or `AppIntentTimelineProvider`); set widget timeline policy to `.never` while entry is static | **S** | **Low** | `WorkoutViewModel.swift:365,386`, `WorkoutMirrorViewModel.swift:51`, `StartWorkoutWidget.swift:21-25` |
| 5 | Substrate `state.session/builder` not cleared after `end()`; controller's `metrics` stream is `.unbounded`. Tighten lifecycle + cap to `.bufferingNewest(N)` | **S** | **Low** | `HealthKitWorkoutSubstrate.swift:170-200`, `WorkoutController.swift:80-82` |

## Out of Scope

- ActiveLook / CoreBluetooth / `ActiveLookGlassesAdapter` / `GlassesService` / `GlassesTransportFactory` — **Weiss**.
- CI workflow, SPM/Xcodegen manifest currency, third-party SDK versions, signing — **Richards**.
- `WorkoutMetric` / `EnergyEstimator` / `WCMessage` model design in Core — **Amber**, except where directly required by HK substrate routing (item #2 above).
- Bundle-IDs, entitlements, signing (`project.yml`) — **Joe**.
- Lock-screen complication, `WKExtendedRuntimeSession` — v0.2 planned work (Story 4), not a regression.
