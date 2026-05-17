# Richards — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead
- **Joined:** 2026-05-14T18:30:31.650Z

## Session Summary — 2026-05-15

**Archive (v1 deep-dive condensed):** 17.5 KB → 2.5 KB. Full entries remain in decisions.md and skill docs.

- **GitHub Remote Setup:** Initialized repo with Squad scaffolding (126 files), SSH remote configured, runtime state correctly gitignored.
- **CI/Simulator Runtime Architecture:** Built Linux + macOS matrix (Linux enforces ARRunnerCore purity). Xcode 16.4 + `maxim-lobanov/setup-xcode` solved simulator runtime gaps on macos-15. Skill captured for future Apple-platform CI matrices.
- **Swift 6 StrictConcurrency:** Stripped redundant `.enableUpcomingFeature("StrictConcurrency")` (D8 remains locked, just implicit under Swift 6 language mode).
- **System Architecture (ADR-001 through ADR-007):** Delivered `docs/planning/architecture.md` (v0.1). D1–D9 locked by Joe; BLE spike (Weiss) + WorkoutController impl (Laughlin) + layout editor design (Killian) are next phases.
- **Public-Repo Readiness Audit:** Verdict 🟡 = go after small cleanup. Single hard 🔴: username `` in one orchestration log. ActiveLook licensing nuance: SDK is Apache 2.0 ✓, Visual-Assets are CC BY-NC-ND 4.0 ⚠️ (hard rule: original art only). 5 open questions for Joe on LICENSE, copyright, visual-assets policy, outside-PR posture, Squad documentation tone.

## Learnings

### 2026-05-16: Gitignored xcconfig + configFiles reference requires bootstrap in ALL xcodegen workflows

**Pattern:** When `project.yml` references a gitignored xcconfig via `configFiles` (e.g., `Config/Signing.xcconfig`), `xcodegen generate` exits 1 with "Invalid config file" if that file is absent — regardless of whether the consuming build uses `CODE_SIGNING_ALLOWED=NO`. xcodegen validates file existence at parse time, before any xcodebuild flags are considered.

**Rule (durable):** Every workflow that calls `xcodegen generate` must call `scripts/bootstrap-signing.sh` first — not just the release workflow. The script is idempotent: called with no `APPLE_TEAM_ID`, it creates a placeholder xcconfig with `DEVELOPMENT_TEAM =` (empty). For no-signing CI builds, the empty team ID is harmless.

**PR #21 incident:** `release-testflight.yml` bootstrapped correctly (needed real team ID from secrets). `ci-build.yml` and `codeql.yml` did not. All 4 macOS matrix builds + CodeQL went red. Linux `swift test` was unaffected (never calls xcodegen). Fixed in commit d8339d0 — added `Bootstrap signing xcconfig` step before `xcodegen generate` in both workflows.

**Checklist:** When adding a new workflow that calls `xcodegen generate`:
- Does `project.yml` have any `configFiles` references pointing to gitignored files?
- If yes → add `Bootstrap signing xcconfig` step before `xcodegen generate`

**References:** Decision inbox: `richards-pr21-ci-fix.md`; Skill: `.squad/skills/ios-testflight-ci-via-actions/SKILL.md`

### GitHub Remote Setup — 2026-05-14T14:37:10-04:00

- **Repo URL:** git@github.com:jkrilov/AR-Runner.git
- **Default Branch:** main
- **Initial Commit SHA:** fd2faad
- **Commit Message:** "Initial commit: Squad scaffolding for AR-Runner" (126 files, ~14.5 KB)
- **Status:** Initialized and committed locally. Push deferred to user (SSH auth required).
- **Setup Process:**
  - `git init -b main` — initialized with main as default branch
  - `git remote add origin git@github.com:jkrilov/AR-Runner.git` — SSH remote configured

## Archive

### Session Summary — 2026-05-14

Condensed from deep-dive learnings (17.5 KB → 2.5 KB summary, full entries below):

