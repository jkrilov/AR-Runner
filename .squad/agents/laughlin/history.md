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
