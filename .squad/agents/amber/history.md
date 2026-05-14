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
- **D8 (Swift 6 strict concurrency) is paying off already.** Zero data-race / `Sendable` warnings across the whole scaffold. The actor discipline (`WorkoutController`, `WatchConnectivityService`, `GlassesService` are all actors; `GlassesFrameTransport` is `Sendable`; app entries are `@MainActor`) holds.
- **Heads-up for Weiss (ActiveLook SDK boundary):** when the iOS SDK gets pulled in for the watch BLE wrapper, use `@preconcurrency import` per D8. The scaffold-side surface (`GlassesFrameTransport`) is already `Sendable` and won't fight you. Drop concrete transport conformances in the watch app target, not in ARRunnerCore — keeps the core platform-agnostic.
- **Heads-up for Laughlin:** the "Metadata extraction skipped — No AppIntents.framework dependency found" warning is benign right now (StartWorkoutIntent lives in the widget extension). It'll vanish once the parent watch target either imports AppIntents directly or wires the intent into its launch flow. Don't waste time chasing it before the foreground-launch glue is in.
- **Test coverage is shallow but correct.** Each of the six suites is a single `testCodableRoundTrip`. That's fine for scaffold; tests live alongside the work that adds real behavior. When metrics calc / split detection / pace smoothing land, I'll grow these into property-based or scenario suites.
- **Repro is in `docs/dev/macos-build-validation.md`.** Anyone else moving from Windows runs the same five commands and sees green.

### 2026-05-14T21:00:00Z: Scribe — CI Workflows Landed on chore/ci-workflows

**From:** Scribe (session orchestration)

Richards completed CI architecture design + implementation. Three workflows now committed to `.github/workflows/`:

1. **`ci-core-tests.yml`** — Linux runner. Tests `ARRunnerCore` with `swift test` on `swift:6.0-jammy` container.
2. **`ci-build.yml`** — macOS runner. Builds all four app targets (Watch, Phone, WidgetsPhone, WidgetsWatch) via xcodebuild 4-way matrix.
3. **`codeql.yml`** — GitHub CodeQL security analysis (PR + weekly).

**Critical for Amber:** The Linux ci-core-tests job now enforces ARRunnerCore platform-agnosticism mechanically. Future PRs (from Weiss, Laughlin, and all subsequent contributors) must keep concrete Apple-framework code out of Core. Your three scaffold fixes enabled this — the Linux spike only works because those bugs are now resolved. This is architectural enforcement paying dividends immediately.

**Architecture assurance:** Weiss's BLE wrapper (ActiveLook SDK) must live in ARRunnerWatch, not ARRunnerCore. Laughlin's HealthKit + WatchConnectivity code must live in ARRunnerWatch, not ARRunnerCore. The Linux ci-core-tests job blocks any slip-ups. This is the payoff from D8 (Swift 6 strict concurrency) + ADR-007 (protocol boundaries).

**Timeline:** PR #3 (chore/ci-workflows) queued behind PR #2 (macos-build-validation). Joe will open both manually. When merged, all subsequent feature branches auto-validate.

**Reference:** `.squad/orchestration-log/2026-05-14T21:00:00Z-richards.md` for full ADRs and design rationale. `.squad/decisions.md` now contains the full CI architecture decision with all trade-offs captured.

### 2026-05-14T21:12:00Z: Scribe — CI Swift 6.0 Toolchain Gotcha (Richards fix landed)

**From:** Scribe (session orchestration)

PR #3 (chore/ci-workflows) first real CI run caught hard error:
> error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6

**Root cause:** Scaffold included redundant `.enableUpcomingFeature("StrictConcurrency")` in `ARRunnerCore/Package.swift`. Local Swift 6.3.2 silently tolerates it; CI Swift 6.0 treats as hard error. This is the classic toolchain-version gap — your smoke test couldn't catch this because you tested locally against 6.3.2.

**Fix applied (350eae0):** Removed the explicit flag. Swift 6 language mode (`swift-tools-version: 6.0` + `.swiftLanguageMode(.v6)`) is the single source of truth.

**Key lesson for future smoke tests:** When validating across platforms, verify against the CI toolchain version (6.0), not just local. Deprecated flags, newly-removed APIs, and other version-specific changes will silently pass local build but hard-fail CI. Treat CI as the authoritative compiler.

**Action:** Your local smoke-test process is still valuable — it caught the earlier three bugs. This one slipped through because the local toolchain was too permissive. Consider adding a "CI toolchain simulation" step for future validation sprints.