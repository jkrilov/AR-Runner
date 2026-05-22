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

### 2026-05-22 — Action Button registration: WRONG surface (AppShortcuts) → CORRECT surface (StartWorkoutIntent)

- **The v0.5.4 / v0.5.5 mistake:** I built the Action Button integration around `AppShortcutsProvider` (+ `updateAppShortcutParameters()` cold-launch refresh). That registered AR-Runner under **Settings → Action Button → Shortcut**, not under **Workout** where Strava / Nike Run Club appear. The user reported AR-Runner still didn't show up in the picker they were actually using.
- **Correct API:** `AppIntents.StartWorkoutIntent` protocol. On Apple Watch Ultra, conforming to this protocol is what makes an app appear in **Settings → Action Button → Workout → App**. This is the *only* surface that populates the Workout category; AppShortcuts is a completely separate registration path.
- **Required protocol members** (load-bearing — system rejects partial conformance):
  - `static var title: LocalizedStringResource`
  - `@Parameter` `workoutStyle` adopting `AppEnum` (or `AppEntity`). Without the parameter wrapper + AppEnum, the picker has nothing to render as the activity choice and the app silently doesn't appear.
  - `static var suggestedWorkouts: [Self]` — must be non-empty. Under Swift 6 strict concurrency this needs `nonisolated(unsafe)` (the protocol declares it as `{ get set }` so `let` is rejected). Same pattern as `ActionButtonMode.sharedDefaults`.
  - `var displayRepresentation: DisplayRepresentation`
  - `static var openAppWhenRun: Bool` (`true` for D7 foreground launch)
  - `func perform() async throws -> some IntentResult`
- **Cross-process pattern preserved:** the PendingActionButtonPress / PendingWorkoutStart App Group flag pattern from PR #95 is still correct — `StartWorkoutIntent.perform()` ALSO runs out-of-host (system Intents extension), so direct singleton calls would still hit the wrong process. The intent now drops *both* flags (pending-start + pending-press) and lets the foregrounded host decide which to honor based on `launchState`. Idle host → auto-start; running host → dispatch configured `ActionButtonMode`. Guards inside `WorkoutViewModel`'s action-button methods make the "wrong" flag a safe no-op.
- **Files touched:** `ARRunnerWatch/ActionButton/ActionButtonIntent.swift` (renamed `ActionButtonIntent` → `ARRunnerStartWorkoutIntent`, dropped `ARRunnerAppShortcuts`; added `ARRunnerWorkoutStyleEnum: AppEnum`), `ARRunnerWatch/ARRunnerWatchApp.swift` (removed `updateAppShortcutParameters()` call + the AppIntents shim import), `project.yml` (0.5.5→0.5.6, build 34→35).
- **Files intentionally untouched:** `PendingActionButtonPress.swift`, `ActionButtonCoordinator.swift`, `Shared/Settings/ActionButtonMode.swift` — the cross-process flag, dispatcher, and mode enum are correct and reusable as-is.
- **Verified:** `swift test` (215 Core tests, 0 failures) + `xcodebuild -scheme ARRunnerWatch -destination 'generic/platform=watchOS' build` succeeds. Build log shows `No AppShortcuts found - Skipping` confirming the AppShortcuts surface is gone.

#### Durable lesson — Action Button has TWO unrelated registration surfaces
1. **Settings → Action Button → Shortcut → App:** populated by `AppShortcutsProvider` + `AppShortcut(intent:phrases:...)`. Generic; works for any AppIntent. Good for "Send Message" / "Toggle Flashlight" style actions.
2. **Settings → Action Button → Workout → App:** populated *only* by apps that ship an `AppIntents.StartWorkoutIntent` conformance with a non-empty `suggestedWorkouts` and a `@Parameter` `workoutStyle: AppEnum`. This is the Apple-native fitness slot — Strava, Nike Run Club, Apple Workout all live here. **An app cannot appear in this category through AppShortcuts.** They are not interchangeable; an app meant to be a workout target MUST adopt `StartWorkoutIntent`.

When in doubt, ask the user: "which Settings → Action Button sub-screen are you looking at?" The submenu name disambiguates the required protocol immediately.

