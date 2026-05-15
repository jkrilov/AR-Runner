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


## 2026-05-15 — PR #4 nit follow-up (cross-reviewer)
Addressed Killian's 3 🟡 nits on PR #4 (chore/public-repo-prep) as the fresh-eyes implementer per reviewer-separation spirit:
1. README.md — hyperlinked first ActiveLook mention to https://www.activelook.net.
2. CONTRIBUTING.md — added Releases-page pointer so outside readers know how to detect v0.1.
3. CODE_OF_CONDUCT.md — new minimal file pointing to Contributor Covenant v2.1.
Sanity-checked `swift build` in ARRunnerCore (clean). One commit; Joe to merge.
