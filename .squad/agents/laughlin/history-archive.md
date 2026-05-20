# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings

### 2026-05-14 — watchOS Architecture Plan Complete
- **Task:** Produce comprehensive watchOS architecture for integrated watch + phone AR fitness app.
- **Key decisions:** 
  - Watch is **primary** for HKWorkoutSession; phone is config authority (glasses layout).
  - Launch surfaces: Smart Stack + Action Button + Siri + Complications (intent-based, no app foregrounding for v1).
  - WatchConnectivity contract defined: live metrics push (10–15s), glasses config push (pre-workout), summary push (post-workout).
  - **Blocked decision:** BLE ownership (watch vs. phone relay) pending Weiss's ActiveLook performance data.
  - **Blocker:** Action Button `openAppWhenRun = false` support requires integration testing; plan fallback to app launch.
- **Architecture shape:** Single watchOS target + iOS companion; HealthKit writer on watch; WC sender/receiver on both.
- **Next:** Await Joe's decision point responses (§ 6, decisions.md/inbox). Coordinate with Weiss on BLE. Then start Swift scaffolding.

### 2026-05-14: Team update from Joe — 9 architecture decisions locked (see decisions.md D1-D9). Next phase: Xcode scaffolding (Laughlin) + ActiveLook watchOS BLE spike (Weiss).

### 2026-05-14 — v0.1 workspace scaffolding landed
- Added `project.yml` with a modern single-target watchOS app (`ARRunnerWatch`), an iOS companion app (`ARRunnerPhone`), and one multi-destination WidgetKit extension (`ARRunnerWidgets`).
- Scaffolded `ARRunnerCore/Package.swift` plus shared files under `ARRunnerCore/Sources/ARRunnerCore/` for sport-agnostic models, versioned WatchConnectivity messages, and the AR side-store contract.
- Stubbed watch target files in `ARRunnerWatch/Views/`, `ARRunnerWatch/Workout/`, `ARRunnerWatch/Glasses/`, and `ARRunnerWatch/Sync/` with Swift 6-safe actors and `@MainActor` UI entry points.
- Stubbed phone shell files in `ARRunnerPhone/Views/` and `ARRunnerPhone/Sync/`, plus widget launch surfaces in `ARRunnerWidgets/StartWorkoutWidget.swift` and `ARRunnerWidgets/StartWorkoutIntent.swift`.
- Chose a single watch app target without a separate WatchKit extension for the 2026-era scaffold, and embedded the foreground launch App Intent in the widget extension instead of creating a standalone `ARRunnerAppIntents` target.

### 2026-05-14: Team update from Joe — v0.1 foundation scaffold + BLE spike landed on feat/v01-foundation. Branch awaiting Joe's push & PR. Next: WorkoutController impl (Laughlin) + watchOS BLE wrapper impl (Weiss).

### 2026-05-14T20:48:00Z: Scribe — macOS Build Validation Landed; Rebase Advisory

**From:** Scribe (session orchestration)

Amber's smoke test validates the v0.1 scaffold on macOS. All tests pass, all targets build, zero concurrency warnings. Three surgical fixes applied and merged into `chore/macos-build-validation` (commit ecb8179, pushed).

**Action for Laughlin:** Rebase your WorkoutController implementation off `chore/macos-build-validation` OR await PR #2 merge to main (Joe filing manually). The fixes include watchOS target type correction (application.watchapp2 → application + WKApplication) and widget extension split per-platform — both relevant to your workout lifecycle scaffolding.

**Reference:** decisions.md now includes Amber's full findings + the three fixes. See `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md` for operational summary.

### 2026-05-14T21:00:00Z: Scribe — CI Workflows Landed on chore/ci-workflows

**From:** Scribe (session orchestration)

Richards completed CI architecture design + implementation. Three workflows now committed to `.github/workflows/`:

1. **`ci-core-tests.yml`** — Linux runner. Tests `ARRunnerCore` with `swift test` on `swift:6.0-jammy` container.
2. **`ci-build.yml`** — macOS runner. Builds all four app targets (Watch, Phone, WidgetsPhone, WidgetsWatch) via xcodebuild 4-way matrix.
3. **`codeql.yml`** — GitHub CodeQL security analysis (PR + weekly).

**Critical for Laughlin:** Your WorkoutController implementation lives in ARRunnerWatch (watch app target), sharing models + protocols through ARRunnerCore. Linux ci-core-tests job validates that ARRunnerCore stays platform-agnostic (Foundation + XCTest only, no HealthKit/WatchKit/WCSession imports into Core). Keep concrete HealthKit + WatchConnectivity code in ARRunnerWatch, not Core. The architecture enforcement is now mechanical.

**Timeline:** PR #3 (chore/ci-workflows) queued behind PR #2 (macos-build-validation). Joe will open both manually. When merged, all subsequent feature branches auto-validate.

**For your WorkoutController implementation:** Your PR must pass ci-core-tests (Linux), all ci-build matrix jobs (macOS 4 targets), and CodeQL. Plan ~15 minutes of CI time per PR after cache warm-up. Local validation matches CI 1:1 — see docs/dev/ci-workflows.md for repro steps.

**Reference:** `.squad/orchestration-log/2026-05-14T21:00:00Z-richards.md` for full ADRs and design rationale.

### 2026-05-14T21:12:00Z: Scribe — CI Swift 6.0 Toolchain Gotcha (Richards fix landed)

**From:** Scribe (session orchestration)

PR #3 (chore/ci-workflows) first real CI run caught hard error:
> error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6

**Root cause:** Your original scaffold included explicit `.enableUpcomingFeature("StrictConcurrency")` in `ARRunnerCore/Package.swift`. This is redundant and breaks on Swift 6.0 CI (treats as hard error). Local Swift 6.3.2 silently tolerated it.

**Fix applied (350eae0):** Removed the explicit flag. Swift 6 language mode (`swift-tools-version: 6.0` + `.swiftLanguageMode(.v6)`) is the single source of truth.

**Lesson:** Local development toolchains run ahead of CI. Flags that work locally can hard-fail CI. When copying Apple/third-party examples (especially ActiveLook), **strip `.enableUpcomingFeature("StrictConcurrency")` lines on import** — it's a CI-breaker even if local builds pass.

**Action:** No change needed to your WorkoutController—your code will inherit the fixed package settings. Just remember this toolchain gap for future WorkoutController PRs.

### 2026-05-14T21:26:21Z: Scribe — watchOS Simulator Runtime Missing on macOS CI

**From:** Scribe (session orchestration)

Richards's second fix (commit 079cb73, chore/ci-workflows) resolved ARRunnerWatch build failures. **Root cause:** macOS-latest CI runners ship Xcode 16 with watchOS 11 SDK but **not** the simulator runtime.

**Why:** iOS (and other commonly-tested platform) simulator runtimes are bundled in the Xcode package. watchOS simulator runtime is downloaded separately via `xcodebuild -downloadPlatform watchOS`.

**Key insight for your WorkoutController:** App schemes (ARRunnerWatch) trigger destination resolution during build, which probes for the simulator runtime and fails if missing. **Non-app schemes don't trigger this probe** — that's why the widget target (non-app) passed while the watch target failed on the same runner.

**Fix applied:** Conditional download step gated on matrix cell. Only watchOS matrix cells run `sudo xcodebuild -downloadPlatform watchOS`; iOS stays fast.

**For your implementation:** Your WorkoutController runs in ARRunnerWatch (app target). When you test on CI, expect this runtime download step to run automatically. On your local macOS machine, you likely have the watchOS simulator runtime already cached — this is why it worked locally but failed CI first time.

**Reference:** `.squad/orchestration-log/2026-05-14T21:26:21Z-richards.md` for full details.

### 2026-05-15T14:33:20-04:00 — v0.2 #2 + #3 — Watch SwiftUI app + iPhone live mirror

**Branch:** `feat/v02-watch-ui-and-mirror-laughlin` (suffix because another agent was racing me on the unsuffixed name; same lesson Weiss documented).

**Outcome:** PR opened, all four app targets build clean (watchOS + iOS + both widget extensions), Core tests 55/55 green.