**Key accomplishments:**
- GitHub Remote Setup (SSH, 126-file Squad scaffolding committed)
- CI/Simulator Runtime Architecture (Linux + macOS matrix, Xcode 16.4 pin solves watchOS runtime gap)
- Swift 6 StrictConcurrency (stripped redundant flags; D8 remains locked)
- System Architecture (ADR-001 through ADR-007 delivered in docs/planning/architecture.md)
- Public-Repo Readiness Audit (verdict 🟡 after cleanup; 5 open questions for Joe)

**Learnings recorded:** watchOS simulator runtime gaps on CI, Swift 6 toolchain version skew, xcodebuild `-downloadPlatform` not viable on GitHub runners.

**Reference:** Full decision drops remain in `.squad/decisions.md`; skills in `.squad/skills/`

### Detailed CI/Build Learnings (2026-05-14)

#### watchOS Simulator Runtime Missing on macos-15
- Trigger: `xcodebuild` failed for `ARRunnerWatch` but passed for `ARRunnerWidgetsWatch` (app vs widget-extension scheme asymmetry)
- Root: macos-15 + Xcode_16.app ship watchOS 11 SDK but not simulator runtime
- Fix: Xcode 16.4 pin via `maxim-lobanov/setup-xcode@v1` (includes iOS 18.5 + watchOS 11.5 runtimes pre-installed)
- Gotcha: `xcodebuild -downloadPlatform watchOS` exits 70 on GitHub runners (needs Apple ID auth); don't use it

#### Swift 6 StrictConcurrency Redundant-Flag CI Break
- Trigger: PR #3 failed with `error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6`
- Root: Scaffold had redundant `.enableUpcomingFeature("StrictConcurrency")` + `SWIFT_STRICT_CONCURRENCY: complete`; Swift 6 language mode already enforces it
- Local vs CI: Swift 6.3.2 (local) silently tolerates; Swift 6.0 (CI) treats as error
- Fix: Stripped redundant flags; Swift 6 language mode is single source of truth
- Lesson: Treat CI as authoritative compiler; test against CI toolchain version, not local

#### Xcode Version vs. Simulator Runtime Catalog
- Runner image manifest (`actions/runner-images/...macos-15-Readme.md`) is the source of truth for installed runtimes
- Cross-check both `Installed SDKs` AND `Installed Simulators` sections
- Asymmetric failure (ARRunnerPhone passes, ARRunnerWidgetsPhone fails) due to scheme-type resolver leniency
- `Ineligible destinations:` is an enumeration, not a diagnosis; read the full error block including `error:` field

#### CI / Security Workflow Architecture
- Three workflows: `ci-core-tests.yml` (Linux), `ci-build.yml` (macOS 4-way), `codeql.yml` (security + weekly)
- Linux spike outcome: ARRunnerCore is platform-pure (Foundation only); Linux job enforces ADR-001/ADR-007
- Cost shape: macOS ~10x Linux; concurrency cancel on PRs only; CodeQL on single scheme (ARRunnerWatch)
- Constraints for Weiss/Laughlin: No Apple-framework imports in ARRunnerCore; `@preconcurrency import` at target level; ~15 min CI budget per PR
- Skills captured: `swift-linux-macos-runner-split` pattern for reuse

#### System Architecture Plan
- Deliverable: `docs/planning/architecture.md` (v0.1)
- 7 ADRs (ADR-001 through ADR-007) covering SPM structure, WCSession contract, BLE strategy, state ownership, OS targets, protocol boundaries
- Blocking inputs from Weiss (SDK platform support, GATT throughput), Laughlin (WCSession + App Intent), Killian (custom history in MVP), Joe (D1–D7)
- 5 risks documented (BLE occlusion, radio contention, App Intent background, frame budget, iCloud KV race)

**Lockout status:** Richards is now fully locked out of follow-up revisions on this branch. Per reviewer-rejection-protocol, if Joe wants the 3 nits folded in pre-merge, either Killian (who raised them) or a fresh agent like Amber must implement. Richards cannot touch chore/public-repo-prep again until merged and closed.

