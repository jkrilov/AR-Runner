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
