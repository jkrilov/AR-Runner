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
### 2026-05-14T17:33:30-04:00 — CI fix: Xcode pin replaces failing `-downloadPlatform watchOS`

PR #3 had three red checks after Richards's runtime-install attempt landed (`079cb73`). I owned the revision. Notes for next time:

- **`xcodebuild -downloadPlatform <platform>` does NOT work unattended on GitHub-hosted runners.** Exits 70 with `Finding content...Unable to connect to simulator.` That's Apple's "command requires an interactive Apple ID auth session or sudo" error. Anyone reaching for `-downloadPlatform` in CI hits this wall. Do not use it. Pin a Xcode that already bundles the runtime, or use `xcrun simctl runtime add` with a cached DMG, or `mxcl/xcodes-action@v1` if you want the auth-free download flow.
- **Pinning Xcode by symlink path (`/Applications/Xcode_16.app`) is brittle.** That path can shift across runner image revisions. Pin explicitly with `maxim-lobanov/setup-xcode@v1` + `xcode-version: '16.4'`. Same shape every run, regardless of which Xcode the image symlinks to.
- **Runner image manifest is the source of truth for "what simulator runtimes ship pre-installed."** Cross-check both `Installed SDKs` *and* `Installed Simulators` sections of `actions/runner-images/.../macos-15-Readme.md`. An SDK present without its matching simulator runtime is a destination-resolution trap. As of 2026-05, macos-15's default is Xcode 16.4 with iOS 18.5 + watchOS 11.5 simulators pre-baked — both ≥ our D2 minimums (iOS 18 / watchOS 11), so no download step is needed at all.
- **`Ineligible destinations:` in xcodebuild errors is an *enumeration*, not a destination-spec diagnosis.** The task brief told me `name:Any iOS Device` was a smoking gun that the destination string had been mangled to `generic/platform=iOS` (real device). It wasn't. Reading the full error block — including `error:iOS 18.0 is not installed. To use with Xcode, first download and install the platform` — is what surfaced the real cause. When the runtime is missing, the only candidate destination that survives enumeration is the real-device placeholder; that's what gets logged. Look at the `error:` field, not just the `name:` field.
- **Asymmetric resolver leniency between scheme types is real and bites both platforms.** Richards already documented the watchOS variant (app-scheme strict, widget-extension scheme lenient). Same shape on iOS: `ARRunnerPhone` passed under the missing iOS 18.0 runtime; `ARRunnerWidgetsPhone` did not. Same root cause; same fix; one knob (Xcode pin) covers both.
- **Local Mac toolchain (Xcode 26.5 / Swift 6.3.2) remains the source of truth for destination *strings*.** CI runner image manifest is the source of truth for *runtime availability*. Two different sources, two different questions. Don't conflate them.
- **Cost win as a side effect:** dropping the `-downloadPlatform` step saves ~3–5 min wall-clock per watchOS cell. macOS minutes are billed at 10x Linux on private repos.