**Non-blocking nits (3) — Joe decides: fold in or punt:**
1. **Nit A (README):** Add hyperlink to ActiveLook website/GitHub org on first mention (help strangers orient).
2. **Nit B (CONTRIBUTING.md):** One-liner pointing to Releases page (so outside readers know how to track v0.1 ship date).
3. **Nit C (governance):** Add minimal CODE_OF_CONDUCT.md (GitHub community profile will flag absence once public).

**Next action:** Joe either (a) merges as-is, or (b) requests nit fold-in via Killian or Amber. Richards will remain locked pending merge.


### 2026-05-15: v0.1 foundation workstreams complete — three PRs open awaiting review

**Parallel agents completed:**
- Weiss (feat/ble-wrapper, PR #5): GlassesFrameTransport protocol + ActiveLook watchOS adapter (24 tests, ✅ CI green)
- Laughlin (feat/workout-controller, PR #7): WorkoutController actor + HealthKit substrate (14 tests, ✅ CI green)
- Amber (feat/integration-mocks, PR #6): Integration test scaffolding + cross-agent mocks + D4 happy-path test (12 tests, ✅ CodeQL green)

All three PRs now open and awaiting Joe's review/coordination. Cross-agent protocol naming gaps identified for small follow-up reconciliation PR post-merge (expected minor, well-documented in decisions.md).

decisions.md now 61442 bytes (merged 4 inbox entries: weiss, laughlin, amber, and CI architecture).


### 2026-05-15: pbxproj target-membership "bug" was actually stale-generated-project (XcodeGen)

**Reported symptom:** `Cannot find 'GlassesTransportFactory' in scope` at `ARRunnerWatch/Views/WorkoutView.swift:11`. Coordinator diagnosed it as PR #9 having missed `GlassesTransportFactory.swift` and `ActiveLookGlassesAdapterHardwareTests.swift` from `AR-Runner.xcodeproj/project.pbxproj` target membership, and assigned a surgical pbxproj-edit task.

**Actual root cause:** This repo uses **XcodeGen**. `AR-Runner.xcodeproj/` is gitignored (see `.gitignore`: `*.xcodeproj/`), regenerated from `project.yml`. The Watch target's `sources: [path: ARRunnerWatch]` is **recursive** — every `.swift` under that tree is auto-included. Both "missing" files exist on disk and appear with 4 refs each immediately after `xcodegen generate`. Joe's local pbxproj was simply stale (generated before PR #9 landed those files).

**Unblock for Joe:** `xcodegen generate` from repo root; re-open Xcode.

**Recurring failure-mode pattern (durable learning):**
- Symptom: "Cannot find X in scope" for a Swift type whose file demonstrably exists.
- Diagnosis trap: looks identical to a missed Xcode-target-membership bug (the classic Apple-developer footgun in hand-managed `.xcodeproj` files). In a hand-edited project, it would be — and the suggested fix (add to PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase) is correct.
- In **this** repo, it's never that. pbxproj is generated. The fix is always `xcodegen generate`.
- The generated-project/hand-edited-project distinction needs to be the **first** question whenever an Xcode target-membership bug is suspected. `git check-ignore AR-Runner.xcodeproj/project.pbxproj` answers it in one shot.

**Process miss:** Coordinator's diagnosis didn't sanity-check whether `AR-Runner.xcodeproj/` was tracked in git before prescribing pbxproj edits. Adding a checklist item for that is going through Scribe (see `.squad/decisions/inbox/richards-pbxproj-target-membership-checklist.md`).

**Artifacts produced:**
- New skill: `.squad/skills/xcodegen-stale-generated-project/SKILL.md` — failure mode + 30-second triage.
- Decision inbox: `.squad/decisions/inbox/richards-pbxproj-target-membership-checklist.md` — proposes triage-first rule for any "missing symbol / target membership" report.
- Doc PR: small troubleshooting section added to `docs/dev/setup.md` so the next dev who hits this self-serves in one step.

**No code/pbxproj edits made.** pbxproj is gitignored — committing it would create a stale snapshot that fights XcodeGen on every regen.
