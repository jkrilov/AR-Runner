# Richards — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead
- **Joined:** 2026-05-14T18:30:31.650Z

## Learnings

### GitHub Remote Setup — 2026-05-14T14:37:10-04:00

- **Repo URL:** git@github.com:jkrilov/AR-Runner.git
- **Default Branch:** main
- **Initial Commit SHA:** fd2faad
- **Commit Message:** "Initial commit: Squad scaffolding for AR-Runner" (126 files, ~14.5 KB)
- **Status:** Initialized and committed locally. Push deferred to user (SSH auth required).
- **Setup Process:**
  - `git init -b main` — initialized with main as default branch
  - `git remote add origin git@github.com:jkrilov/AR-Runner.git` — SSH remote configured
  - `git status` verified runtime state dirs (.squad/orchestration-log/, .squad/log/, .squad/decisions/inbox/, .squad/sessions/, .squad/.scratch/) were properly gitignored
  - 126 files staged and committed (Squad scaffolding, workflows, .copilot/ skills, team config)
- **No issues:** All files properly staged, runtime state correctly ignored by .gitignore

<!-- Append learnings below -->

### watchOS Simulator Runtime Missing on macos-15 — 2026-05-14T17:21:00-04:00

- **Trigger:** PR #3 ARRunnerWatch xcodebuild failed with `xcodebuild: error: Unable to find a destination matching ... { generic:1, platform:watchOS Simulator } ... Ineligible: { platform:watchOS, ... Any watchOS Device, error:watchOS 11.0 is not installed }`. ARRunnerWidgetsWatch passed on the **same runner with the same destination spec**, even building ARRunnerWatch transitively as a dependency.
- **Root cause:** `macos-15` + `Xcode_16.app` ships the watchOS 11 **SDK** but not the **simulator runtime**. App schemes (`type: application`) probe for an installed simulator runtime when resolving `generic/platform=watchOS Simulator`; widget extension schemes (`type: app-extension`) don't, so the gap was invisible from the widgets cell.
- **What I ruled out first:** destination spec was already `generic/platform=watchOS Simulator` (correct, matches Amber's local cmd). Joe's local Mac has the runtime installed so the gap doesn't reproduce there. project.yml was untouched — the bug was strictly in the runner image's bundled runtimes.
- **Fix (commit `079cb73`):** Added a conditional install step in `ci-build.yml` gated on `contains(matrix.destination, 'watchOS')` running `sudo xcodebuild -downloadPlatform watchOS`. Adds ~3–5 min per watch cell. Iphone cells skip it. Destination spec unchanged.
- **Why not the other options:** Option 1 (spec fix) didn't apply — spec was already right. Option 3 (pin Xcode via `maxim-lobanov/setup-xcode`) is runner-image-dependent and brittle; `-downloadPlatform` is portable across runner image churn.
- **Generalization for next time I author Apple-platform CI matrices:** Whenever a matrix cell targets a non-default Apple platform (watchOS, visionOS, tvOS), don't trust that the runner image has the runtime — only the SDK. Pre-install via `xcodebuild -downloadPlatform <platform>` gated on the destination. Gate by destination string, not scheme name, so the predicate stays robust as schemes get added. Skill `.squad/skills/swift-linux-macos-runner-split/SKILL.md` updated with this gotcha and confidence bumped to **medium** (applied twice now).
- **For Laughlin / Weiss:** if you ever add `-destination 'generic/platform=visionOS Simulator'` or similar, mirror the install step. Don't try to "save 5 minutes" by skipping it — the asymmetric failure mode (extension passes, app fails) wastes hours diagnosing.
- **No decision drop:** this is implementation polish, not architectural rule. Skill capture + history is the right home.

### Swift 6 StrictConcurrency Redundant-Flag CI Break — 2026-05-14T17:08:00-04:00

- **Trigger:** PR #3 (chore/ci-workflows) failed all 5 build checks with `error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6`.
- **Root cause:** Scaffold had `.enableUpcomingFeature("StrictConcurrency")` in `ARRunnerCore/Package.swift` (and `SWIFT_STRICT_CONCURRENCY: complete` in `project.yml`) — both redundant under Swift 6 language mode.
- **Why it slipped:** Joe's local toolchain is Swift 6.3.2 which silently tolerates the redundant flag. CI runners use the Xcode 16 / Swift 6.0 stable toolchain which treats it as a hard error. **Local-vs-CI toolchain skew is the gotcha to remember.** Treat CI as the authoritative compiler for anything time-sensitive.
- **Fix:** Stripped both declarations. Swift 6 language mode (`swift-tools-version: 6.0` + `.swiftLanguageMode(.v6)` per target + `SWIFT_VERSION: 6.0` at project base) is now the single source of truth. D8 is unchanged — strict concurrency is still mandatory, just enforced implicitly. Commit `350eae0`.
- **Verification:** `swift build` clean (~1s). `xcodebuild -scheme ARRunnerWatch -destination 'generic/platform=watchOS Simulator'` → `** BUILD SUCCEEDED **`. Pushed to chore/ci-workflows; PR will auto-rerun.
- **Upcoming-feature default landscape (Swift 6):** Already on by default — don't manually enable: `StrictConcurrency`, `BareSlashRegexLiterals`, `ConciseMagicFile`, `ImportObjcForwardDeclarations`, `DisableOutwardActorInference`, `IsolatedDefaultValues`, `ForwardTrailingClosures`. Still optional and OK to enable explicitly: `ExistentialAny`, `InternalImportsByDefault` (verify before stripping).
- **For Laughlin (watchOS scaffolding):** When copying boilerplate from Apple sample code or WWDC sessions, strip any `.enableUpcomingFeature(...)` lines on import — most samples target Swift 5.x and they'll be either redundant or CI-breakers under our Swift 6.0 CI. If you genuinely need a feature that ISN'T default-on in Swift 6, talk to me first.
- **For Weiss (ActiveLook SDK / BLE):** Same as above — ActiveLook examples are written against older toolchains. Also: if you ever vendor in a third-party Package.swift, check its `swift-tools-version` header and `swiftSettings` for the same pattern before committing.
- **For future scaffold edits (everyone):** Before pushing any change to `Package.swift` build settings or `project.yml` Swift settings, run `swift build` AND a watchOS-target `xcodebuild` locally. The two compilers don't always agree, and CI runs both. Pre-flight skill captured at `.squad/skills/swift-6-strict-concurrency-default/SKILL.md`.
- **Decision drop:** `.squad/decisions/inbox/richards-strict-concurrency-cleanup.md` — Scribe will fold into ledger.

### System Architecture Plan — 2026-05-14T15:03:23-04:00

- **Deliverable:** `docs/planning/architecture.md` (v0.1) — full system architecture for AR-Runner
- **Decisions inbox:** `.squad/decisions/inbox/richards-architecture-v0.md` (7 ADRs)
- **Key architectural choices made:**
  - `ARRunnerCore` shared SPM package (models, workout state machine, glasses frame protocol, WCSession contract) consumed by both watchOS and iOS shells
  - Three WCSession message types: `LayoutConfigMessage` (phone→watch), `WorkoutTickMessage` (watch→phone, ~1Hz), `WorkoutLifecycleMessage` (watch↔phone)
  - BLE strategy: Option B (phone-only) for v0.1, Option C (hybrid handoff) as v1 target — pending Weiss SDK confirmation
  - State ownership: Watch/HealthKit owns workout session + metrics + history; Phone/iCloud KV owns layout config + preferences; BLE owner TBD
  - Minimum targets: watchOS 11 / iOS 18 / Swift 6 (recommended, Joe must confirm)
  - `GlassesFrameProtocol` abstracted behind a Swift protocol so Laughlin can build before BLE strategy is locked
- **Blocking inputs needed:**
  - **Weiss:** ActiveLook SDK platform support (iOS? watchOS? SPM/XCFramework/Pod?), GATT frame throughput/budget
  - **Laughlin:** WCSession reachability during HKWorkoutSession, App Intent background launch capability
  - **Killian:** Is custom run history in MVP scope? (D4 decision)
  - **Joe:** D1–D7 decision points (BLE ownership, OS targets, persistence strategy, workspace layout, Swift 6)
- **Risk register:** 5 risks documented (BLE occlusion, watch radio contention, App Intent background, frame budget, iCloud KV race)
- **Patterns applied:** SPM bounded contexts, domain-driven state ownership, typed WCSession contract, abstract BLE protocol boundary

### 2026-05-14: Team update from Joe — 9 architecture decisions locked (see decisions.md D1-D9). Next phase: Xcode scaffolding (Laughlin) + ActiveLook watchOS BLE spike (Weiss).

### 2026-05-14: Team update from Joe — v0.1 foundation scaffold + BLE spike landed on feat/v01-foundation. Branch awaiting Joe's push & PR. Next: WorkoutController impl (Laughlin) + watchOS BLE wrapper impl (Weiss).

### CI / Security Workflow Architecture — 2026-05-14T16:51:53-04:00

- **Branch:** `chore/ci-workflows` (off `chore/macos-build-validation` — D-"No Direct Main" compliant; rebases cleanly when Amber's branch merges).
- **Three workflows landed:** `ci-core-tests.yml` (Linux), `ci-build.yml` (macOS x4 matrix), `codeql.yml` (macOS + weekly schedule).
- **Linux spike outcome — GREEN:** `ARRunnerCore/Sources` imports only `Foundation`; tests import `XCTest` + `Foundation`. No Apple-framework imports anywhere. SwiftPM `platforms:` is a min-Apple-version declaration, not a Linux exclusion. Linux `swift:6.0-jammy` is the right home for core tests.
- **The Linux job is now an architectural enforcement mechanism.** If Weiss or Laughlin ever import HealthKit / CoreBluetooth / WatchKit / WatchConnectivity / UIKit / AppKit into Core, the job fails. That's exactly the boundary ADR-001 + ADR-007 specified — CI now mechanically enforces it.
- **Cost shape:** macOS ~10x Linux. Concurrency cancellation on PRs (never on main). `fail-fast: false` on matrix so one platform breakage doesn't mask another. CodeQL drives off a single scheme (ARRunnerWatch — largest closure) instead of the full matrix.
- **What Weiss/Laughlin should know when adding tests:**
  1. Don't import Apple-framework code into ARRunnerCore. Use protocol boundaries; concrete implementations live in app targets. Same rule the architecture already documented — CI just makes it loud.
  2. `@preconcurrency import` of ActiveLook SDK stays in watch/phone target, never in Core.
  3. ~15 min CI budget per PR after cache warm-up. Local validation (Amber's repro block) matches CI 1:1.
  4. Coverage and lint are deferred — no point measuring/linting a 6-test scaffold. Re-evaluate after real logic lands.
- **Punt list (TODO when CI is green):** lint tool selection (swiftlint vs swift-format), coverage upload, release/TestFlight workflow, Dependabot (no external SPM deps yet), branch protection on main (Joe must toggle in repo settings).
- **Skill captured:** `.squad/skills/swift-linux-macos-runner-split/SKILL.md` — reusable Linux-Core + macOS-shell CI pattern for any Swift project with a pure-Swift shared SPM core.
- **PR:** Joe to file manually at `https://github.com/jkrilov/AR-Runner/pull/new/chore/ci-workflows` (gh-auth account mismatch).

### Xcode Version vs. Simulator Runtime Catalog — 2026-05-14T21:40:00Z (Amber revision + Scribe log)

- **From Amber's fresh-eyes investigation (commit 38580ce):** Your `-downloadPlatform` fix in commit 079cb73 actually regressed CI from 1→3 failures. Root cause was **not** a destination-spec mismatch as initially assumed.
- **The actual issue:** `macos-15` runner image under Xcode 16.0 has the iOS/watchOS **SDKs** but lacks the **simulator runtimes**. The symptom was different per scheme type:
  - App schemes (ARRunnerWatch) probe for installed simulator runtime → fail with `watchOS 11.0 is not installed`.
  - App-extension schemes (ARRunnerWidgetsWatch) don't probe the same way → pass silently, masking the gap.
- **Why `-downloadPlatform` failed:** That command requires Apple ID auth, which GitHub-hosted runners reject with exit 70. Portability was the wrong tradeoff.
- **The fix (Amber → commit 38580ce):** Pin Xcode 16.4 via `maxim-lobanov/setup-xcode@v1`. Per the [actions/runner-images macos-15 manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md), Xcode 16.4 ships with iOS 18.5 + watchOS 11.5 simulator runtimes **pre-installed** — both ≥ our D2 minimums. No download step needed.
- **Key memory for next time you touch CI:**
  1. Always cross-check the [runner-images manifest](https://github.com/actions/runner-images) — check both "Installed SDKs" **and** "Installed Simulators" columns.
  2. An Xcode symlink pin (`/Applications/Xcode_16.app`) is brittle; the symlink can shift when the image rotates. Use `maxim-lobanov/setup-xcode@v1` with explicit version instead.
  3. Asymmetric scheme-type failures (app passes, extension fails, or vice versa) are often simulator-runtime gaps, not destination-spec bugs.
  4. The `Ineligible destinations:` error block is an enumeration fallback, not a destination-spec diagnosis — read the full block, not just the `name:` field.
- **Going forward:** When you need a runtime that isn't pre-baked on any image, Option B is cached DMG + `xcrun simctl runtime add`, or Option C is `mxcl/xcodes-action`. Avoid `-downloadPlatform` in unattended CI.
- **Skill updates:** `.squad/skills/swift-linux-macos-runner-split/SKILL.md` now documents this gotcha + confidence bumped to **medium** (pattern recognized across two fix iterations).