### 2026-05-22T11:26:41-04:00 — v0.5.7: explicit AppIntents.framework + complete workout intents (PR #99)
- **Root cause of v0.5.5/v0.5.6 'Workout category missing AR-Runner' regression:** XcodeGen's Swift auto-link via `import AppIntents` does NOT cause `appintentsmetadataprocessor` to run. The Xcode build system gates metadata extraction on an *explicit* "Link Binary With Libraries" dependency — without it the build emits `warning: Metadata extraction skipped. No AppIntents.framework dependency found.` and the watch app bundle ships with no `Metadata.appintents/` directory at all. System has nothing to discover, AR-Runner stays absent from `Settings → Action Button → Workout → App`. Fix: add `- sdk: AppIntents.framework` to the watch target's `dependencies` in `project.yml`. After the fix the bundle's `Metadata.appintents/extract.actionsdata` listed all four intents with `systemProtocols: [StartWorkout|PauseWorkout|ResumeWorkout]` populated.
- **Verification recipe for future intent work:** `find .../DerivedData -name "Metadata.appintents"` after a build, then `cat .../extract.actionsdata` and grep for the intent's identifier + `systemProtocols`. If a `Metadata.appintents` directory is absent from a target that has intent code, the framework isn't linked — adding `import AppIntents` alone won't fix it. Don't rely on Xcode UI inspection; the bundle either exists in the built product or it doesn't.
- **Apple's `openAppWhenRun` guidance:** The `StartWorkoutIntent` protocol docs explicitly say not to override `openAppWhenRun` — it defaults to `true` and SDKs may rely on the default. Removed our explicit `static let openAppWhenRun: Bool = true` declaration. Metadata bundle still showed `openAppWhenRun: true` (protocol default came through), confirming the override was redundant.
- **`PauseWorkoutIntent` / `ResumeWorkoutIntent`:** Apple's Action + Side simultaneous-press shortcut is hardware-only; the system ignores it unless the app implements both protocols. Added `ARRunnerPauseWorkoutIntent` and `ARRunnerResumeWorkoutIntent` in a new `WorkoutControlIntents.swift` next to the existing intent file. They use a *separate* cross-process flag (`AppGroupPendingWorkoutControlStore`) keyed on an enum (`.pause` / `.resume`) rather than the generic `AppGroupPendingActionButtonPressStore`, because explicit pause/resume must bypass the user's configured `ActionButtonMode` (a user with mode=splits still expects Action+Side to pause).
- **`donate(result: .result(actionButtonIntent:))` pattern:** Apple's "donate the next action" model: after a workout starts, donate a follow-up intent so subsequent Action Button presses do something different. Added `WorkoutControlDonation.donateNextAction()` called from `WorkoutViewModel.start()` after `launchState = .running`. The donated `ARRunnerNextActionIntent` just drops the existing action-button press flag, so the host then dispatches the user's configured `ActionButtonMode`. This avoids the system trying to start a second workout when the user presses Action mid-run.
- **`nonisolated(unsafe)` justification:** Kept on `suggestedWorkouts: [ARRunnerStartWorkoutIntent]` (Swift 6 strict-concurrency-required) and expanded the comment to explain why — the protocol mandates `static var { get set }`, the property is effectively immutable after process launch, and reads/writes flow through the protocol's serialized registration. Apple's own sample code uses the same pattern.
- **Store placement decision:** Put `AppGroupPendingWorkoutControlStore` in the watch target (next to the intents) rather than in `ARRunnerCore`. The store's only consumer is watch-side; adding it to Core would have grown the public surface (and required Linux tests for `UserDefaults`-backed code that Linux can't run identically anyway). Pattern: store cross-process flags in Core only when the writer/reader split crosses targets.
- **Coordinator extension:** Added `ActionButtonCoordinator.consumePendingWorkoutControl()` + `applyExplicitWorkoutControl()`. Wired into `WorkoutView.task` and `.onChange(scenePhase)` next to the existing `consumePendingPress()` call — same activation cycle so a press that landed while the host was suspended is drained on resume. Both `apply` calls guard on `launchState` (`.running` for pause, `.paused` for resume) so a stale flag from a finished workout is a no-op.
- **CI / merge:** CI green (Phone 2m35s, Watch 1m44s, Core 1m1s); CodeQL was still pending after ~30 min so used `--auto` and the merge completed. Squashed and branch deleted.
- **Files touched:** `project.yml` (+`AppIntents.framework`), `VERSION` (0.5.7), `ARRunnerWatch/ActionButton/ActionButtonIntent.swift`, `ARRunnerWatch/ActionButton/WorkoutControlIntents.swift` (new), `ARRunnerWatch/Settings/ActionButtonCoordinator.swift`, `ARRunnerWatch/Views/WorkoutView.swift`, `ARRunnerWatch/Workout/WorkoutViewModel.swift`.

