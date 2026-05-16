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
