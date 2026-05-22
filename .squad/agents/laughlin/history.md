# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings

### 2026-05-21T11:46:12-04:00 — Strava API compliance pass (button copy, deauth, token-exchange client_id)
- **Brand-guideline button:** Strava requires the exact string "Connect with Strava" (not "Connect to Strava") and a 48pt button height on the orange (#FC4C02) CTA. Updated `SettingsView.connectButton` to use `.frame(height: 48)` instead of `.padding(.vertical, 8)` so the asset matches their published spec without needing the official PNG. Comment on `Color.stravaOrange` now links the guidelines.
- **Deauthorize on disconnect:** Strava's API agreement requires revoking the grant server-side when a user disconnects — local token deletion alone leaves the app installed in the athlete's Strava settings. Added `StravaOAuthService.deauthorize(accessToken:)` that POSTs `{"access_token": ...}` to the worker's `/deauthorize` endpoint (worker proxies to `POST https://www.strava.com/oauth/deauthorize`). Best-effort: errors are logged and swallowed. `SettingsViewModel.disconnectStrava()` fires it as a plain `Task { ... }` (NOT `Task.detached` — keeps the @MainActor oauth capture Sendable-clean) and immediately calls `tokenStore.disconnect()` regardless of network outcome.
- **Token accessor for deauth:** Added `StravaTokenStore.currentAccessToken: String?` — a non-refreshing read of the cached token. Deliberately did NOT use `validAccessToken()` because (a) it's async/throws and would force the disconnect path to await, (b) a stale token still identifies the grant for revocation, and (c) we must not block local clear on a refresh round-trip.
- **Token-exchange client_id fix:** The worker's `/token` endpoint requires `client_id` in the body to disambiguate which Strava app the auth code belongs to (worker holds the matching `client_secret` per D-Strava-3). `exchangeCodeForTokens` was only sending `{"code": code}` — added `client_id: StravaConfig.clientID`. This was a latent bug from PR #84 OAuth landing; refresh path was unaffected because `WorkerStravaTokenRefresher` already sent it.
- **Validation:** 39/39 ARRunnerPhoneTests pass. Pre-existing `test_disconnect_clearsTokensAndResetsAutoUpload` still passes — it uses a real `StravaOAuthService` and the fire-and-forget Task fires a stray network POST during the test (the test doesn't await it). If this becomes flaky in CI, the right fix is to inject deauth via a transport protocol seam in `StravaOAuthService` (mirror what `StravaUploadService` does with `StravaUploadTransport`). Left as-is for now since tests are green.
- **File paths touched:** `ARRunnerPhone/Views/SettingsView.swift`, `ARRunnerPhone/Views/SettingsViewModel.swift`, `ARRunnerPhone/Strava/StravaOAuthService.swift`, `ARRunnerPhone/Strava/StravaTokenStore.swift`. No project.yml or Info.plist changes needed (no new files, no new plist keys). Did NOT commit/push per instruction.


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

### 2026-05-21T13:30:00-04:00 — Appearance settings (Light/Dark/System)
- Added `AppearanceMode` enum (`.system/.light/.dark`) in `ARRunnerPhone/Views/AppearanceMode.swift`. `.system` maps to `colorScheme: ColorScheme? = nil` so `preferredColorScheme(nil)` falls through to device setting — the canonical pattern, no need to read `UITraitCollection`.
- Persistence via `@AppStorage("appearanceMode")` on the `App` struct AND `SettingsView` (both bind to the same UserDefaults key, so the picker drives the root override live — no NotificationCenter or environment plumbing needed).
- Stored the raw `String` rather than the enum directly: `@AppStorage` supports `RawRepresentable where RawValue == Int` natively but String-RawValue enums need a manual `Binding` shim anyway. Storing the string keeps the default value path trivial (`"system"`) and avoids a `RawRepresentable` extension.
- Segmented picker placed in its own `appearanceSection` between Strava and About — kept Strava section ordering intact since it's the primary CTA.
- Validation: 39/39 ARRunnerPhoneTests pass, ARRunnerPhone build green. No new files needed in project.yml (target uses `path: ARRunnerPhone` recursive scan).

### 2026-05-22T07:36:00-04:00 — Apple Watch Ultra Action Button support
- **Enum:** `ARRunnerWatch/Settings/ActionButtonMode.swift` mirrors `AppearanceMode` (raw String, CaseIterable, Identifiable, `title`/`detail` for picker labels). Cases: `.off / .splits / .pauseResume / .toggleHUD`. Default is `.splits`.
- **Persistence:** `@AppStorage("actionButtonMode")` — same key surfaced via `ActionButtonMode.storageKey`. Coordinator reads it directly from `UserDefaults.standard` since `AppIntent.perform()` can't capture SwiftUI state.
- **Dispatch architecture:** `ActionButtonIntent` (in `ARRunnerWatch/ActionButton/`) is an `AppIntent` with `openAppWhenRun = true`. It runs *in-process* (not in the Widgets extension like `StartWorkoutIntent`), which lets a MainActor singleton `ActionButtonCoordinator` route presses straight to the live `WorkoutViewModel`. `WorkoutView.task` calls `ActionButtonCoordinator.shared.attach(viewModel:)`; if a press lands before the UI wakes, the coordinator parks the mode in `pendingMode` and replays it on attach.
- **Why an AppShortcut:** Action Button binding on watchOS 10+ is done from system Settings → Action Button → App. The intent must be discoverable (`AppShortcutsProvider`) for it to appear in the picker, otherwise the user can't bind it without typing a Shortcuts phrase.
- **Settings UI:** new `WatchSettingsView` (gear icon in `WorkoutView` toolbar). Watch-only — phone Settings stays scoped to Strava/appearance. Future watch-only prefs land in this view.
- **View-model entry points:**
  - `markSplitFromActionButton()` → records `ActionButtonSplit(index, elapsedAtPress, delta, distanceMetersAtPress, wallClock)` in a new private(set) `actionButtonSplits` array. Only fires while `launchState == .running`; returns Bool so the coordinator only haptics on successful capture.
  - `togglePauseResumeFromActionButton()` → swaps `.running` ↔ `.paused`. Ignored from terminal / `.pendingFinish` states so a stray press can't strand the workout.
  - `toggleHUDFromActionButton()` → flips `private(set) var hudVisible` and queues an `ActiveLookCommand.power(on:)` frame on the transport. Safe when offline (just the flag flips). On power-up, immediately calls `pushHUDFrameIfConnected` so the wearer doesn't sit on a blank panel until the next 1Hz tick.
- **Haptics:** coordinator plays `.notification` for split captures, `.start` for pause/resume + HUD toggles. Provides tactile confirmation even when AR glasses aren't connected. No-op presses (idle workout, off mode) play nothing so the user knows the press was ignored.
- **State reset:** `actionButtonSplits` is cleared and `hudVisible` set back to `true` in `resetLiveCounters()` so a fresh workout starts at split 1 with HUD presumed on.
- **Pattern echo:** the coordinator/intent split is intentionally the same shape as `StartWorkoutIntent` + `AppGroupPendingWorkoutStartStore` — drop a parked request, drain on UI ready. Future hardware-button work should follow this template.
- **Build verified:** `xcodebuild -scheme ARRunnerWatch -destination 'generic/platform=watchOS Simulator'` succeeds; all 215 ARRunnerCore tests still pass.

### 2026-05-22T10:11:46-04:00 — Action Button fix (v0.5.5): process isolation + shortcut registration
- **Two real bugs in v0.5.4 Action Button:** (1) AR-Runner never appeared in Settings → Action Button → Shortcut picker; (2) even if bound via Shortcuts app, presses did nothing. Root causes were independent.
- **Bug 1 — picker registration:** `AppShortcutsProvider` alone is necessary but not sufficient. The system caches the shortcuts catalog and won't refresh after a build/install without an explicit `ARRunnerAppShortcuts.updateAppShortcutParameters()` call. Added it inside `ARRunnerWatchApp`'s root `.task` (guarded `if #available(watchOS 10.0, *)` + `#if canImport(AppIntents)`) so every cold launch re-publishes. Cheap, idempotent.
- **Bug 2 — process isolation:** This was the load-bearing one. `ActionButtonIntent.perform()` runs in the **system Shortcuts process** when invoked via the hardware Action Button, NOT in the watch host. Two cascading consequences:
  - `ActionButtonCoordinator.shared` accessed from `perform()` is a *different singleton instance* than the one `WorkoutView.task` attached to. `pendingMode` parked on it was discarded when that process exited.
  - `UserDefaults.standard` is per-bundle/per-process — the intent process and the host process had separate `.standard` containers, so even if dispatch had reached the right coordinator it would have read a stale or default mode.
- **Fix shape:** mirrors the existing `PendingWorkoutStartStore` pattern.
  - New `ARRunnerCore/Workout/PendingActionButtonPress.swift` — `AppGroupPendingActionButtonPressStore` writes a timestamp (only) to `group.com.arrunner.shared`. Mode is *not* on the wire — read fresh from the shared store at consume time, so a mid-flight mode change can't get sandwiched between press and dispatch. 30s freshness (vs 60s for workout-start, because the Action Button is foreground UX).
  - `ActionButtonMode.sharedDefaults` — new static helper returning `UserDefaults(suiteName: "group.com.arrunner.shared")` with a `.standard` fallback for previews/tests. Marked `nonisolated(unsafe)` because Swift 6 doesn't see `UserDefaults` as `Sendable` and adding `@MainActor` would force every reader (including the intent's `perform()`) onto the main actor. The static suite handle is effectively immutable post-launch — safe per the same reasoning Apple's own `UserDefaults.standard` uses.
  - `ActionButtonIntent.perform()` now writes the flag *first* (authoritative path that survives process boundaries), then opportunistically calls the in-host coordinator on the fast path. `WorkoutView.task` and the `scenePhase == .active` change both call `ActionButtonCoordinator.shared.consumePendingPress()` so a press lands within milliseconds of foregrounding.
- **Settings store migration:** `WatchSettingsView`'s `@AppStorage(ActionButtonMode.storageKey, store: ActionButtonMode.sharedDefaults)` and the watch-side `WatchConnectivityService.didReceiveApplicationContext` mirror both now write to the shared App Group suite so the intent process sees the latest pick. Phone-side `@AppStorage` stays on `.standard` because the phone never dispatches the intent — its UI just mirrors what the watch chose.
- **Plist NOT needed:** `WKSupportsActionButton` is *not* a real Info.plist key. The watchOS 10+ Action Button pipeline is entirely `AppShortcutsProvider`-driven; nothing in the plist makes an app appear in Settings → Action Button. Confirmed via Apple docs + web research before touching project.yml.
- **App Group entitlement:** already present on watch target (`group.com.arrunner.shared`) for the existing pending-workout-start flow. Reused as-is, no entitlement change required.
- **Files touched:** `ARRunnerCore/Sources/ARRunnerCore/Workout/PendingActionButtonPress.swift` (new), `Shared/Settings/ActionButtonMode.swift`, `ARRunnerWatch/ActionButton/ActionButtonIntent.swift`, `ARRunnerWatch/Settings/ActionButtonCoordinator.swift`, `ARRunnerWatch/Views/WorkoutView.swift`, `ARRunnerWatch/Views/WatchSettingsView.swift`, `ARRunnerWatch/Sync/WatchConnectivityService.swift`, `ARRunnerWatch/ARRunnerWatchApp.swift`, `project.yml` (0.5.4→0.5.5, build 33→34).
- **Validation:** `swift test --package-path ARRunnerCore` → 215/215 pass. `xcodebuild ARRunnerWatch` (watchOS Simulator) → BUILD SUCCEEDED. `xcodebuild ARRunnerPhone` test → 39/39 pass.
- **Durable lesson — AppIntents are not in-host by default:** Any AppIntent that has to mutate live host state must use a cross-process flag (App Group `UserDefaults`, `App Group` files) and let the foregrounded host drain it on `scenePhase == .active`. The "singleton in the same target" assumption only holds when the intent is invoked from the host's own UI (e.g., a Button(intent:) tap from a foregrounded SwiftUI view). System surfaces — Shortcuts, Action Button, Siri, widgets — all execute the intent out-of-host. This generalizes: any future hardware-button / Siri / Shortcuts integration follows the `PendingWorkoutStartStore` / `PendingActionButtonPressStore` template.
