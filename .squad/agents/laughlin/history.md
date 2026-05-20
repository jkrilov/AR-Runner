# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings


## Summary

**Archive:** Pre-rc12 development (rc5-rc11) documented in history-archive.md. Key patterns:
- rc5–rc8: 4-release blank-screen saga (power-on, write serialization, queryID, cfgSet). All fixes load-bearing.
- rc9: Polish (rotation 0→2, holdFlush wrap). Went blank on bench.
- rc10: Bisect (reverted rotation, kept holdFlush). Text upside-down but readable.
- rc11: Tried rotation=4. Went blank. Directive issued: bundle version bump into feature PRs.


## Active Sessions (Compacted)

### 2026-05-19T15:55:00Z — rc12: four-constant coordinate fix + bundled-bump validation
- Fixed the rotation=4 placement bug by updating four layout constants and shipping PR #71 with the version bump, xcodegen regen, and Info.plist placeholder check in the same PR.
- Durable lesson: blank `txt` with no 0xE2 usually means off-screen clipping; verify the bounding box against framebuffer bounds before blaming firmware.

### 2026-05-19T22:25:00Z — rc17: lifecycle split, finish-screen revalidation, battery → phone
- Split workout lifecycle from peripheral lifecycle by deleting `teardownTransport()`, pushing the finish frame before ending HK, and recomputing finish Y anchors under `y_fb = 255 − wearer_top`; battery mirroring to phone shipped in the same release.
- Validation held across the 0.3→0.4 bump (186/186 Core, watch build green, `v0.4.0-rc1` tagged).

### 2026-05-20T11:00:00-04:00 — rc2: GPS/discard/finish-layout bundle
- Moved generated-plist edits into `project.yml`, added a true discard path (`discard(at:)`), wired workout-scoped route building, and reshaped the finish screen to banner / distance / time+pace with extracted `ALookFontMetrics`.
- Durable lesson: save/discard need distinct substrate verbs, and additive WatchConnectivity fields should stay optional so old peers still decode.

## rc12–rc2 Pattern Evolution (Consolidated Summary, 2026-05-20)

**Six releases, one bundled-bump pattern.**

From rc12 through rc2, the release cadence has been **feature + version bump + tag in a single PR**, automatically TestFlight'd on CI green. This pattern cuts per-release overhead and eliminates manual coordination. All rc12–rc2 work has followed it consistently.

**Recurring learnings across the six-release span:**

1. **Coordinate-system clarity matters more than exact X,Y values.** The canonical `y_fb = 255 − wearer_top` (no font-height subtraction) formula has been revisited three times (rc12 → rc16 revalidation → rc17 finish-screen → rc2 reflow). Each revalidation either caught silent bugs (off-screen rendering) or re-confirmed the math. Lesson: pin the formula in tests, not just the constant values. When the formula changes OR a new rendering surface requires re-validation, the tests catch missing updates.

2. **Lifecycle ownership clarity prevents UX bugs.** rc17's discovery that "workout lifecycle ≠ peripheral lifecycle" (teardown-on-stop was breaking finish-screen readability) generalized to rc2 data-integrity: "confirm-save lifecycle ≠ persist-to-health lifecycle." Both required new protocol methods and terminal-path separation (never branch off a shared path). Pattern: when a UI action should have multiple outcomes (save = persist, cancel = discard, draft = auto-save), the substrate must have distinct verb methods. rc2 formalized this as a skill: `terminal-path-data-leak-qa`.

3. **ALooK font metrics deserve a typed constant.** Passed the same (height, per-font-width) pairs into layout calculations at least four times across rc12–rc2 (live HUD, finish screen, rc2 reflow). Richards recommended extraction in rc13; didn't land until rc2 via `ALookFontMetrics` struct. Lesson: extract early when you see a pattern repeat 2+ times. The 3rd and 4th use cases are slower and riskier than the 1st.

4. **xcodegen `Config/` is a generated artifact — edit project.yml, not the generated plist.** Cost of breaking this rule: silent data loss (the Info.plist edit vanishes on next xcodegen run). Lesson learned the hard way in rc2 with NSLocationWhenInUseUsageDescription. Rule: always touch project.yml first; never hand-edit generated files in Config/.

5. **WatchConnectivity schema bumps are backward-compat opportunities.** rc17 + rc2 both added optional fields (`glassesBattery`, `startedAt`) without requiring watch/phone version alignment. Lesson: Codable + Optional field + version bump in schema = old peers decode, don't block each other.

**Tests growth: 154 (rc12) → 195 (rc2), +41 tests across 6 releases.**

Most additions were pattern tests (pinning formulas, invariants, wire-byte contracts) rather than new feature coverage. The test cadence became denser as the protocol surface stabilized — more regression coverage per release.

---