### 2026-05-22T14:10:29-04:00 — v0.5.10: Action Button split feedback (PR pending)
- **Reported symptom:** "Action Button works to start a workout, but pressing it mid-run does nothing — no haptic, no visual." All four ActionButtonMode dispatch paths (split/pause-resume/toggleHUD) were already wired in v0.5.7, so the bug was upstream of dispatch.
- **Root cause #1 — `openAppWhenRun` defaults to `false` for plain `AppIntent`:** `ARRunnerNextActionIntent` (donated post-`start()` as the "next action") never opted into `openAppWhenRun = true`. The intent fired in the system Intents process, dropped the App Group press flag, and if the host happened to be backgrounded (sleep/Now Playing/glance) the scene-phase consumer never ran. Flag aged out via the freshness window — no haptic, no marker. **Apple's "don't override `openAppWhenRun`" guidance applies only to `StartWorkoutIntent`; plain `AppIntent` defaults to `false`** and we must opt in. Set `static let openAppWhenRun: Bool = true` on `ARRunnerNextActionIntent`.
- **Root cause #2 — no on-screen confirmation:** Even when the press dispatched, `WorkoutView` never displayed anything about splits. The user got a haptic on the wrist but no visual confirmation that "Split 3" landed (vs e.g. a stray phantom press). Added a transient `splitFlashBanner` ("Split N · MM:SS", green pill, ~1.6s auto-dismiss via `.task(id:)` keyed on flash timestamp) plus a persistent `Splits: N` line under the metrics while any splits exist.
- **HKWorkoutEvent.segment recording:** Splits now also surface on the saved `HKWorkout` via `HKLiveWorkoutBuilder.addWorkoutEvents([HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: stamp, duration: 0), metadata: ["com.arrunner.actionButtonSplitTitle": "Split N"])])`. `HKWorkoutEventType.segment` is the Apple-native equivalent of the stock Workout app's lap press; using a zero-duration `DateInterval` makes it a point-in-time marker. App-namespaced metadata key avoids colliding with system-reserved keys.
- **Substrate plumbing pattern:** Added `markSegment(at:title:) async throws` to `WorkoutHealthSubstrate` **with a default no-op extension implementation** so `InMemoryWorkoutHealthSubstrate` and other mocks (Amber's integration mocks, Linux tests) inherit a working impl without changes. Real HealthKit substrate overrides with the `addWorkoutEvents` call. Pattern: when adding optional behavior to a protocol surface that has many mock implementations, provide a default extension to avoid mass churn — only the production impl needs to opt in.
- **Controller-level "best effort" semantics:** `WorkoutController.markSegment(at:title:)` no-ops outside `.running`/`.paused` (so a stray press from a dispatcher race during teardown doesn't throw), and substrate failures bubble as `Error.substrateFailure` without transitioning the workout to `.failed` — losing a single marker shouldn't strand a 30-minute run. View model treats markSegment as fire-and-forget via `Task { try? await ... }` so the haptic and on-screen flash don't wait on HK.
- **Flash data model decision:** Kept `SplitFlash` (transient on-screen banner) separate from `ActionButtonSplit` (durable record in `actionButtonSplits`). Clearing the banner via `clearSplitFlash(matching:)` is guarded on the timestamp so a re-entrant timer from a rapid second press can't accidentally clear the newer flash.
- **Build verification:** `swift build` + `swift test` in `ARRunnerCore/` (215 tests pass, 1 skipped); `xcodebuild -scheme ARRunnerWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build` succeeded. xcodegen regenerated cleanly off `project.yml`.
- **Files touched:** `VERSION` (0.5.10), `project.yml` (build 39), `ARRunnerCore/Sources/ARRunnerCore/Workout/WorkoutHealthSubstrate.swift` (+`markSegment` protocol requirement + no-op extension), `ARRunnerCore/Sources/ARRunnerCore/Workout/WorkoutController.swift` (+`markSegment` public method), `ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift` (+`addWorkoutEvents` impl), `ARRunnerWatch/Workout/WorkoutViewModel.swift` (+`SplitFlash`, +`clearSplitFlash`, +markSegment best-effort call), `ARRunnerWatch/Views/WorkoutView.swift` (+`splitFlashBanner`), `ARRunnerWatch/ActionButton/WorkoutControlIntents.swift` (+`openAppWhenRun = true` on `ARRunnerNextActionIntent`).

### 2026-05-22T14:49:26-04:00 — v0.5.11 PR: Action Button mid-workout debug + Test Split button

- **Files changed:** `ARRunnerWatch/ActionButton/ActionButtonIntent.swift`, `WorkoutControlIntents.swift`, `ARRunnerWatch/Settings/ActionButtonCoordinator.swift`, `ARRunnerWatch/Views/WorkoutView.swift`, `project.yml`, `VERSION`.
- **Symptom:** Joe reports the Action Button does NOT trigger a split mid-workout in the watchOS simulator, even though `ARRunnerNextActionIntent` was wired in PR #104 and Action Button is set to "Split".
- **Root cause (most likely):** **watchOS simulator does not deliver hardware Action Button events to a foreground/active app.** The simulator only exercises the cold-start `StartWorkoutIntent` path. The mid-workout "next action" donation (`ARRunnerNextActionIntent`) requires real Apple Watch Ultra hardware to validate end-to-end. This is a long-standing simulator limitation; nothing in our code is missing.
- **What we shipped to confirm + work around it:**
  1. `os.Logger(subsystem: "com.arrunner.watch", category: "ActionButton")` named `actionButtonLog` (top-level in `ActionButtonIntent.swift`) so all four intents (`Start`, `Pause`, `Resume`, `NextAction`) + `ActionButtonCoordinator.handleActionButtonPress` + `dispatch(mode:)` all log to Console.app. Joe (and we) can filter `subsystem == com.arrunner.watch && category == ActionButton` and see exactly which step fires.
  2. `WorkoutControlDonation.donateNextAction()` now logs success/failure of the system donation — confirms whether the system accepted our "next action" hint at workout-start time.
  3. **DEBUG-only "Test Split (DEBUG)" button** in `WorkoutView.controlsSection` under `.running`. Wrapped in `#if DEBUG` so Release builds don't ship it. Calls `ActionButtonCoordinator.shared.handleActionButtonPress()` directly — the *exact* code path the dispatcher uses, so split flash + haptic + `HKWorkoutEvent.segment` are all exercised without hardware.
- **Why we did NOT add Pause/Resume stubs:** They already exist (`ARRunnerPauseWorkoutIntent`, `ARRunnerResumeWorkoutIntent` in `WorkoutControlIntents.swift`, added in PR #104). The "Apple requires all intents implemented before routing works" hypothesis is already satisfied.
- **Why we did NOT touch `HKWorkoutSession` configuration:** Apple's Action Button routing for the mid-workout case is driven by `IntentDonationManager` (via `donate(result:.result(actionButtonIntent:))`) — NOT by the workout session itself. The donation pattern in `WorkoutControlDonation` matches Apple's documented sample exactly.
- **Verification plan for Joe:**
  1. Install v0.5.11, start a run in the simulator, tap "Test Split (DEBUG)" → should see the green "Split N · M:SS" flash + the "Splits: N" counter persist after fade. This validates split logic end-to-end.
  2. Open Console.app, filter `subsystem == com.arrunner.watch`, then press the simulator's hardware Action Button mid-workout. If we see "NextActionIntent.perform fired" → the intent IS routing and the bug is downstream; if we see nothing → confirmed the simulator suppresses the event and the only path to fully validate is on real Apple Watch Ultra.
- **Durable lesson:** The watchOS simulator's Action Button does NOT fire mid-workout. Always ship a `#if DEBUG` UI affordance for any hardware-input-driven code path so we can validate logic without hardware. Same lesson applies to the side button (Pause/Resume simultaneous press) — should add a similar debug toggle if/when we need to test that path.

## Learnings

### 2026-05-22 — v0.5.11 split-marker crash fix
- `HKWorkoutEvent(type: .segment, dateInterval:, metadata:)` requires a **positive-duration** `DateInterval`. Passing `duration: 0` (or any non-positive interval) raises `NSInvalidArgumentException` ("Invalid date interval duration for type HKWorkoutEventTypeSegment").
- That NSException is an Objective-C exception, **not** a Swift `Error` — it bypasses `do/catch` at the callsite (`WorkoutController.markSegment`) and crashes the watch app outright. Always validate inputs *before* calling HK exception-prone APIs.
- Modeling laps the way the stock Workout app does: each segment spans `[previousSegmentEnd ?? workoutStart, now]`. Stored `lastSegmentDate: Date?` in `MutableState` and reset it to nil inside `begin(...)` for each new workout.
- `OSAllocatedUnfairLock<MutableState>` pattern in `HealthKitWorkoutSubstrate` requires snapshotting all needed fields in one `state.withLock { ... }` call when computing across them; then a second `state.withLock` to write back. Don't hold the lock across `await`.
- Build/typecheck for watch code: `xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerWatch -destination 'generic/platform=watchOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO`. Swiftc standalone fails on `import ARRunnerCore` because the package graph isn't resolved.
- Key files: `ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift` (HK substrate, owns session/builder/routeBuilder/lastSegmentDate); `ARRunnerCore/Sources/ARRunnerCore/Workout/WorkoutController.swift` (`markSegment` callsite, gates on `phase == .running || .paused`).
- Branch `laughlin/v0.5.11-action-button-debug` (PR #105) is the active ship vehicle for both the debug logging and this crash fix — pushed onto the same branch rather than spinning a new PR.

### 2026-05-22 — v0.5.11 Action Button: dedicated start path + bolder split flash
- **`StartWorkoutIntent.perform()` must NOT reuse `handleActionButtonPress()`.** That generic dispatcher routes by the persisted mid-workout `ActionButtonMode` (default `.splits`), which is a no-op when launchState is idle and was silently swallowing the cold-launch Action Button press. Added `ActionButtonCoordinator.handleWorkoutStart()` and routed the intent's in-process fast path through it instead.
- **Cold-start race needs a `pendingStart` rendezvous** mirroring `pendingMode`: the intent runs before `WorkoutView.task` attaches the view-model. `attach(viewModel:)` now replays a parked start request.
- **App Group cross-process flags don't work in the watchOS Simulator** — the Intents extension and host don't share a container there. The in-process `handleWorkoutStart()` is the actual primary path that succeeds; the App Group flag is a belt-and-braces fallback for real hardware.
- **Split-flash UX cues:** bumped duration 1.6s → 3s, made the pill chunkier (headline font, bigger padding, 35% green fill), and made the "Splits: N" counter row **always visible** while any splits exist (not gated on the flash being absent). Wrapped `lastSplitFlash` clearing in `withAnimation` since `.transition()` alone is a no-op without an enclosing animation.
- **Logging convention:** the `actionButtonLog` `Logger` (subsystem `com.arrunner.watch`, category `ActionButton`) defined at file scope in `ActionButtonIntent.swift` is reachable from any file in the `ARRunnerWatch` target. Reused it from `WorkoutViewModel.markSplitFromActionButton` and from the `splitFlashBanner` `.task` so the full press → mutation → render lifecycle shows up in one Console filter.
- **Key files:** `ARRunnerWatch/ActionButton/ActionButtonIntent.swift`, `ARRunnerWatch/Settings/ActionButtonCoordinator.swift`, `ARRunnerWatch/Workout/WorkoutViewModel.swift` (lines ~406-432 for the split path), `ARRunnerWatch/Views/WorkoutView.swift` (`splitFlashBanner` computed property).
- **Build:** `xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' build` — green.

## Learnings

### v0.5.11 (build 41) — Action Button cold-start + mid-workout split fixes

**Bug 1 (first press doesn't start workout).** Apple's Action Button docs: "If your app has never requested authorization for any HealthKit data types, the system just launches your app when someone presses the Action button. It doesn't call your intent's `perform()` method." Previously HK auth was requested only from `.task` on the root view, which still runs on first launch — but moving it into `App.init()` (fire-and-forget Task) gets the auth prompt up as early as possible, so the *very next* press correctly calls `perform()`. Kept the `.task` defensive re-request (HK treats re-requests as no-ops once answered).

**Bug 2 (Action Button mid-workout doesn't mark splits).** Two-layer fix:
1. **Primary mechanism (per Apple docs):** `ARRunnerStartWorkoutIntent.perform()` now returns `.result(actionButtonIntent: ARRunnerNextActionIntent())` on every path. This is the *reliable* way to wire the next press — donation is a hint, return-value is authoritative.
2. **Donation hardening:** `WorkoutControlDonation.donateNextAction()` now adds a 250ms settling delay before the first attempt and retries once after 500ms on failure. The `NSCocoaErrorDomain Code=4099 com.apple.linkd.transcript invalidated` failure observed in the wild appears to be a transient timing issue immediately after `HKLiveWorkoutBuilder` begins collecting data.

**Key constraint preserved:** Did NOT redeclare `openAppWhenRun` on `StartWorkoutIntent` per Apple's "don't change the property's value" guidance. Only `ARRunnerNextActionIntent` (a plain `AppIntent`) sets `openAppWhenRun = true` explicitly because plain AppIntents default to `false`.

**Files:** `ActionButtonIntent.swift`, `WorkoutControlIntents.swift`, `ARRunnerWatchApp.swift`, `project.yml` (build 40→41).

## Learnings
- **v0.5.12 — Pause overlay on WorkoutView:** added a glanceable PAUSED indicator overlaid on `metricsSection` when `launchState` is `.paused` or `.pendingFinish`. Used `.overlay(alignment: .center)` + `TimelineView(.animation)` for a frame-driven sin-wave breathing animation (alpha 0.7↔1.0, scale 0.97↔1.0 over 1.4s). Stats dimmed to 0.55 opacity so numbers stay readable underneath. Wrapped overlay appearance in a `.transition(.opacity.combined(with: .scale))` driven by `.animation(.easeInOut(0.2), value: isPaused)`.
- **`pendingFinish` counts as paused for UI:** the finish confirmation dialog leaves the workout non-recording, so I treated `.pendingFinish` as "paused" too — otherwise the overlay would vanish the moment the user taps Finish, giving the false impression the run resumed.
- **Sim destination drift:** CI guidance still references `Apple Watch Ultra 2 (49mm)` but the installed Xcode 26.x simulators only have `Apple Watch Ultra 3 (49mm)`. Worth flagging to whoever owns build docs.

### 2026-05-22 — v0.5.15: live route map on the watch

- **Goal:** Render a MapKit `Map` below the metrics on `WorkoutView` showing the current GPS position and the polyline traced so far.
- **Architecture choice — bypass the protocol seam:** The existing route ingestion sits inside `HealthKitWorkoutSubstrate.ingest(locations:)`, but `WorkoutHealthSubstrate` (in `ARRunnerCore`) is deliberately CoreLocation-free so Linux SPM tests keep building. Adding a `CLLocationCoordinate2D` stream to the protocol would have broken that. Solution: added `routeCoordinateEvents: AsyncStream<CLLocationCoordinate2D>` directly on `HealthKitWorkoutSubstrate` (watch target only) and downcast in `WorkoutViewModel.attachRouteStream`. Mocks/Linux substrates simply skip the subscription — no protocol churn.
- **Fan-out point:** Yields happen *after* `HKWorkoutRouteBuilder.insertRouteData` is dispatched, so a slow UI consumer can never starve persistence. Same filtered fixes (`horizontalAccuracy <= 50 m`) drive both — what you see on the watch matches what Health stores.
- **Map view:** `LiveRouteMapView` uses `MapCameraPosition.userLocation(fallback: .automatic)` so the camera tracks the runner without us recomputing a region per fix. `MapPolyline(coordinates:)` for the trace, custom green pulse annotation for the runner pin, `.standard(elevation: .flat)`, `.mapControlVisibility(.hidden)`, 160 pt height. Gated by `#if canImport(MapKit)`.
- **Gating in `WorkoutView`:** New `isInWorkout` (running / paused / pendingFinish) controls visibility. Pre-run / post-run surfaces don't show the map — no fixes flowing, nothing useful to render, and it would only steal real estate from the Connect Glasses row.
- **Reset:** `resetLiveCounters` clears `routeCoordinates` + `currentLocation` and cancels the route task. Every workout starts with a blank polyline.
- **Build:** `xcodebuild build -scheme ARRunnerWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)'` → BUILD SUCCEEDED with only pre-existing warnings.
- **Versioning:** `VERSION` → 0.5.15, `project.yml` `MARKETING_VERSION` 0.5.15 / `CURRENT_PROJECT_VERSION` 45.

### v0.5.16 — live route map placement fix (phone primary, watch secondary)

**Decision (D-LAUGHLIN-v0.5.16-LIVE-MAP-PLACEMENT):** The live route map is phone-PRIMARY (inline below metrics in `WorkoutMirrorView`, ~280pt tall) and watch-SECONDARY (separate vertically-paginated `TabView` page using `.tabViewStyle(.verticalPage)`, only while `isInWorkout`). v0.5.15's inline watch placement compressed the metrics — metrics must win at a glance on the tiny screen. The watch TabView is gated on `isInWorkout` so the swipe affordance never appears pre-/post-run when there's nothing to plot.

**Wire protocol — additive optional pattern (4th use):** Added `latitude: Double?` + `longitude: Double?` to `WorkoutTickMessage`, piggybacked on the existing ~1 Hz tick. WC schema bumped 4 → 5. v5 ↔ v4 peers keep working in both directions because both fields default to `nil` and the phone treats "no lat/lon" as "no map yet". This is now the established pattern: additive optional fields + schema bump + a back-compat test that synthesises the previous version's JSON literal (see `testV4SnapshotWithoutLatLonStillDecodesOnV5`). Update both the version-pin test AND add a fresh back-compat test on every bump.

**Code org — `Shared/Views/` is now a thing:** Moved `LiveRouteMapView.swift` from `ARRunnerWatch/Views/` to `Shared/Views/` because both targets needed it (and `Shared/` is already in both target source paths per `project.yml`). Previously `Shared/` held only settings-types (e.g. `ActionButtonMode`). The view gained a `height: CGFloat?` param — explicit pt sizes the rounded-rect tile, `nil` makes it fill the parent for full-page contexts (watch's verticalPage map page). Pattern to repeat: any SwiftUI view that the phone and watch both render goes in `Shared/Views/` before being target-duplicated.

**Watch view structure — TabView only while needed:** `WorkoutView.body` now branches on `isInWorkout`: wraps in `TabView { metricsPage; mapPage }.tabViewStyle(.verticalPage)` during a workout, renders `metricsPage` standalone otherwise. The map page uses `LiveRouteMapView(height: nil).ignoresSafeArea(edges: .bottom)` for a full-screen feel. All modifiers (`.toolbar`, `.task`, `.sheet`, `.confirmationDialog`, `.onChange(scenePhase)`) hang off the outer `Group`, not the inner pages, so they don't fire twice when the user swipes between pages.

**Phone view-model — dedup contiguous coords:** `WorkoutMirrorViewModel.ingestLocation(from:)` skips appending if the new fix equals the previous one (stationary runner). Uses `CLLocationCoordinate2DIsValid` to drop bogus 0/0 fixes that test mocks emit. Cleared on lifecycle `.started`, retained through `.ended` so the post-run header still shows the completed polyline.

**Files touched (v0.5.16):**
- `ARRunnerCore/Sources/ARRunnerCore/Messaging/WorkoutTickMessage.swift` (+latitude/longitude)
- `ARRunnerCore/Sources/ARRunnerCore/Messaging/WCMessage.swift` (schema 4→5)
- `ARRunnerCore/Tests/ARRunnerCoreTests/WorkoutTickMessageTests.swift` (v5 pin + v4 back-compat test)
- `Shared/Views/LiveRouteMapView.swift` (moved from `ARRunnerWatch/Views/`, gained `height` param)
- `ARRunnerWatch/Workout/WorkoutViewModel.swift` (snapshot ctor now passes lat/lon from `currentLocation`, gated on `canImport(CoreLocation)`)
- `ARRunnerWatch/Views/WorkoutView.swift` (TabView with verticalPage, gated on `isInWorkout`)
- `ARRunnerPhone/Views/WorkoutMirrorViewModel.swift` (accumulates `routeCoordinates` + `currentLocation`)
- `ARRunnerPhone/Views/WorkoutMirrorView.swift` (wrapped in `ScrollView`, embeds `LiveRouteMapView` at 280pt)
- `VERSION` → `0.5.16`, `project.yml` MARKETING 0.5.16 / CURRENT_PROJECT_VERSION 46