**Workstream #2 — Watch SwiftUI workout app:**
- `WorkoutViewModel.LaunchState` grew `.pendingFinish` and `.cancelled` to model decision #5 (Finish menu pauses, presents Save / Discard / Resume).
- `requestFinish()` pauses the controller and parks it in `.pendingFinish`. The `confirmationDialog` Bool binding auto-resumes the run if the user dismisses without choosing — a stray tap-out can't strand the workout in pendingFinish.
- Hybrid energy (decision #4): pure-Swift `EnergyEstimator` + `EnergyAccumulator` in Core integrate HR samples by elapsed time (Keytel 2005 formula). Watch view model holds an `EnergyAccumulator`, ingests HR samples from the existing metric stream, and publishes `estimatedActiveKilocalories` for the HUD. After Save, the HealthKit-official `WorkoutSummary.totalActiveEnergyKilocalories` overrides the estimate in the post-run footer.
- "Discard" caveat: the canonical `WorkoutHealthSubstrate` protocol does not expose a HK-level discard path in v0.2 (and was off-limits per the brief). Discard ends the controller normally — the HKWorkout still writes — and just suppresses the on-device summary. The view-model `.cancelled` state surfaces a "Run discarded" hint; users can delete the workout from the Health app. Worth re-litigating in v0.3 alongside the iPhone settings UI.

**Workstream #3 — iPhone live mirror:**
- New shared `WorkoutTickMessage` payload in Core. Bumped `WCMessage.currentSchemaVersion` from 1 → 2 with backward-decoding for v1 envelopes (older watch builds keep working against the v0.2 phone mirror).
- Watch publishes a tick every 1 s while phase ∈ {running, paused, pendingFinish}. Best-effort: silent drop if the phone is unreachable. Reachability-aware delivery — `sendMessageData` when reachable, `updateApplicationContext` for live-tick latest-only fallback, `transferUserInfo` for queued lifecycle transitions.
- iPhone `WorkoutMirrorViewModel` republishes the latest snapshot. `Status` enum models `.idle` / `.live` / `.stale(since:)` / `.ended` so the dashboard can dim/annotate when ticks dry up. 8 s stale threshold; pure visual signal — no retries, no nags.
- New `WorkoutMirrorView` replaces the placeholder `Live` tab. Single screen, no controls, no settings (decision #3 keeps phone read-only).

**Watch-first guarantee (decision #3):** the view-model's `mirror` parameter is optional. If WCSession is unsupported / unactivated / unreachable, every send silently drops. The watch records, saves, and renders identically with no phone present. Verified by reading the code path — every WC call is best-effort.

**SwiftUI-on-watchOS gotchas:**
1. `confirmationDialog` needs a `Bool` binding; presenting based on a `LaunchState` case requires a derived binding. Setter must handle the dismiss-without-choice case (we route it to `resumeFromFinish`).
2. `Task { … }` closures inside a `@MainActor @Observable` view-model inherit MainActor isolation by default — calling sync MainActor-isolated methods from inside that Task does NOT need `await`, and the compiler warns if you add it ("no async operations occur within 'await' expression"). Drop the await; do NOT change isolation.
3. SwiftUI macro-generated `@Observable` classes interplay fine with `@State private var viewModel = ViewModel(...)` default initializers — the default expression runs in the enclosing `@MainActor` view's init context.

**WCSession patterns (Swift 6 strict-concurrency edition):**
- `WCSessionDelegate` conformance triggers MainActor-isolation inference in iOS 18 / watchOS 11 SDKs in subtle ways. The cleanest pattern is `final class : NSObject, @unchecked Sendable` (no `@MainActor`) with delegate methods declared without isolation modifiers — they get nonisolated treatment via `@unchecked`. The `ARRunner*Environment` singletons are `@MainActor` and call `service.activate()` once at app launch; everything else stays off the main actor.
- For live-tick publishing prefer the three-tier pattern: `sendMessageData` (reachable, low-latency), `updateApplicationContext` (background, latest-wins), `transferUserInfo` (queued, durable). The watch `transmit(_:preferLatestOnly:preferQueued:)` helper picks based on the message type — live tick → latest-only; lifecycle event → queued; other → queued.
- `AsyncStream` is the right shape for the inbound side. The phone receiver's `incomingMessages` stream is bridged into a MainActor view-model; subscribers see future messages only, no replay.

**Hybrid energy approach:**
- `EnergyEstimator` is pure Foundation in Core so it builds on Linux SPM (the existing `ARRunnerCoreTests` Linux job validates it). Sex switch defaults `.unspecified` to the male/female average so we never lose the estimate when the user hasn't shared sex.
- `maxSampleGapSeconds` clamp prevents long pauses from inflating the estimate when the watch resumes sampling. Tested with a 5-min gap → bounded to the 10-s clamp.
- `BodyProfile` lives in Core too. Watch reads body mass + age + sex from HealthKit at workout start; if any field is missing, the view-model just doesn't construct an `EnergyAccumulator` and the live kcal row reads "—".

**Menu-on-finish pattern:**
- The Finish menu is a `confirmationDialog` driven by `launchState == .pendingFinish`. Dialog actions invoke async view-model methods via `Task { await … }`. The Resume button has `role: .cancel` so dragging down on the watch does the right thing.
- Two-phase commit: Finish → pause + show menu (controller still alive) → Save / Discard ends controller. Resume just calls `controller.resume()`. This means the user can Finish, change their mind, Resume, and continue the same `WorkoutController` — no new HK session, no lost samples.

### 2026-05-15T16:49:00-04:00 — v0.2 #4 — Watch-side D4 UX (haptic + HUD-offline)

**Branch / PR:** `feat/v02-d4-watch-ux` → PR #13.

**Outcome:** Both CI legs green (Linux SPM 66 pass / 3 skip; macOS watchOS app build succeeded). Surgical: 2 watch files + 1 test message update, no canonical surface touched.

**watchOS haptic patterns:**
- `WKInterfaceDevice.current().play(.notification)` is the right "subtle but noticed" call for HUD-drop alerts. `.failure` is too alarming for a non-failure event (the workout keeps running fine without HUD); `.directionUp/Down` exist on watchOS 7+ but are intended for navigation cues, not status.
- Wrap the `WKInterfaceDevice` call behind a `@Sendable () -> Void` closure with an `#if canImport(WatchKit) && os(watchOS)` default. Lets the view-model stay testable on Linux (via stub closure) AND keeps the production call zero-overhead. Initializer takes an optional `hapticPlayer` so tests inject a counter; production code uses the default.

**Glasses-status observation pattern:**
- The transport exposes TWO complementary streams: `connectionStates()` (full lifecycle: scanning/connecting/connected/reconnecting/...) and `statusEvents()` (side-channel: `.dropped(reason:at:)`, `.reconnected(gap:at:)`, battery, RSSI). For UX hooks (haptic, banner) read `statusEvents()` — drop reasons are richer and `.reconnected` is unambiguous. For controller-side state mirroring, keep using `connectionStates()` → `GlassesConnectivitySignal.from(_:)` (already wired in v0.2 #2).
- A single MainActor handler `handle(statusEvent:)` switches on cases. Keeping the switch exhaustive makes future side-channel events (battery low, signal weak) easy to add without touching the subscriber loop.

**Debouncing approach:**
- `private var lastHapticAt: Date?` + a 10s constant. Check elapsed in MainActor method; suppress if too recent.
- **Reset on `.reconnected`** so a new outage after recovery alerts immediately. Without reset, a fast disconnect → reconnect → disconnect cycle would silently swallow the second alert.
- Inject `now: @Sendable () -> Date` so deterministic tests can control the clock.
- **Phase gate:** only fire when `launchState == .running`. Drops while `.idle`, `.paused`, `.pendingFinish`, `.ending`, `.ended`, `.cancelled`, or `.failed` are still surfaced visually but never haptic. Decision #5's pause-on-Finish flow stays haptic-quiet — the user is making a UI choice, not running.

**SwiftUI banner pattern:**
- Conditional `@ViewBuilder` (`if viewModel.hudOffline { Label(...) }`) inside the root `VStack`. `.transition(.opacity)` keeps it from popping. Orange `.foregroundStyle` reads as "warning, not error" — matches the D4 "keep recording" intent. SF Symbol `eyeglasses.slash` is the right glyph (not `wifi.slash` — that's network-coded).

**Test-gate decision:**
- The `test_HapticAlertHook_OnDisconnect_ExpectedFailing` skip pinned a `controller.alerts AsyncStream` contract. v0.2 #4 chose to ship haptics directly off `transport.statusEvents()` instead of adding a Core-level alerts stream — the canonical surface stays narrower. The 1:1 outage-to-haptic contract is already covered by `test_Disconnect_EmitsDroppedExactlyOnce`. Updated the skip message to document the deferral so the next reader doesn't spend time hunting a missing implementation.

**Coordination with Weiss:**
- He's working `RunningHUDPreset` + BLE auto-reconnect in parallel. No file overlap (his work is `ARRunnerCore/Glasses/` adapters; mine is `ARRunnerWatch/`). Worktrees made this trivial — he flips the two BLE-owned skip gates when his loop lands.

---

### 2026-05-15 — WidgetKit Info.plist constraints (PR #17, fix/watch-widgets-extension-keys)

**The bug:** `xcodebuild build` succeeded for `ARRunnerWatch`, but `simctl install` (and SwiftUI Preview host install) failed with "Appex bundle ... defines either an NSExtensionMainStoryboard or NSExtensionPrincipalClass key, which is not allowed for the extension point com.apple.widgetkit-extension". Both `ARRunnerWidgetsWatch` and `ARRunnerWidgetsPhone` had the same misconfig in `project.yml`.

**WidgetKit Info.plist constraint:**
- For extension point `com.apple.widgetkit-extension`, the `NSExtension` dict MUST contain only `NSExtensionPointIdentifier`. `NSExtensionMainStoryboard` and `NSExtensionPrincipalClass` are forbidden — the runtime entry point is the Swift `@main WidgetBundle` type, not a plist-declared principal class. Specifying a principal class in the plist conflicts with `@main` resolution and the install-time validator rejects it.
- The `$(PRODUCT_MODULE_NAME).WidgetBundle` style of `NSExtensionPrincipalClass` is a holdover from pre-WidgetKit `NSExtension`-style extensions (Today widgets, share extensions, etc.). When converting/scaffolding a WidgetKit target, those keys must be stripped.

**xcodebuild-vs-install validation gap:**
- `xcodebuild build` only validates code compilation, code signing, and basic bundle structure. It does NOT validate extension-point-specific Info.plist constraints (allowed/forbidden keys per extension point).
- `simctl install` runs the device-side installer (`installd` / `IXUserPresentableErrorDomain`), which DOES enforce these constraints. SwiftUI Preview host install hits the same path — that's why Joe saw it from the Preview, not from a plain build.
- **Implication:** CI that only runs `xcodebuild build` cannot catch this class of bug. Two CI legs were green while the local install was broken.

**Rule for future PRs touching extension targets in `project.yml`:**
- After any change to an extension target's Info.plist (inline `info.properties` in `project.yml` or an explicit Info.plist file), run a `simctl install` smoke test on the resulting `.app` before pushing. Build success is necessary but not sufficient.
- Quickest verification: `/usr/libexec/PlistBuddy -c "Print :NSExtension" path/to/Foo.appex/Info.plist` — eyeball that only the keys allowed by the extension point's contract are present.

**XcodeGen layout for this repo (worth recording):**
- Widget targets use inline `info.properties` in `project.yml` (NOT a checked-in Info.plist file). XcodeGen synthesizes the plist into `Config/ARRunnerWidgets{Phone,Watch}-Info.plist` at generate time. So the source of truth for plist content is `project.yml`, not any file on disk.
- `xcodegen generate` is required after any `project.yml` edit; the `.xcodeproj` is gitignored.

**Out-of-scope finding (separate issue, not fixed in this PR):**
- After the WidgetKit fix, `simctl install` surfaced a *different* error: "This app's bundle identifier does not start with its parent app's bundle identifier ... WKCompanionAppBundleIdentifier=com.arrunner.phone vs watch app bundle id=com.arrunner.watch". Pre-existing companion-bundle-id mismatch. Documented in PR body so it doesn't get lost; needs a follow-up (likely set watch bundle id to `com.arrunner.phone.watchkitapp` or similar to satisfy the prefix rule).

---

### 2026-05-15T18:15:00-04:00 — PR #18: WKCompanion bundle-ID prefix rename

Followed up on the out-of-scope finding from PR #16/#17. Renamed watch + watch-widget bundle IDs so the watch app's `CFBundleIdentifier` is a strict dotted-prefix descendant of the phone app's:

- `ARRunnerWatch`:        `com.arrunner.watch` → `com.arrunner.phone.watchkitapp`
- `ARRunnerWidgetsWatch`: `com.arrunner.watch.widgets` → `com.arrunner.phone.watchkitapp.widgets`
- Phone + phone-widgets unchanged (already prefix-compliant: `com.arrunner.phone` / `com.arrunner.phone.widgets`).
- `WKCompanionAppBundleIdentifier` already pointed at `com.arrunner.phone` — kept as-is.

**Learnings:**

- **Apple's WKCompanion prefix rule (hard).** A watchOS app's `CFBundleIdentifier` must be a strict dotted-prefix descendant of the iPhone host app's `CFBundleIdentifier` declared in `WKCompanionAppBundleIdentifier`. `com.arrunner.watch` is *not* a descendant of `com.arrunner.phone` regardless of how "obvious" the naming feels. The convention Apple's own templates use is `<phone-id>.watchkitapp`. The same prefix rule cascades to embedded `.appex` plugins — `ARRunnerWidgetsWatch` had to become `com.arrunner.phone.watchkitapp.widgets`, not just `com.arrunner.phone.widgets` (which would belong to the phone app, not the watch).
- **The error doesn't appear at build time, only at install time.** `xcodebuild` is happy to produce an .app with a non-compliant companion ID. `xcrun simctl install` is the first thing to reject it. SwiftUI Previews fail silently for the same reason. So "build succeeded" is not a sufficient bar for watch-target work — always do at least one `simctl install` per PR that touches watch bundle config.
- **Audit insight: functional bundle IDs live in exactly one place.** Because Info.plist values are inlined into `project.yml` (no separate `Config/*.plist` files in this repo) and the entitlements files only reference the `group.com.arrunner.shared` app group (which is its own identifier, unrelated to bundle IDs), `project.yml` is the *only* file that carries functional bundle-ID strings. Logger subsystem labels (`Logger(subsystem: "com.arrunner.watch", ...)`) and `DispatchQueue` labels look bundle-ID-shaped by convention but are free-form strings — changing them risks breaking log filters and is out of scope for a bundle-ID rename. Leave them.
- **Layout decision (locked in):** root = `com.arrunner.phone`; everything watch-side sits under `com.arrunner.phone.watchkitapp.*`. If we ever add a phone-side extension (Share/Notification/etc.), it goes under `com.arrunner.phone.*` directly. App group ID (`group.com.arrunner.shared`) is independent of bundle IDs and does not need to follow the prefix rule.
- **Verification recipe for any future bundle-ID change:** (1) `xcodegen generate`; (2) build both schemes against sims; (3) `xcrun simctl install <watch-sim-UDID> <built.app>` — if this exits 0 with no stderr, the companion prefix rule is satisfied; (4) `swift test` from `ARRunnerCore/` to catch any test that hardcoded an ID. Step 3 is the actual signal; steps 1, 2, 4 will pass even when the IDs are wrong.

### 2026-05-15 — v0.2 runtime fixes: HK Error(7), nav title overlap, UIScene manifest
- **HK Error(7) root cause:** `HealthKitWorkoutSubstrate.begin(...)` called `session.startActivity` and `builder.beginCollection` without ever invoking `HKHealthStore.requestAuthorization`. The substrate's docstring delegated auth to "the caller", but no caller ever did. `HKLiveWorkoutBuilder` reacts to pre-flight failure (missing entitlement / usage-string / un-granted auth) by entering the terminal `Error(7)` state with `Allowed transitions = {}` — every subsequent transition is rejected. Fix: added `HealthKitWorkoutSubstrate.requestAuthorization(healthStore:)` (static), call it from `ARRunnerWatchApp` as a `.task` on the WindowGroup root so the system prompt fires on first launch, and call it again defensively from `begin(...)` (a re-request after grant is a no-op, but it guarantees no race vs. the first Start Run tap).
- **project.yml entitlement layout:** the watch target already had `com.apple.developer.healthkit: true` under `entitlements.properties` and `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` under `info.properties`. Entitlement + usage strings alone are necessary but not sufficient — the app **must** actually call `requestAuthorization` before `beginCollection`, otherwise HealthKit acts as if it were unauthorized.
- **Auth type set:** for a workout substrate that writes `HKWorkout` and reads HR / distance / energy stats live from `HKLiveWorkoutBuilder`, share = `{workoutType, heartRate, distanceWalkingRunning, distanceCycling, activeEnergyBurned}`, read = same set (workout objects + per-sample types).
- **watchOS nav title overlap fix:** `.navigationTitle("Run")` on a plain `VStack` whose contents exceed the available height causes the watchOS large title to render over the top row of metrics. Wrapping the body in a `ScrollView` and using `.padding(.horizontal)` / `.padding(.bottom)` (no `.padding()` on the whole VStack) places the metrics below the title bar correctly and lets the user scroll to the footer. Do not reach for `.navigationBarTitleDisplayMode` — that modifier is iOS-only and not available on watchOS.
- **UIScene manifest for SwiftUI App lifecycle (iOS):** even with pure `@main struct ARRunnerPhoneApp: App` (no `SceneDelegate`), iOS 17+ still logs `Info.plist contained no UIScene configuration dictionary` unless the manifest declares at least one entry under `UISceneConfigurations.UIWindowSceneSessionRoleApplication`. A minimal entry with just `UISceneConfigurationName: Default Configuration` (no `UISceneDelegateClassName`) is enough — SwiftUI substitutes its own scene delegate. In `project.yml` this is a nested dict under the iPhone target's `info.properties.UIApplicationSceneManifest`.
- **Build verification:** `xcodebuild` clean for both `ARRunnerWatch` (watchOS Sim 11 46mm) and `ARRunnerPhone` (generic iOS Sim). `swift test` from `ARRunnerCore/` → 78 passed, 1 skipped, 0 failed. `simctl install` onto the watch sim succeeds with the updated entitlements.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings

### 2026-05-14 — watchOS Architecture Plan Complete
- **Task:** Produce comprehensive watchOS architecture for integrated watch + phone AR fitness app.
- **Key decisions:** 
  - Watch is **primary** for HKWorkoutSession; phone is config authority (glasses layout).
  - Launch surfaces: Smart Stack + Action Button + Siri + Complications (intent-based, no app foregrounding for v1).
  - WatchConnectivity contract defined: live metrics push (10–15s), glasses config push (pre-workout), summary push (post-workout).
  - **Blocked decision:** BLE ownership (watch vs. phone relay) pending Weiss's ActiveLook performance data.
  - **Blocker:** Action Button `openAppWhenRun = false` support requires integration testing; plan fallback to app launch.
- **Architecture shape:** Single watchOS target + iOS companion; HealthKit writer on watch; WC sender/receiver on both.
- **Next:** Await Joe's decision point responses (§ 6, decisions.md/inbox). Coordinate with Weiss on BLE. Then start Swift scaffolding.

### 2026-05-14: Team update from Joe — 9 architecture decisions locked (see decisions.md D1-D9). Next phase: Xcode scaffolding (Laughlin) + ActiveLook watchOS BLE spike (Weiss).

### 2026-05-14 — v0.1 workspace scaffolding landed
- Added `project.yml` with a modern single-target watchOS app (`ARRunnerWatch`), an iOS companion app (`ARRunnerPhone`), and one multi-destination WidgetKit extension (`ARRunnerWidgets`).
- Scaffolded `ARRunnerCore/Package.swift` plus shared files under `ARRunnerCore/Sources/ARRunnerCore/` for sport-agnostic models, versioned WatchConnectivity messages, and the AR side-store contract.
- Stubbed watch target files in `ARRunnerWatch/Views/`, `ARRunnerWatch/Workout/`, `ARRunnerWatch/Glasses/`, and `ARRunnerWatch/Sync/` with Swift 6-safe actors and `@MainActor` UI entry points.
- Stubbed phone shell files in `ARRunnerPhone/Views/` and `ARRunnerPhone/Sync/`, plus widget launch surfaces in `ARRunnerWidgets/StartWorkoutWidget.swift` and `ARRunnerWidgets/StartWorkoutIntent.swift`.
- Chose a single watch app target without a separate WatchKit extension for the 2026-era scaffold, and embedded the foreground launch App Intent in the widget extension instead of creating a standalone `ARRunnerAppIntents` target.

### 2026-05-14: Team update from Joe — v0.1 foundation scaffold + BLE spike landed on feat/v01-foundation. Branch awaiting Joe's push & PR. Next: WorkoutController impl (Laughlin) + watchOS BLE wrapper impl (Weiss).

### 2026-05-14T20:48:00Z: Scribe — macOS Build Validation Landed; Rebase Advisory

**From:** Scribe (session orchestration)

Amber's smoke test validates the v0.1 scaffold on macOS. All tests pass, all targets build, zero concurrency warnings. Three surgical fixes applied and merged into `chore/macos-build-validation` (commit ecb8179, pushed).

**Action for Laughlin:** Rebase your WorkoutController implementation off `chore/macos-build-validation` OR await PR #2 merge to main (Joe filing manually). The fixes include watchOS target type correction (application.watchapp2 → application + WKApplication) and widget extension split per-platform — both relevant to your workout lifecycle scaffolding.

**Reference:** decisions.md now includes Amber's full findings + the three fixes. See `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md` for operational summary.

### 2026-05-14T21:00:00Z: Scribe — CI Workflows Landed on chore/ci-workflows

**From:** Scribe (session orchestration)

Richards completed CI architecture design + implementation. Three workflows now committed to `.github/workflows/`:

1. **`ci-core-tests.yml`** — Linux runner. Tests `ARRunnerCore` with `swift test` on `swift:6.0-jammy` container.
2. **`ci-build.yml`** — macOS runner. Builds all four app targets (Watch, Phone, WidgetsPhone, WidgetsWatch) via xcodebuild 4-way matrix.
3. **`codeql.yml`** — GitHub CodeQL security analysis (PR + weekly).

**Critical for Laughlin:** Your WorkoutController implementation lives in ARRunnerWatch (watch app target), sharing models + protocols through ARRunnerCore. Linux ci-core-tests job validates that ARRunnerCore stays platform-agnostic (Foundation + XCTest only, no HealthKit/WatchKit/WCSession imports into Core). Keep concrete HealthKit + WatchConnectivity code in ARRunnerWatch, not Core. The architecture enforcement is now mechanical.

**Timeline:** PR #3 (chore/ci-workflows) queued behind PR #2 (macos-build-validation). Joe will open both manually. When merged, all subsequent feature branches auto-validate.

**For your WorkoutController implementation:** Your PR must pass ci-core-tests (Linux), all ci-build matrix jobs (macOS 4 targets), and CodeQL. Plan ~15 minutes of CI time per PR after cache warm-up. Local validation matches CI 1:1 — see docs/dev/ci-workflows.md for repro steps.

**Reference:** `.squad/orchestration-log/2026-05-14T21:00:00Z-richards.md` for full ADRs and design rationale.

### 2026-05-14T21:12:00Z: Scribe — CI Swift 6.0 Toolchain Gotcha (Richards fix landed)

**From:** Scribe (session orchestration)

PR #3 (chore/ci-workflows) first real CI run caught hard error:
> error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6

**Root cause:** Your original scaffold included explicit `.enableUpcomingFeature("StrictConcurrency")` in `ARRunnerCore/Package.swift`. This is redundant and breaks on Swift 6.0 CI (treats as hard error). Local Swift 6.3.2 silently tolerated it.

**Fix applied (350eae0):** Removed the explicit flag. Swift 6 language mode (`swift-tools-version: 6.0` + `.swiftLanguageMode(.v6)`) is the single source of truth.

**Lesson:** Local development toolchains run ahead of CI. Flags that work locally can hard-fail CI. When copying Apple/third-party examples (especially ActiveLook), **strip `.enableUpcomingFeature("StrictConcurrency")` lines on import** — it's a CI-breaker even if local builds pass.

**Action:** No change needed to your WorkoutController—your code will inherit the fixed package settings. Just remember this toolchain gap for future WorkoutController PRs.

### 2026-05-14T21:26:21Z: Scribe — watchOS Simulator Runtime Missing on macOS CI

**From:** Scribe (session orchestration)

Richards's second fix (commit 079cb73, chore/ci-workflows) resolved ARRunnerWatch build failures. **Root cause:** macOS-latest CI runners ship Xcode 16 with watchOS 11 SDK but **not** the simulator runtime.

**Why:** iOS (and other commonly-tested platform) simulator runtimes are bundled in the Xcode package. watchOS simulator runtime is downloaded separately via `xcodebuild -downloadPlatform watchOS`.

**Key insight for your WorkoutController:** App schemes (ARRunnerWatch) trigger destination resolution during build, which probes for the simulator runtime and fails if missing. **Non-app schemes don't trigger this probe** — that's why the widget target (non-app) passed while the watch target failed on the same runner.

**Fix applied:** Conditional download step gated on matrix cell. Only watchOS matrix cells run `sudo xcodebuild -downloadPlatform watchOS`; iOS stays fast.

**For your implementation:** Your WorkoutController runs in ARRunnerWatch (app target). When you test on CI, expect this runtime download step to run automatically. On your local macOS machine, you likely have the watchOS simulator runtime already cached — this is why it worked locally but failed CI first time.

**Reference:** `.squad/orchestration-log/2026-05-14T21:26:21Z-richards.md` for full details.

### 2026-05-15T14:33:20-04:00 — v0.2 #2 + #3 — Watch SwiftUI app + iPhone live mirror

**Branch:** `feat/v02-watch-ui-and-mirror-laughlin` (suffix because another agent was racing me on the unsuffixed name; same lesson Weiss documented).

**Outcome:** PR opened, all four app targets build clean (watchOS + iOS + both widget extensions), Core tests 55/55 green.

**Workstream #2 — Watch SwiftUI workout app:**
- `WorkoutViewModel.LaunchState` grew `.pendingFinish` and `.cancelled` to model decision #5 (Finish menu pauses, presents Save / Discard / Resume).
- `requestFinish()` pauses the controller and parks it in `.pendingFinish`. The `confirmationDialog` Bool binding auto-resumes the run if the user dismisses without choosing — a stray tap-out can't strand the workout in pendingFinish.
- Hybrid energy (decision #4): pure-Swift `EnergyEstimator` + `EnergyAccumulator` in Core integrate HR samples by elapsed time (Keytel 2005 formula). Watch view model holds an `EnergyAccumulator`, ingests HR samples from the existing metric stream, and publishes `estimatedActiveKilocalories` for the HUD. After Save, the HealthKit-official `WorkoutSummary.totalActiveEnergyKilocalories` overrides the estimate in the post-run footer.
- "Discard" caveat: the canonical `WorkoutHealthSubstrate` protocol does not expose a HK-level discard path in v0.2 (and was off-limits per the brief). Discard ends the controller normally — the HKWorkout still writes — and just suppresses the on-device summary. The view-model `.cancelled` state surfaces a "Run discarded" hint; users can delete the workout from the Health app. Worth re-litigating in v0.3 alongside the iPhone settings UI.

**Workstream #3 — iPhone live mirror:**
- New shared `WorkoutTickMessage` payload in Core. Bumped `WCMessage.currentSchemaVersion` from 1 → 2 with backward-decoding for v1 envelopes (older watch builds keep working against the v0.2 phone mirror).
- Watch publishes a tick every 1 s while phase ∈ {running, paused, pendingFinish}. Best-effort: silent drop if the phone is unreachable. Reachability-aware delivery — `sendMessageData` when reachable, `updateApplicationContext` for live-tick latest-only fallback, `transferUserInfo` for queued lifecycle transitions.
- iPhone `WorkoutMirrorViewModel` republishes the latest snapshot. `Status` enum models `.idle` / `.live` / `.stale(since:)` / `.ended` so the dashboard can dim/annotate when ticks dry up. 8 s stale threshold; pure visual signal — no retries, no nags.
- New `WorkoutMirrorView` replaces the placeholder `Live` tab. Single screen, no controls, no settings (decision #3 keeps phone read-only).

**Watch-first guarantee (decision #3):** the view-model's `mirror` parameter is optional. If WCSession is unsupported / unactivated / unreachable, every send silently drops. The watch records, saves, and renders identically with no phone present. Verified by reading the code path — every WC call is best-effort.

**SwiftUI-on-watchOS gotchas:**
1. `confirmationDialog` needs a `Bool` binding; presenting based on a `LaunchState` case requires a derived binding. Setter must handle the dismiss-without-choice case (we route it to `resumeFromFinish`).
2. `Task { … }` closures inside a `@MainActor @Observable` view-model inherit MainActor isolation by default — calling sync MainActor-isolated methods from inside that Task does NOT need `await`, and the compiler warns if you add it ("no async operations occur within 'await' expression"). Drop the await; do NOT change isolation.
3. SwiftUI macro-generated `@Observable` classes interplay fine with `@State private var viewModel = ViewModel(...)` default initializers — the default expression runs in the enclosing `@MainActor` view's init context.

**WCSession patterns (Swift 6 strict-concurrency edition):**
- `WCSessionDelegate` conformance triggers MainActor-isolation inference in iOS 18 / watchOS 11 SDKs in subtle ways. The cleanest pattern is `final class : NSObject, @unchecked Sendable` (no `@MainActor`) with delegate methods declared without isolation modifiers — they get nonisolated treatment via `@unchecked`. The `ARRunner*Environment` singletons are `@MainActor` and call `service.activate()` once at app launch; everything else stays off the main actor.
- For live-tick publishing prefer the three-tier pattern: `sendMessageData` (reachable, low-latency), `updateApplicationContext` (background, latest-wins), `transferUserInfo` (queued, durable). The watch `transmit(_:preferLatestOnly:preferQueued:)` helper picks based on the message type — live tick → latest-only; lifecycle event → queued; other → queued.
- `AsyncStream` is the right shape for the inbound side. The phone receiver's `incomingMessages` stream is bridged into a MainActor view-model; subscribers see future messages only, no replay.

**Hybrid energy approach:**
- `EnergyEstimator` is pure Foundation in Core so it builds on Linux SPM (the existing `ARRunnerCoreTests` Linux job validates it). Sex switch defaults `.unspecified` to the male/female average so we never lose the estimate when the user hasn't shared sex.
- `maxSampleGapSeconds` clamp prevents long pauses from inflating the estimate when the watch resumes sampling. Tested with a 5-min gap → bounded to the 10-s clamp.
- `BodyProfile` lives in Core too. Watch reads body mass + age + sex from HealthKit at workout start; if any field is missing, the view-model just doesn't construct an `EnergyAccumulator` and the live kcal row reads "—".

**Menu-on-finish pattern:**
- The Finish menu is a `confirmationDialog` driven by `launchState == .pendingFinish`. Dialog actions invoke async view-model methods via `Task { await … }`. The Resume button has `role: .cancel` so dragging down on the watch does the right thing.
- Two-phase commit: Finish → pause + show menu (controller still alive) → Save / Discard ends controller. Resume just calls `controller.resume()`. This means the user can Finish, change their mind, Resume, and continue the same `WorkoutController` — no new HK session, no lost samples.

### 2026-05-15T16:49:00-04:00 — v0.2 #4 — Watch-side D4 UX (haptic + HUD-offline)

**Branch / PR:** `feat/v02-d4-watch-ux` → PR #13.

**Outcome:** Both CI legs green (Linux SPM 66 pass / 3 skip; macOS watchOS app build succeeded). Surgical: 2 watch files + 1 test message update, no canonical surface touched.

**watchOS haptic patterns:**
- `WKInterfaceDevice.current().play(.notification)` is the right "subtle but noticed" call for HUD-drop alerts. `.failure` is too alarming for a non-failure event (the workout keeps running fine without HUD); `.directionUp/Down` exist on watchOS 7+ but are intended for navigation cues, not status.
- Wrap the `WKInterfaceDevice` call behind a `@Sendable () -> Void` closure with an `#if canImport(WatchKit) && os(watchOS)` default. Lets the view-model stay testable on Linux (via stub closure) AND keeps the production call zero-overhead. Initializer takes an optional `hapticPlayer` so tests inject a counter; production code uses the default.

**Glasses-status observation pattern:**
- The transport exposes TWO complementary streams: `connectionStates()` (full lifecycle: scanning/connecting/connected/reconnecting/...) and `statusEvents()` (side-channel: `.dropped(reason:at:)`, `.reconnected(gap:at:)`, battery, RSSI). For UX hooks (haptic, banner) read `statusEvents()` — drop reasons are richer and `.reconnected` is unambiguous. For controller-side state mirroring, keep using `connectionStates()` → `GlassesConnectivitySignal.from(_:)` (already wired in v0.2 #2).
- A single MainActor handler `handle(statusEvent:)` switches on cases. Keeping the switch exhaustive makes future side-channel events (battery low, signal weak) easy to add without touching the subscriber loop.

**Debouncing approach:**
- `private var lastHapticAt: Date?` + a 10s constant. Check elapsed in MainActor method; suppress if too recent.
- **Reset on `.reconnected`** so a new outage after recovery alerts immediately. Without reset, a fast disconnect → reconnect → disconnect cycle would silently swallow the second alert.
- Inject `now: @Sendable () -> Date` so deterministic tests can control the clock.
- **Phase gate:** only fire when `launchState == .running`. Drops while `.idle`, `.paused`, `.pendingFinish`, `.ending`, `.ended`, `.cancelled`, or `.failed` are still surfaced visually but never haptic. Decision #5's pause-on-Finish flow stays haptic-quiet — the user is making a UI choice, not running.

**SwiftUI banner pattern:**
- Conditional `@ViewBuilder` (`if viewModel.hudOffline { Label(...) }`) inside the root `VStack`. `.transition(.opacity)` keeps it from popping. Orange `.foregroundStyle` reads as "warning, not error" — matches the D4 "keep recording" intent. SF Symbol `eyeglasses.slash` is the right glyph (not `wifi.slash` — that's network-coded).

**Test-gate decision:**
- The `test_HapticAlertHook_OnDisconnect_ExpectedFailing` skip pinned a `controller.alerts AsyncStream` contract. v0.2 #4 chose to ship haptics directly off `transport.statusEvents()` instead of adding a Core-level alerts stream — the canonical surface stays narrower. The 1:1 outage-to-haptic contract is already covered by `test_Disconnect_EmitsDroppedExactlyOnce`. Updated the skip message to document the deferral so the next reader doesn't spend time hunting a missing implementation.

**Coordination with Weiss:**
- He's working `RunningHUDPreset` + BLE auto-reconnect in parallel. No file overlap (his work is `ARRunnerCore/Glasses/` adapters; mine is `ARRunnerWatch/`). Worktrees made this trivial — he flips the two BLE-owned skip gates when his loop lands.

---

### 2026-05-15 — WidgetKit Info.plist constraints (PR #17, fix/watch-widgets-extension-keys)

**The bug:** `xcodebuild build` succeeded for `ARRunnerWatch`, but `simctl install` (and SwiftUI Preview host install) failed with "Appex bundle ... defines either an NSExtensionMainStoryboard or NSExtensionPrincipalClass key, which is not allowed for the extension point com.apple.widgetkit-extension". Both `ARRunnerWidgetsWatch` and `ARRunnerWidgetsPhone` had the same misconfig in `project.yml`.

**WidgetKit Info.plist constraint:**
- For extension point `com.apple.widgetkit-extension`, the `NSExtension` dict MUST contain only `NSExtensionPointIdentifier`. `NSExtensionMainStoryboard` and `NSExtensionPrincipalClass` are forbidden — the runtime entry point is the Swift `@main WidgetBundle` type, not a plist-declared principal class. Specifying a principal class in the plist conflicts with `@main` resolution and the install-time validator rejects it.
- The `$(PRODUCT_MODULE_NAME).WidgetBundle` style of `NSExtensionPrincipalClass` is a holdover from pre-WidgetKit `NSExtension`-style extensions (Today widgets, share extensions, etc.). When converting/scaffolding a WidgetKit target, those keys must be stripped.

**xcodebuild-vs-install validation gap:**
- `xcodebuild build` only validates code compilation, code signing, and basic bundle structure. It does NOT validate extension-point-specific Info.plist constraints (allowed/forbidden keys per extension point).
- `simctl install` runs the device-side installer (`installd` / `IXUserPresentableErrorDomain`), which DOES enforce these constraints. SwiftUI Preview host install hits the same path — that's why Joe saw it from the Preview, not from a plain build.
- **Implication:** CI that only runs `xcodebuild build` cannot catch this class of bug. Two CI legs were green while the local install was broken.

**Rule for future PRs touching extension targets in `project.yml`:**
- After any change to an extension target's Info.plist (inline `info.properties` in `project.yml` or an explicit Info.plist file), run a `simctl install` smoke test on the resulting `.app` before pushing. Build success is necessary but not sufficient.
- Quickest verification: `/usr/libexec/PlistBuddy -c "Print :NSExtension" path/to/Foo.appex/Info.plist` — eyeball that only the keys allowed by the extension point's contract are present.

**XcodeGen layout for this repo (worth recording):**
- Widget targets use inline `info.properties` in `project.yml` (NOT a checked-in Info.plist file). XcodeGen synthesizes the plist into `Config/ARRunnerWidgets{Phone,Watch}-Info.plist` at generate time. So the source of truth for plist content is `project.yml`, not any file on disk.
- `xcodegen generate` is required after any `project.yml` edit; the `.xcodeproj` is gitignored.

**Out-of-scope finding (separate issue, not fixed in this PR):**
- After the WidgetKit fix, `simctl install` surfaced a *different* error: "This app's bundle identifier does not start with its parent app's bundle identifier ... WKCompanionAppBundleIdentifier=com.arrunner.phone vs watch app bundle id=com.arrunner.watch". Pre-existing companion-bundle-id mismatch. Documented in PR body so it doesn't get lost; needs a follow-up (likely set watch bundle id to `com.arrunner.phone.watchkitapp` or similar to satisfy the prefix rule).

---

### 2026-05-15T18:15:00-04:00 — PR #18: WKCompanion bundle-ID prefix rename

Followed up on the out-of-scope finding from PR #16/#17. Renamed watch + watch-widget bundle IDs so the watch app's `CFBundleIdentifier` is a strict dotted-prefix descendant of the phone app's:

- `ARRunnerWatch`:        `com.arrunner.watch` → `com.arrunner.phone.watchkitapp`
- `ARRunnerWidgetsWatch`: `com.arrunner.watch.widgets` → `com.arrunner.phone.watchkitapp.widgets`
- Phone + phone-widgets unchanged (already prefix-compliant: `com.arrunner.phone` / `com.arrunner.phone.widgets`).
- `WKCompanionAppBundleIdentifier` already pointed at `com.arrunner.phone` — kept as-is.

**Learnings:**

- **Apple's WKCompanion prefix rule (hard).** A watchOS app's `CFBundleIdentifier` must be a strict dotted-prefix descendant of the iPhone host app's `CFBundleIdentifier` declared in `WKCompanionAppBundleIdentifier`. `com.arrunner.watch` is *not* a descendant of `com.arrunner.phone` regardless of how "obvious" the naming feels. The convention Apple's own templates use is `<phone-id>.watchkitapp`. The same prefix rule cascades to embedded `.appex` plugins — `ARRunnerWidgetsWatch` had to become `com.arrunner.phone.watchkitapp.widgets`, not just `com.arrunner.phone.widgets` (which would belong to the phone app, not the watch).
- **The error doesn't appear at build time, only at install time.** `xcodebuild` is happy to produce an .app with a non-compliant companion ID. `xcrun simctl install` is the first thing to reject it. SwiftUI Previews fail silently for the same reason. So "build succeeded" is not a sufficient bar for watch-target work — always do at least one `simctl install` per PR that touches watch bundle config.
- **Audit insight: functional bundle IDs live in exactly one place.** Because Info.plist values are inlined into `project.yml` (no separate `Config/*.plist` files in this repo) and the entitlements files only reference the `group.com.arrunner.shared` app group (which is its own identifier, unrelated to bundle IDs), `project.yml` is the *only* file that carries functional bundle-ID strings. Logger subsystem labels (`Logger(subsystem: "com.arrunner.watch", ...)`) and `DispatchQueue` labels look bundle-ID-shaped by convention but are free-form strings — changing them risks breaking log filters and is out of scope for a bundle-ID rename. Leave them.
- **Layout decision (locked in):** root = `com.arrunner.phone`; everything watch-side sits under `com.arrunner.phone.watchkitapp.*`. If we ever add a phone-side extension (Share/Notification/etc.), it goes under `com.arrunner.phone.*` directly. App group ID (`group.com.arrunner.shared`) is independent of bundle IDs and does not need to follow the prefix rule.
- **Verification recipe for any future bundle-ID change:** (1) `xcodegen generate`; (2) build both schemes against sims; (3) `xcrun simctl install <watch-sim-UDID> <built.app>` — if this exits 0 with no stderr, the companion prefix rule is satisfied; (4) `swift test` from `ARRunnerCore/` to catch any test that hardcoded an ID. Step 3 is the actual signal; steps 1, 2, 4 will pass even when the IDs are wrong.

### 2026-05-15 — v0.2 runtime fixes: HK Error(7), nav title overlap, UIScene manifest
- **HK Error(7) root cause:** `HealthKitWorkoutSubstrate.begin(...)` called `session.startActivity` and `builder.beginCollection` without ever invoking `HKHealthStore.requestAuthorization`. The substrate's docstring delegated auth to "the caller", but no caller ever did. `HKLiveWorkoutBuilder` reacts to pre-flight failure (missing entitlement / usage-string / un-granted auth) by entering the terminal `Error(7)` state with `Allowed transitions = {}` — every subsequent transition is rejected. Fix: added `HealthKitWorkoutSubstrate.requestAuthorization(healthStore:)` (static), call it from `ARRunnerWatchApp` as a `.task` on the WindowGroup root so the system prompt fires on first launch, and call it again defensively from `begin(...)` (a re-request after grant is a no-op, but it guarantees no race vs. the first Start Run tap).
- **project.yml entitlement layout:** the watch target already had `com.apple.developer.healthkit: true` under `entitlements.properties` and `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` under `info.properties`. Entitlement + usage strings alone are necessary but not sufficient — the app **must** actually call `requestAuthorization` before `beginCollection`, otherwise HealthKit acts as if it were unauthorized.
- **Auth type set:** for a workout substrate that writes `HKWorkout` and reads HR / distance / energy stats live from `HKLiveWorkoutBuilder`, share = `{workoutType, heartRate, distanceWalkingRunning, distanceCycling, activeEnergyBurned}`, read = same set (workout objects + per-sample types).
- **watchOS nav title overlap fix:** `.navigationTitle("Run")` on a plain `VStack` whose contents exceed the available height causes the watchOS large title to render over the top row of metrics. Wrapping the body in a `ScrollView` and using `.padding(.horizontal)` / `.padding(.bottom)` (no `.padding()` on the whole VStack) places the metrics below the title bar correctly and lets the user scroll to the footer. Do not reach for `.navigationBarTitleDisplayMode` — that modifier is iOS-only and not available on watchOS.
- **UIScene manifest for SwiftUI App lifecycle (iOS):** even with pure `@main struct ARRunnerPhoneApp: App` (no `SceneDelegate`), iOS 17+ still logs `Info.plist contained no UIScene configuration dictionary` unless the manifest declares at least one entry under `UISceneConfigurations.UIWindowSceneSessionRoleApplication`. A minimal entry with just `UISceneConfigurationName: Default Configuration` (no `UISceneDelegateClassName`) is enough — SwiftUI substitutes its own scene delegate. In `project.yml` this is a nested dict under the iPhone target's `info.properties.UIApplicationSceneManifest`.
- **Build verification:** `xcodebuild` clean for both `ARRunnerWatch` (watchOS Sim 11 46mm) and `ARRunnerPhone` (generic iOS Sim). `swift test` from `ARRunnerCore/` → 78 passed, 1 skipped, 0 failed. `simctl install` onto the watch sim succeeds with the updated entitlements.

## 2026-05-20T21:28:21Z — History compaction archive (laughlin)

### 2026-05-19T15:55:00Z — rc12: Four-Constant Coordinate Fix + Bundled-Bump Release Pattern Validated

**Work:** Shipped v0.3.0-rc12 fixing rotation=4 coordinate placement bug uncovered by textrotation forensic research. Updated 4 Layout constants (leftMargin 20→284, timeY 40→166, distanceY 120→86, paceY 200→6) in single PR #71 COMBINED with version bump (26→27), xcodegen regen, and Info.plist placeholder check — all committed together per Joe's bundled-bump directive.

**Outcome:** 154/154 Core tests pass. TestFlight upload succeeded. Tag v0.3.0-rc12 released.

**Pattern validation:** First release using Joe's bundled-bump pattern (feature + version bump in same PR, no separate follow-up bump PR). Cuts release cycle from 2 PRs to 1, no wasted merge round. End-to-end validated.

**Key learning:** Coordinate errors and firmware rejections have different diagnostic signatures. Off-screen clipping per spec §5.5.6 is silent (no 0xE2 error), but rotation + anchor corner interactions are subtle. When text goes blank, check bounding box vs. framebuffer bounds before escalating to firmware hypothesis.

### 2026-05-19T22:25:00Z — rc17: Workout-Stop Keeps BLE Link Up, Finish-Screen Y Recompute, Battery → Phone, MARKETING_VERSION 0.4.0

**Context:** Richards formalized the BLE-link lifecycle contract (ADR-1: user-managed peripheral, not workout-scoped). Joe's rc16 bench report flagged two failures: (1) finish frame disappears, (2) glasses disconnect mid-stop, forcing manual re-pair. Root cause: `WorkoutViewModel.confirmSave` and `confirmCancel` were calling `teardownTransport()` immediately after (or instead of) pushing the finish frame, severing the link and wiping the screen.

**Work:** Three coordinated pieces:
1. **Lifecycle fix:** Reordered `confirmSave`/`confirmCancel` to stop per-tick HUD task → push finish frame while HK extended-runtime still held → end HK session → **delete `teardownTransport()` call** (deleted the helper entirely to prevent future re-introduction). User's only explicit disconnect affordance is now the UI-facing `disconnectGlasses()` button per Richards's ADR rule R5.
2. **Finish-screen Y anchor recompute:** Old constants (timeY=166, distanceY=86, paceY=6) were derived under obsolete `y_fb = 206 − T` formula (pre-rc16). rc16 introduced canonical formula `y_fb = 255 − wearer_top`. Walked the old layout through new formula and found distance text 57 px off bottom of panel (clipped). Recomputed:
   - finishBannerY = 239 (wearer-top 16)
   - finishTimeY = 159 (wearer-top 96)
   - finishDistanceY = 79 (wearer-top 176)
   - Result: symmetric, even 16-px gaps, fully on-panel. Old names deprecated with compiler nudges.
3. **Battery → iPhone:** `WCMessage` schema v3 adds `glassesBattery(level: Int)` case. Wired through existing three-tier `transmit(..., preferQueued: true)` helper (queued, survives transient disconnect). Phone shows battery via `GlassesBatteryIcon` (SF Symbol, red/orange/green) in `WorkoutMirrorView` above metrics. **Phone-optional contract:** silent no-op if phone unreachable.

**Release mechanics:** `project.yml` bundle 31→32, `MARKETING_VERSION` 0.3.0→0.4.0, Info.plist placeholders verified untouched. Tag v0.4.0-rc1. TestFlight upload queued (automatic per Joe's directive).

**Tests:** 186/186 Core pass (baseline 176; +10 from filter/backoff/schema, +2 from finish-screen Y pins). New tests pin Y-anchor formula AND on-panel invariant. Per-frame wire-byte assertion guards against coordinate-order regression. `xcodebuild` ARRunnerWatch build SUCCEEDED.

**Key learning:** The user mental model for paired peripherals is "they stay paired until I explicitly unpair." Making AR glasses uniquely tear themselves down on "finish run" violates principle-of-least-surprise and breaks the finish-screen UX. The rc16 bench regression ("connection drops on stop, I have to re-pair") is exactly that violation. rc17 fixes it by keeping the link up and letting the user read the finish stats at their own pace.

**Pattern: Bundled-bump release.** Feature + version bump + tag in single PR, merged once, TestFlight upload automatic post-CI-green. Cuts release cycle from 2+ PRs to 1, no manual coordination. Fifth release using this pattern (rc12–rc17); proven reliable.

---

---

### Cross-Agent Note (via Scribe, 2026-05-19)

**From Richards's rc13→rc16 review:**
- **Recommendation #1:** Revalidate the finish-screen Y anchors (timeY=166, distanceY=86) under the rc16 formula `y_fb = 255 − wearer_top`. They were derived under the obsolete `y_fb = 255 − T − font_height` formula. They happen to render OK on bench, but may be off by a font-height. A 30-minute pass with the corrected formula closes a known gap.

**Action:** If Joe directs finish-screen revalidation work, you have context. The rc16 formula is now canonical (`y_fb = 255 − wearer_top`; **no font-height subtraction**). The corrected ALooK font-height table: F1=24 / F2=38 / F3=64 / F4=75 / F5=82.

---

### 2026-05-19T18:45:00-04:00 — rc17: workout-lifecycle / BLE / finish / battery

**Branch:** `fix/rc17-lifecycle-finish-battery`. Joe's three tasks: (1) workout-stop must not tear the BLE link down, (2) finish screen actually renders + Y coords revalidated, (3) glasses battery → phone via WatchConnectivity (phone-optional). Tests 178/178 green (+2 from finish-screen pinning).

**Key learnings to internalize:**

1. **Workout lifecycle ≠ peripheral lifecycle.** rc13→rc16 conflated them — `confirmSave/Cancel` were calling `teardownTransport()` because the watch app's mental model was "the workout owns the link." Joe's directive (and Richards's ADR) splits them: workouts are HK + UI state; the link is a user-managed peripheral session. Workout-stop is now: (a) stop runtime tasks BEFORE push (so live HUD can't race the summary), (b) push the finish frame while HK is still alive (foreground runtime + radio guaranteed), (c) end HK, (d) leave the BLE link up — the user disconnects explicitly when done. Delete `teardownTransport()` outright so a future agent can't re-introduce the bug structurally.

2. **Finish-screen Y revalidation pattern under rc16 formula.** Old `timeY/distanceY/paceY` (166/86/6) were derived under `y_fb = 206 − T` (font height subtracted). Under the canonical rc16 `y_fb = 255 − wearer_top` (NO subtraction), `paceY=6 → wearer_top 249 → bottom 313` = 57 px off-screen for a font-3 line. The disconnect-on-stop bug hid this for 4 RCs because the link tore down before anyone could inspect the finish screen. Lesson: when the rendering surface changes "from coincidentally-on-screen to persistently-inspected-by-Joe," every coordinate derived under a superseded formula needs a re-walk. Recomputed: `finishBannerY=239 / finishTimeY=159 / finishDistanceY=79` (wearer T=16/96/176, 16-16-16 margins, even 16-px gaps). Renamed to surface-scoped names (Richards's rec #3 — old `paceY` was rendering DISTANCE text, the name lied). Old names retained as `@available(*, deprecated, renamed:)` aliases. Pin both the literal values AND the formula (`finishTimeY == 255 - 96`) so an edit that touches one without the other trips CI; also pin the per-frame y-anchor in a wire-byte-decoding test so a banner/time/distance order swap is caught.

3. **WatchConnectivity phone-optional pattern.** For low-frequency low-stakes data (battery, ambient stats), `transferUserInfo` is the right tier — queued, survives transient disconnect, OS wakes the receiver, no blocking on `isReachable`. `sendMessage` is wrong (requires reachable); `updateApplicationContext` is close but doesn't wake the receiver via a delegate callback. The phone-optional contract falls out **for free** from `WatchConnectivityService.transmit(..., preferQueued: true)` because the helper already silent-no-ops when the session is unactivated/unreachable. Watch-side flow: subscribe to glasses event stream → on `.batteryLevel(level)` event call `mirror?.sendGlassesBattery(level)` (the `?` is the phone-optional safety net). Phone-side flow: `WorkoutMirrorViewModel.glassesBatteryLevel: Int?` starts nil; only updated on first `didReceiveUserInfo`. The "nil" state is the source of truth for "no value yet" — no fake "100%" placeholder.

4. **Bundled-bump v4 (rc17 — first cross-MARKETING_VERSION application).** `project.yml` bumped 31→32 AND `MARKETING_VERSION` 0.3.0→0.4.0 in the same PR as the feature work. The pattern (skill `release-mechanics-bundle-bump`) is unchanged from rc12-16 application except: when MARKETING_VERSION rolls, the next tag is `v0.4.0-rc1` (rc counter resets), not `rc17`. xcodegen produced no `.pbxproj` delta — only the project.yml line moved — because the build settings are sourced from xcconfig placeholders. The Info.plist placeholders (`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`) verified preserved per the skill's gotcha #2.

5. **Coordination via inbox decision files (parallel agents).** Weiss owned the BLE-adapter half (battery service discovery, characteristic subscription + initial read so we don't wait 30 s for the first value, event emission). I owned the consumer side (`WorkoutViewModel` event handler, `WCMessage` schema, `WatchConnectivityService` send, phone-side ViewModel + View). We never touched each other's files — `git status` confirms a clean ownership boundary in the diff. Richards filed his ADR `richards-adr-ble-link-lifecycle.md` in parallel; Amber filed QA scenarios `amber-rc17-qa-scenarios.md`. The pattern works: contract negotiated in a brief, individual decision files filed concurrently, Scribe merges. No agent-to-agent direct messaging needed.


### 2026-05-20T11:00:00-04:00 — rc2 (v0.4.0-rc2): Joe's 5K bench-feedback bundle (4-of-5 items, Strava parallel)

**Context:** Joe ran a real 5K with the rc1 (v0.4.0-rc1) build. Five issues; I owned items 1, 3, 4, 5; Richards owned 2 (Strava) in parallel. Single bundled-bump PR per Joe's standing directive.

**Key learnings:**

1. **xcodegen `Config/` is gitignored — Info.plist edits must go in `project.yml properties`, not the plist itself.** I edited `Config/ARRunnerWatch-Info.plist` directly first; the change vanished because the file is regenerated from `project.yml` on every xcodegen run AND because the whole Config/ directory isn't tracked. The correct surface is `targets.ARRunnerWatch.info.properties.NSLocationWhenInUseUsageDescription: ...`. Without that, `CLLocationManager` silently rejects every fix on watchOS and `HKWorkoutRouteBuilder` stays empty — exactly the missing-polyline bug Joe saw on the 5K. **Rule for future Info.plist additions: always touch project.yml first, never the generated plist.** (Pinned in skill `release-mechanics-bundle-bump` gotcha follow-up.)

2. **Terminal-path data integrity: discard MUST be a distinct substrate method, not a branch off save.** The rc17 `confirmCancel` reorder kept calling `controller.end()` because the protocol had no discard verb — only end. So even though the UI branched to `.cancelled`, the substrate still ran `builder.finishWorkout()` and wrote the `HKWorkout`. The fix is structural: add `WorkoutHealthSubstrate.discard(at:)` as a required protocol method, implement it as `session.end()` + `builder.discardWorkout()` (no `finishWorkout`, no route finalize), and route `confirmCancel` through a new `controller.discard()`. No "save then maybe delete" — that branch leaks partial data if delete fails. Tests assert the negative: discard path NEVER calls substrate.end; save path NEVER calls substrate.discard. Pinning the **absence** of a call is the discriminator that catches future regressions of this class. Amber landed `terminal-path-data-leak-qa` SKILL.md in parallel that captures exactly this pattern.

3. **HKWorkoutRouteBuilder lifecycle is workout-scoped, not session-scoped.** `HKWorkoutRouteBuilder` must be created in `begin(...)` (so it captures fixes from start), fed from `CLLocationManagerDelegate.didUpdateLocations` via `insertRouteData(_:)` (filter horizontalAccuracy out-of-range / negative per Apple docs), and finalized via `finishRoute(with: workout, metadata: nil)` **inside `end(...)` AFTER `builder.finishWorkout()` resolves with the persisted HKWorkout**. The finishRoute call associates the polyline with that specific workout sample; if you call it before the workout exists, there's nothing to attach to. **discard(...) MUST NOT call finishRoute** — without it, the route samples drop with the builder when it deallocates. This is the discard-vs-save isolation extended to GPS data.

4. **Finish-screen reshape: the two-field encoder rule was a one-RC rule, not a permanent invariant.** rc14 (Richards's call) said "discard HR/pace at the encoder, finish = Time+Distance only." Joe's rc2 directive reshapes to 4 data items / 3 visual lines (banner / distance / time+pace shared row). I superseded the rc14 rule explicitly (documented in the decision file as evolution, not violation) and renamed `finishBannerY/finishTimeY/finishDistanceY` → `finishLine1Y/finishLine2Y/finishLine3Y` because the rc17 names lied about line content under the new layout. Old names kept as deprecated aliases (compiler nudge for anyone who reaches for them).

5. **Right-justify on ALooK txt = measure string width, compute anchor.** ALooK's `txt` (0x37) under rotation=4 (topLR) anchors text in wearer space at the LEFT edge and grows RIGHT (after the lens flip — empirically validated rc12+). There's no native right-justify primitive. For a right-justified field at wearer_right = R, set wearer_left = R − text_width, then map to framebuffer via `x_fb = 303 − wearer_left`. This finally justified extracting `ALookFontMetrics` (height + per-font average glyph width table) per Richards's rc13 nudge — heights live in one place, widths are addressable, and the right-justify formula is one helper call away (`summaryPaceXFB(for:)`). Conservative width estimates work because the HUD strings are ≤ 10 chars and the slack lands inside the panel margins.

6. **Font selection on a shared line: drop to font 2.** Line 3 hosts two metrics (time + pace) on a 304-px panel. At font 3 (~28 px/char) a 5-char time + 7-char pace span ~336 px and collide. Font 2 (~18 px/char) spans ~216 px with ~88 px of clearance. Same trick rc16 used for the live-HUD line 1 (Time+HR shared, `liveLine1Font = 2`). The encoder enforces this via `Layout.finishLine3Font: UInt8 = 2`; tests pin the on-panel + clearance-from-time-column invariant so a future "but it'd look more readable at font 3" tweak trips CI.

7. **WC schema bump for an additive optional field: make the new field `Optional`, not required, and the version bump documents intent without breaking peers.** `WorkoutTickMessage.startedAt: Date?` (optional) means v3 snapshots from older watch builds still decode on v4 phones — the `Codable` synthesized init treats a missing optional as nil. Phone-side falls back to `timestamp − elapsedSeconds` when nil so the user-visible "Started" row shows a sensible time even without a watch upgrade. WC schema v3 → v4 documents that there's a new field; phones running v4 advertise that to themselves and the watch knows to populate it. The backward-compat test (`testV3SnapshotWithoutStartedAtStillDecodesOnV4`) pins the OLD wire format against the NEW type so a regression that makes the field required trips CI.

**Tests:** 186 → 195 Core. ARRunnerWatch xcodebuild SUCCEEDED.

**PR:** [#79](https://github.com/jkrilov/AR-Runner/pull/79).

---

### 2026-05-20T12:42:23-04:00 — rc3: GPS-route auth fix + discard-returns-to-start (BLE preserved)

**Context:** Joe's v0.4.0-rc2 bench test surfaced two bugs from the same release. Finish screen ✅. Two failures: (1) GPS route still doesn't reach Apple Health even though the location prompt now appears (so the Info.plist fix worked, CoreLocation is producing fixes); (2) Discard tears the BLE link into a stuck state — UI shows "connected" but disconnect/reconnect both no-op until the app is force-killed.

**Root cause #1 — GPS:** `HKWorkoutRouteBuilder.insertRouteData` requires the user to grant share authorization for `HKSeriesType.workoutRoute()`. We never asked for it. The auth request in `HealthKitWorkoutSubstrate.sharedTypes` included workouts + heart rate + distance + energy but **omitted the workout-route series type**. Every `insertRouteData` call returned `success=true` (HK accepts the buffer) but nothing ever reached the persisted polyline, and `finishRoute(with:metadata:)` produced no attached route on the workout. Two prior fixes had been red herrings: the Info.plist location-usage string (needed, but not sufficient) and the substrate's CoreLocation wiring (correct, but blocked downstream by the missing auth). **Add `HKSeriesType.workoutRoute()` to `sharedTypes`** so the next HK auth prompt asks for route-write permission. Also replaced `try?` on `finishRoute` with explicit success/error logging and added per-step `os.Logger` traces (`subsystem=com.arrunner.watch category=WorkoutRoute`) for ingest count, accuracy-filter drops, insert success/error, and finishRoute sample count — the next missing-route regression will surface in Console.app instead of needing another bench bisect.

**Root cause #2 — Discard kills BLE observation:** `WorkoutViewModel.stopRuntimeTasks()` cancelled `glassesStateTask` and `glassesStatusTask` alongside the workout-runtime streams. Per ADR-1, the BLE link is **user-managed and transport-scoped**, not workout-scoped. Cancelling the glasses observers after a discard left the view-model blind to subsequent connection-state events: the UI froze on the last-observed "connected" state while the transport itself was effectively orphaned. `disconnectGlasses()` did call `transport.disconnect()` — but the resulting `.disconnected` event was never observed, so the UI never updated; and `connectGlasses()` early-returned on the stale `.connected` read. Force-kill of the app was the only recovery (rebuilds the view-model + observers from scratch).

**Fix:** Split task-cancellation by scope. `stopRuntimeTasks()` now only cancels workout-scoped tasks (state, metric, elapsed, mirror-tick). Glasses observers are intentionally preserved, with a docstring pinning the contract so a future agent doesn't re-introduce the bug. `confirmCancel` now transitions to `.idle` (not `.cancelled`) after `controller.discard()`, drops the now-finished controller reference, and resets live counters — landing the user on a clean, fully-functional start screen with the BLE link still alive and ready for another run.

**Key learnings:**

1. **HKWorkoutRouteBuilder needs its own share-auth.** `insertRouteData` accepting samples doesn't mean it'll persist them. The route series type is a separate auth grant from the workout type, and the auth API silently degrades to "buffered but never written" without it. Pattern: every HK series type used in a workout (route, environmental audio exposure, etc.) MUST be in `sharedTypes` for its `insertX` calls to take effect. The diagnostic signature was "Info.plist prompt appears, CoreLocation delivers fixes, but Apple Health workout has no map" — that exact signature → check `HKSeriesType.workoutRoute()` is in the share set first.

2. **Best-effort completion handlers hide auth failures.** Pre-rc3 `insertRouteData(filtered) { _, _ in }` swallowed the error parameter. We thought we were tolerating transient transport hiccups; we were actually masking a permanent permission gap. New rule: when the completion handler can surface an auth/config error (vs. just a transient I/O failure), log it loudly. `os.Logger` at `.error` level with `privacy: .public` for non-PII fields keeps the trace useful in production.

3. **Lifecycle scope boundaries must be encoded in helper names.** `stopRuntimeTasks()` was ambiguous — does "runtime" include the transport observers? The old answer was yes; the new answer is no. Either rename to `stopWorkoutRuntimeTasks()` (we considered this and dropped it as redundant since only one cancellation method exists now) OR pin the contract in a docstring (we did this) so the boundary is unmistakable to the next reader. The decision file documents the choice.

4. **Terminal UI states should match user mental model.** `.cancelled` is a terminal state that says "this workout is done, just not saved" — but Joe's mental model on Discard is "go back to where I was before I started, glasses still on." `.idle` matches that mental model. The state-machine purist in me liked `.cancelled` for distinguishability, but the UX wins: the start screen treats `.idle / .ended / .cancelled / .failed` identically anyway, so the distinction was paying for nothing.

**Files changed (2):** `ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift` (route auth + logging), `ARRunnerWatch/Workout/WorkoutViewModel.swift` (discard → idle, BLE observers preserved).

**Tests:** Core 195/195 pass. `xcodebuild -scheme ARRunnerWatch` SUCCEEDED (signing skipped for local validation).


### 2026-05-20T13:19:07-04:00 — rc4: confirmationDialog binding race strands discard on running screen

**Context:** Joe's rc3 (v0.4.0-rc3) bench test: discard still doesn't return to start screen. The rc3 fix (separate `controller.discard()` terminal path, glasses observers preserved, transition to `.idle`) was correct on paper — `xcodebuild` succeeded, 195/195 Core tests passed, code inspection of `confirmCancel()` showed all the right writes. But on-device the wearer lands back on the live running screen post-discard.

**Root cause — SwiftUI `confirmationDialog` ordering race.** When the user taps "Discard" in the dialog, SwiftUI synchronously (same runloop tick) does TWO things:

1. Invokes the Button action → `Task { await viewModel.confirmCancel() }` (enqueued, not yet executing).
2. Dismisses the dialog → invokes the `isPresented` binding's `set(false)` synchronously next.

At step 2, the `confirmCancel` Task hasn't started, so `launchState` is still `.pendingFinish`. The setter's guard (`if !isPresented, viewModel.launchState == .pendingFinish`) — added in rc1 to recover from "stray tap-out" auto-dismissals — fires and spawns `Task { await viewModel.resumeFromFinish() }`. Now two terminal actions race on the same `controller`:

- `confirmCancel` writes `.ending`, suspends on `controller.discard()`.
- During that suspension, `resumeFromFinish` → `resume()` enters; its `guard let controller` captures the still-non-nil property and calls `controller.resume()`.
- `confirmCancel` resumes, sets `controller = nil`, lands `launchState = .idle`.
- `resume()` then resumes from `controller.resume()` (which succeeded — the workout was merely paused), writes `launchState = .running`.

Final state: `.running`. UI shows Pause/Finish. Discard appears "to have done nothing" — the user is stranded on the live screen. Same race latently afflicted Save, but Save's symptoms were masked because the running screen renders briefly before the user dismisses the app or starts another action.

**Fix:** Add a synchronous `acknowledgeFinishChoice()` method on the view-model that transitions `.pendingFinish` → `.ending` (idempotent guard). Call it from the Save / Discard / Resume button actions BEFORE the `Task { … }` is scheduled. Now when SwiftUI synchronously invokes the binding's `set(false)` next, `launchState` is `.ending` — the setter's `launchState == .pendingFinish` guard fails and `resumeFromFinish()` is NOT auto-spawned.

For Resume, the synchronous pre-transition prevents a benign-but-wasteful double-resume() call (one from the Button action, one from the binding setter). The brief `.ending` flash shows a ProgressView for one frame before `.running` lands — acceptable for a tap.

**Key learnings:**

1. **SwiftUI's `confirmationDialog` invokes BOTH the Button action AND the `isPresented` binding's `set(false)` in the same synchronous tick.** This is well-known but easy to forget. If your dismissal binding has side effects gated on view-model state (like the "stray tap-out → resume" recovery here), those side effects WILL fire even on explicit-choice taps unless your state mutation happens BEFORE the binding setter runs. That means **the state mutation must be synchronous from the Button action's closure** — `Task { await … }` is too late because the Task body runs on the next runloop tick at the earliest, after the binding setter has already executed.

2. **`@Observable` view-model state changes inside async functions are not "racing" via @MainActor isolation alone.** Both `confirmCancel` and `resumeFromFinish` run on @MainActor, so they don't *interleave* at instruction level — but they do *interleave at suspension points* (every `await`). The state transitions `.pendingFinish → .ending → … → .idle` and `.pendingFinish → … → .running` both go through suspension points (`controller.discard()`, `controller.resume()`), and which one wins the final assignment depends on which substrate call resolves last. Lesson: in any async terminal flow, assume any other async caller can interleave at every `await`. The synchronous pre-transition is the load-bearing primitive that makes the dialog's "two simultaneous tasks" actually mutually-exclusive — by collapsing the pre-condition check (`launchState == .pendingFinish`) into a single MainActor tick, only one of the two enqueued tasks ever satisfies it.

3. **The "guard on state" pattern in SwiftUI binding setters needs synchronous corroboration from the button action.** The rc1-era `if !isPresented, viewModel.launchState == .pendingFinish { Task { resumeFromFinish() } }` setter is the right pattern for catching stray dismissals, but it ONLY works correctly when the button actions synchronously move out of the gated state. The view-model needs both an async terminal method (for `confirmCancel`) AND a sync acknowledger (for the button action) — two halves of one contract.

4. **A six-RC-old comment can encode a stale assumption.** The rc1 setter comment ("a stray tap-out can't strand the workout in pendingFinish") was correct then because the buttons synchronously mutated state via the legacy non-async API. When the buttons were converted to `Task { await … }` (rc16 or so), the synchronous-pre-condition guarantee was lost silently — no warning, no test break, just a latent race that didn't surface until rc3's discard finally produced an observably-broken UI (rc1/rc2's discard didn't return to start anyway because of the data-leak bug, masking this race). Lesson: when refactoring a sync→async boundary, audit every state-gated callback within two hops for the previously-held synchrony assumption.

**Files changed (2):**
- `ARRunnerWatch/Workout/WorkoutViewModel.swift` — add `acknowledgeFinishChoice()` (sync MainActor method, idempotent guard `.pendingFinish → .ending`).
- `ARRunnerWatch/Views/WorkoutView.swift` — call `viewModel.acknowledgeFinishChoice()` synchronously from Save / Discard / Resume button actions before scheduling the Task.

**Tests:** Core 195/195 pass. `xcodebuild -scheme ARRunnerWatch` SUCCEEDED.


### 2026-05-20T15:33:22-04:00 — v0.5 PR 2: Strava OAuth + Token Store + Settings tab

**Work:** Shipped phone-side Strava plumbing per D-Strava-1/3/5/6 on `feat/v05-strava-oauth` (branched from main, clean rebase off Amber's TCX PR which lives on `feat/v05-tcx-encoder`).

**Files added (all under `ARRunnerPhone/`):**
- `Strava/StravaConfig.swift` — clientID resolved from `STRAVA_CLIENT_ID` env → Info.plist → placeholder. Worker base `https://strava-connect.ar-runner.app`. App Group `group.com.arrunner.shared`. `isConfigured` flag drives a UI warning when the placeholder is still in place.
- `Strava/StravaOAuthService.swift` — `ASWebAuthenticationSession` driving `https://www.strava.com/oauth/authorize?...&approval_prompt=auto`. Callback parsed by pure `StravaOAuthURLBuilder` (testable without a UIWindow). Code exchanged via POST to worker `/token`. `StravaOAuthError` enum keeps framework types out of the VM layer. `MainActor.assumeIsolated` used for the `presentationAnchor` hop because `ASWebAuthenticationPresentationContextProviding` is `nonisolated`.
- `Strava/StravaTokenStore.swift` — single JSON record in shared keychain (`KeychainStravaTokenStore`, access group = `StravaConfig.appGroup`). Auto-refresh via worker `/refresh` when `expiresAt - now < 60s`. `StravaTokenBackingStore` + `StravaTokenRefresher` protocols make the store fully testable in-memory. Update-then-add on save avoids a window where readers see "no tokens".
- `Views/SettingsView.swift` + `SettingsViewModel.swift` — gear tab replaces the old placeholder. Sections: Strava (Connect/Connected/Disconnect + auto-upload toggle) and About (app version). Auto-upload toggle defaults OFF per D-Strava-5 and resets on disconnect. Branded orange `#FC4C02` `Color.stravaOrange` extension for the CTA only.
- `Tests/{StravaOAuthURLBuilderTests, StravaTokenStoreTests, SettingsViewModelTests}.swift` — 16 tests, all green.

**Project changes:**
- `project.yml`: new `ARRunnerPhoneTests` xcodegen target (type `bundle.unit-test`, hosts on ARRunnerPhone, `GENERATE_INFOPLIST_FILE: YES` to dodge code-sign-without-plist error). Excluded `ARRunnerPhone/Tests/**` from the app target sources so test files don't leak into the app binary. Registered `arrunner://` URL scheme via `CFBundleURLTypes` and `StravaClientID: $(STRAVA_CLIENT_ID)` Info.plist key on the phone target.

**Verification:** ARRunnerPhone build green. ARRunnerPhoneTests: 16/16 pass. ARRunnerCore: 215/215 still pass.

**Key learning:**
- Phone app had no test target until now. Pattern for adding one in xcodegen: `type: bundle.unit-test` + `GENERATE_INFOPLIST_FILE: YES` + `TEST_HOST: $(BUILT_PRODUCTS_DIR)/ARRunnerPhone.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ARRunnerPhone` + matching `BUNDLE_LOADER`. Forgetting `GENERATE_INFOPLIST_FILE` fails build-for-testing with "Cannot code sign because the target does not have an Info.plist file".
- When adding a test directory inside an existing target's source path, MUST add `excludes: ["Tests/**"]` to the app target's source spec or the test files compile into the app bundle (and the app fails to link XCTest).
- App Group keychain pattern: pass the raw entitlement group string (`group.com.arrunner.shared`) as `kSecAttrAccessGroup`. The OS resolves it via the entitlement plist; no team-ID prefix needed in client code.
- `ASWebAuthenticationPresentationContextProviding.presentationAnchor(for:)` is `nonisolated`, so the implementation hops to MainActor with `MainActor.assumeIsolated { ... }` to read `UIApplication.shared.connectedScenes`. Cleaner than wrapping the whole conformance in `@preconcurrency`.
- `Config/` is gitignored — Info.plist edits don't ship. Always express plist additions in `project.yml` `info.properties`; xcodegen regenerates the plist on build.

**Cross-agent note:** Amber's `feat/v05-tcx-encoder` branch holds the TCX encoder + activity naming (PR 1). This work (PR 2) is independent — branches share no code. Both should rebase cleanly onto each other when both land in main; PR 3 (upload pipeline) will wire them together via `tokenStore.validAccessToken()`.