### 2026-05-20T12:42:23-04:00 — rc3: GPS-route auth + discard returns to start
- Root causes were missing `HKSeriesType.workoutRoute()` share auth and `stopRuntimeTasks()` cancelling transport-scoped BLE observers; discard now lands in `.idle` with BLE preserved.
- Durable lesson: `insertRouteData` succeeding does not prove persistence, and helper names/comments must encode scope boundaries explicitly.

### 2026-05-20T13:19:07-04:00 — rc4: confirmationDialog binding race
- SwiftUI fired the Discard button action and the dialog binding setter in the same tick, letting `resumeFromFinish()` race `confirmCancel()`; the synchronous `acknowledgeFinishChoice()` pre-transition closed the hole.
- Durable lesson: async terminal flows can still interleave at suspension points on `@MainActor`, so state-gated callbacks need a synchronous acknowledgement before spawning `Task { ... }`.

### 2026-05-20T15:33:22-04:00 — v0.5 PR 2: Strava OAuth + token store + Settings
- Added phone-side Strava OAuth/token plumbing, the first phone test target, and a Settings tab; validation was 16/16 phone tests, 215/215 Core, and an ARRunnerPhone build.
- Durable lesson: xcodegen phone test targets need `bundle.unit-test` + `GENERATE_INFOPLIST_FILE: YES` + app-target `excludes: ["Tests/**"]`, and plist additions still belong in `project.yml`.

---

### 2026-05-20T16:06:42-04:00 — v0.5 PR 3: Strava uploader + queue + History tab

- **Files added:** `ARRunnerPhone/Strava/StravaUploadService.swift`, `StravaUploadQueue.swift`, `WorkoutTCXBridge.swift`, `AutoUploadCoordinator.swift`; `ARRunnerPhone/Views/HistoryView.swift`, `HistoryViewModel.swift`. Tests: `StravaUploadServiceTests`, `StravaUploadQueueTests`, `WorkoutTCXBridgeTests` (22 new tests, 38 phone total — all pass).
- **Files modified:** `StravaTokenStore.swift` (added `forceRefresh()` for 401 retry), `ARRunnerPhoneEnvironment.swift` (wires `AutoUploadCoordinator` at launch), `RootView.swift` (History tab replaces placeholder).
- **Queue design:** actor-based, persists to `Documents/StravaUploadQueue/{queue.json, tcx/{uuid}.tcx}`. Per-entry exponential backoff 30/60/120/300/900s, max 5 retries → `.failed`. 429 → queue-global `pauseUntil` (uses `Retry-After` header, defaults 15 min). Re-uploads use the *bytes* on disk — `StravaUploadService.upload(workoutID:startDate:tcx:)` is the wire-level entry point; `upload(workout:)` is the convenience wrapper.
- **401 retry path:** added `StravaTokenStore.forceRefresh()` rather than over-loading `validAccessToken()` — keeps the proactive-refresh path (within 60s of expiry) separate from the reactive-refresh path (server says it's stale).
- **Auto-upload trigger:** chose to listen for `WCMessage.workoutLifecycle(.ended)` and poll HK for recently-saved workouts (5-min window, 3s settle delay), rather than bump the WC schema with a "workout saved" case. HK is source of truth per D-Strava-4, and adding a schema case would touch ARRunnerCore + watch + phone for a UX nicety.
- **HK source filter:** `HistoryViewModel.arRunnerSourceBundleIDs = {com.arrunner.phone, com.arrunner.phone.watchkitapp}` — applied in-memory post-query, because the NSPredicate string form of `HKQuery.predicateForObjects(from: source)` is fragile and 200 workouts is a trivial filter. The set is `nonisolated static let` so HK query continuations (off main actor) can read it.
- **Bridge testability:** split `WorkoutTCXBridge.mergeTrackpoints(locations:heartRates:)` out as a pure function over local `LocationSample` / `HRSample` value types so the merge logic is unit-tested without `HKHealthStore` / `CLLocation`.
- **Swift 6 gotchas hit:** (1) `@Sendable () -> Date` clock closure cannot capture a local `var` — used a small `MutableClock` class in tests. (2) Mutating `var collected: [CLLocation]` from the `HKWorkoutRouteQuery` batch callback was flagged; wrapped in a `final class Box: @unchecked Sendable`. (3) `@MainActor`-isolated `static let` on a view model can't be read from a `Sendable` HK closure — marked it `nonisolated`. (4) `URLSession`'s `upload(for:from:)` had to be wrapped in a one-line transport protocol extension to match the testable `StravaUploadTransport` seam.
- **xcodeproj regen:** `xcodegen generate` is required after adding new files (the `*.xcodeproj/` is gitignored and built on demand; ran it before the build/test cycle).
- **Build / test cycle used:** `xcodebuild -scheme ARRunnerPhone -destination 'platform=iOS Simulator,id=EC467EC9-2998-439B-AA2B-1B4ED39C3AA5' -configuration Debug test CODE_SIGNING_ALLOWED=NO -only-testing:ARRunnerPhoneTests` (iPhone 16 / iOS 18.1 is the local simulator that's installed). Core tests via `swift test --package-path ARRunnerCore`.
