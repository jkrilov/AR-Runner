# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Recent Work (v0.5+)

### 2026-05-27 — Team: v0.5.20 shipped via tag-push (first to do so cleanly)
Release-guard monotonicity fix validated end-to-end. PR #117, tag `v0.5.20-1`, workflow run 26511705252 PASS. Build 50 shipped to TestFlight. First pre-release to traverse tag-push cleanly; all future releases now auto-trigger reliably.

### 2026-05-26 — v0.5.20 release-guard fix: COMMITTED, push BLOCKED on missing `workflow` scope
- **Task:** Fix the two interacting bugs in `release-testflight.yml`'s monotonicity guard that had forced every v0.5.x release through manual `workflow_dispatch`.
- **Bug 1 — self-collision (confirmed):** On tag-push, `git fetch --tags --force` pulled the trigger tag into the local list; `git tag --list 'v*'` then surfaced it as the candidate `LATEST_TAG`, and `RAW_VERSION == LATEST_TAG` always fired. The guard was comparing the trigger tag against itself.
- **Bug 2 — `sort -V` is not SemVer-correct (confirmed empirically):** `printf '0.5.18\n0.5.19\n0.5.19-1\n0.5.20\n0.5.20-1\n' | sort -V` returned `0.5.18 / 0.5.19 / 0.5.19-1 / 0.5.20 / 0.5.20-1`. GNU sort -V treats the pre-release suffix as a longer-string continuation, putting `0.5.19-1` AFTER `0.5.19`. SemVer 2.0 specifies the opposite. The original code comment claimed the desired ordering but had never been verified.
- **Fix:** Inline ~30-line bash `semver_gt` that parses `MAJOR.MINOR.PATCH[-PRERELEASE]`, compares numeric components, then applies SemVer pre-release rules (absence > presence; identifier-by-identifier; numeric vs numeric numerically, otherwise lex). Trigger-tag exclusion on `push` events via `grep -v -F -x`. Highest-tag selection by reduction instead of `sort -V | tail -1`. A separate self-test step BEFORE the guard exercises 11 fixture assertions and fails fast on regression.
- **Local verification:** All 11 assertions pass in Git Bash (`0.5.20 > 0.5.19`, `0.5.19 > 0.5.19-1`, `0.5.19-1 < 0.5.19`, `0.5.20-1 > 0.5.19`, `0.5.19-2 > 0.5.19-1`, equality is not strict-greater, `1.0.0 > 0.99.99`, etc.).
- **Version bump:** `VERSION` 0.5.19 → 0.5.20; `project.yml` `MARKETING_VERSION` 0.5.19 → 0.5.20 and `CURRENT_PROJECT_VERSION` 49 → 50 (CI overrides the latter with `github.run_number`, but bumping keeps local dev builds aligned).
- **Branch:** `chore/release-monotonicity-guard-fix` at `42851ed`. Diff: workflow + VERSION + project.yml + new `.squad/skills/release-monotonicity/SKILL.md`.
- **BLOCKER — push refused.** GitHub returned `refusing to allow an OAuth App to create or update workflow .github/workflows/release-testflight.yml without workflow scope`. The session's gh CLI token has `admin:public_key, gist, read:org, repo` only. Git Credential Manager pulled the same token; explicit `x-access-token` URL push got the same rejection. `gh auth refresh -h github.com -s workflow` requires interactive browser device-code auth which I can't complete from a non-interactive shell.
- **Handoff:** Joe runs `gh auth refresh -h github.com -s workflow` in his own terminal, accepts the device code, then `git push -u origin chore/release-monotonicity-guard-fix`. The commit, PR template, version bumps, decision inbox file, and SKILL.md are all in place — the end-to-end smoke test (PR → squash-merge → tag `v0.5.20-1` → auto-trigger) can resume from step 5 of the original plan.
- **Lesson — token scopes are part of release infrastructure.** Branch protection blocked direct main pushes (already known). What I missed: the OAuth-app `workflow` scope is a separate gate that only matters when modifying CI files. Worth adding to the release checklist: "if you're touching `.github/workflows/*`, verify your gh token has `workflow` scope before starting."
- **Skill earned:** `.squad/skills/release-monotonicity/SKILL.md` — semver-correct ordering in bash, trigger-tag exclusion pattern, in-workflow comparator self-test.

### 2026-05-26 — v0.5.19 ship: discard "leak" was a dialog text bug, not a code bug
- **Symptom:** Joe reported watch Discard was leaking to Apple Fitness/Health. Two independent audits (mine + Amber's) confirmed WorkoutHealthSubstrate.discard() calls uilder.discardWorkout() only — never inishWorkout() — and is still pinned by WorkoutDiscardTerminalPathTests. The code has been correct since the rc2 substrate work.
- **Actual bug:** The Finish-Run confirmation dialog at ARRunnerWatch/Views/WorkoutView.swift:117 carried v0.2-era copy: "Discard removes it from this view (it remains in Health and can be deleted there)." That statement became false the moment the rc2 substrate landed, and was never updated. Reading it, a careful user reasonably concluded discard wasn't actually discarding.
- **Fix:** One-line copy change to "Discard permanently removes it — nothing is saved to Health or Strava." Also updated stale doc-comment on WorkoutViewModel.LaunchState.cancelled that referenced "the substrate protocol does not expose a discard path in v0.2." Shipped as v0.5.19 build 49 in PR #116.
- **Lesson — copy is a behavior contract.** When you fix a Health/persistence behavior, audit every user-facing string that asserts what happens on that path in the same PR. A correct code path with a stale dialog is operationally indistinguishable from a broken path. Add "scan user-facing copy" to the terminal-path checklist alongside "audit substrate seam."
- **Workflow snag:** The pre-release tag 0.5.19-1 auto-trigger of elease-testflight.yml self-tripped its monotonicity guard — git tag --list 'v*' | sort -V | tail -n 1 includes the just-pushed tag, so RAW_VERSION == LATEST_TAG always. Recovered with manual workflow_dispatch using ersion=0.5.19 (the pattern Joe has used for every v0.5.x release per gh run list). The guard should exclude the trigger tag from its own LATEST_TAG calculation — filing as a v0.5.20 chore.

### 2026-05-21 — Strava API compliance pass (button copy, deauth, token-exchange client_id)
- **Brand-guideline button:** Exact "Connect with Strava" string, 48pt height on orange (#FC4C02).
- **Deauthorize on disconnect:** Server-side revocation per API agreement. Added StravaOAuthService.deauthorize() that POSTs to worker's /deauthorize endpoint.
- **Token-exchange fix:** Missing client_id in OAuth code exchange body (latent bug from PR #84). Added for both initial exchange and refresh.
- **Validation:** 39/39 ARRunnerPhoneTests pass.

### 2026-05-20–2026-05-22 — v0.5 releases (OAuth, TCX, Uploader, Action Button, Appearance)
- **v0.5.1–v0.5.3:** Phone-side Strava OAuth/token store + Settings tab.
- **v0.5.4:** Appearance mode (Light/Dark/System) via @AppStorage.
- **v0.5.5–v0.5.7:** Apple Watch Action Button support. Went through two major iterations:
  - v0.5.5: Process-isolation bug (intents run out-of-host). Fixed via AppGroupPendingActionButtonPressStore.
  - v0.5.6: Wrong API surface. Switched from AppShortcuts to StartWorkoutIntent protocol (only path that populates Settings → Action Button → Workout).
  - v0.5.7: Missing AppIntents.framework link in project.yml caused metadata extractor to skip. Added explicit framework dependency. Also added PauseWorkoutIntent / ResumeWorkoutIntent.
- **v0.5.8–v0.5.10:** Action Button UX polish (split markers, transient UI, HKWorkoutEvent donation, segments).

## Core Patterns (Load-Bearing Across Releases)

### Lifecycle Ownership
- **Problem:** rc17 discovered "workout lifecycle ≠ peripheral lifecycle." Stopping a workout shouldn't tear down BLE (finish screen needs it). Applied to rc2 discard: "confirm-save lifecycle ≠ persist-to-health lifecycle."
- **Solution:** Distinct substrate verb methods per terminal path (never branch off a shared path). rc2 formalized as 	erminal-path-data-leak-qa skill.

### Coordinate System
- **Formula:** y_fb = 255 − wearer_top (no font-height subtraction). Pinned via rc12/rc16/rc17/rc2 revalidations.
- **Pattern:** Pin the formula in tests, not just the constant values. When formula changes or new rendering surface appears, tests catch missing updates.

### AppIntents Cross-Process Model
- **Discovery:** AppIntent.perform() runs out-of-host when invoked from system surfaces (Action Button, Siri, Shortcuts).
- **Pattern:** Use App Group UserDefaults or files to bridge the process boundary. Host drains the flag on scenePhase == .active.
- **Template:** PendingWorkoutStartStore + PendingActionButtonPressStore — reuse for all future hardware-button work.
- **Registration gotcha:** Two unrelated surfaces for Action Button — AppShortcutsProvider (Shortcut category) vs. StartWorkoutIntent (Workout category). They are not interchangeable; fitness apps must use StartWorkoutIntent.
- **Metadata verification:** After build, check .../DerivedData/.../Metadata.appintents/extract.actionsdata for intent identifiers and systemProtocols. If Metadata.appintents/ directory is absent, the framework isn't linked (no import AppIntents alone won't fix it).

### WatchConnectivity Schema Evolution
- **Pattern:** Codable + Optional field + version bump = old peers decode without blocking. rc17 + rc2 both added optional fields (glassesBattery, startedAt) safely.

## Archives

- **Pre-rc12 development:** history-archive.md (rc1–rc11 documentation, blank-screen saga, first fixes).
- **rc12–rc10 technical detail:** history-archive-v05-pre.md (release-by-release deep dives, six-release pattern evolution).

## Key Files Touched (Recent Sessions)

- ARRunnerWatch/Views/WorkoutView.swift (dialog text, UI polish)
- ARRunnerWatch/Workout/WorkoutViewModel.swift (action button, state management)
- ARRunnerPhone/Strava/StravaOAuthService.swift (compliance)
- ARRunnerWatch/ActionButton/ActionButtonIntent.swift (intents)
- project.yml (framework links, version bumps)

## Test Status

- **ARRunnerCore:** 215/215 tests pass (Linux CI required).
- **ARRunnerPhone:** 39/39 tests pass.
- **ARRunnerWatch:** Build green (watchOS Simulator).

## Next Phase

Waiting for Joe's bench confirmation of v0.5.19 discard fix. v0.5.20 should include a chore to fix the release-testflight.yml tag-monotonicity guard (framework will need coordination with any parallel pre-release work).

## Session 2026-06-17: v0.6 Multi-Sport Planning

**Context:** Feature 1 for v0.6.x (Phase 1) — additional workout types with watch-side picker and user-selectable default.

**Deliverable:** 10 working decisions (WD-1–WD-10) covering SportType enum expansion, HealthKit locationType mapping (sport.isIndoor ? .indoor : .outdoor), MetricKind.speed addition, WorkoutController.makeSummary branching on sport, WorkoutView type-picker UI, default workout type preference (App Group UserDefaults), Action Button expansion (5 cases), WCMessage schema v6 (defaultWorkoutType case), HealthKit cycling cadence authorization, and file inventory.

**Key codebase findings:**
- SportType already accepted by WorkoutController.start() — just add cases, no signature change.
- HealthKitWorkoutSubstrate hardcodes locationType = .outdoor at line 201; extend mapping via sport.isIndoor.
- GPS must be gated on location type (skip HKWorkoutRouteBuilder creation and locationManager for indoor).
- MetricKind needs .speed case (cycling); WorkoutSummary needs companion averageSpeedMetersPerSecond field.
- WorkoutView pre-run state needs type picker; WorkoutViewModel.start() already accepts SportType = .running.
- Action Button (ARRunnerWorkoutStyleEnum) should expose all 5 types via AppGroupPendingWorkoutStartStore + UserDefaults default.
- WCSession: add WCMessage.defaultWorkoutType(SportType) case for phone↔watch sync.

**Pattern:** Add computed properties (isIndoor, baseActivity) in Core, not framework imports. Watch shell does HealthKit mapping via existing activityType(for:) seam.

**Status:** COMPLETE, awaiting jkrilov review. Downstream coordination needed: Amber (TCX sport), Richards (phone WCMessage v6), Weiss (cycling HUD + smart stack).

## Learnings

### 2026-06-17 — v0.6 multi-sport planning: workout types + watch selection UI

**Context:** Planning Feature 1 for AR-Runner 0.6.x — additional workout types (outdoor walk, indoor run, outdoor bike, indoor bike) with watch-side type picker and user-selectable default.

**Key findings from codebase audit:**

- `SportType.swift:6` is a flat 3-case enum with no location dimension. `WorkoutController.start()` signature already accepts `SportType` and forwards to `substrate.begin(sport:)`. No structural surgery needed — just add cases.
- `HealthKitWorkoutSubstrate.begin(sport:startedAt:)` at line 201 hardcodes `configuration.locationType = .outdoor`. The `activityType(for:)` mapping at line 495 is a clean 3-case switch — the indoor/outdoor split is a one-line addition per new case.
- **GPS must be gated on location type.** `locationManager.startUpdatingLocation()` at line 240 fires unconditionally today. For indoor workouts, neither the `HKWorkoutRouteBuilder` creation (line 220) nor the location manager start should execute. The existing nil-guards at line 379 (`if let workout, let routeBuilder`) and line 454 (`guard let routeBuilder`) in `end()` and `ingest(locations:)` already handle the nil-routeBuilder case safely — no logic change there.
- **Metric pipeline**: `MetricKind` at `WorkoutMetric.swift:6` has no `.speed` case. `WorkoutController.makeSummary()` at line 339 always computes pace; cycling needs speed instead. `WorkoutSummary` at `WorkoutSummary.swift:28` already has `averagePaceSecondsPerKilometer: Double?` — add a companion `averageSpeedMetersPerSecond: Double?`.
- **Watch UI**: `WorkoutView.controlsSection` (line 447) shows `Button("Start Run")` calling `viewModel.start()` with no argument. Type picker needs to live in the pre-run state alongside this button. The `WorkoutViewModel.start(activity:)` at line 234 already accepts `SportType = .running` — no signature change needed.
- **Action Button**: `ARRunnerWorkoutStyleEnum` at `ActionButtonIntent.swift:25` has a single `.run` case. All 5 types should be exposed as suggested workouts. The cross-process `AppGroupPendingWorkoutStartStore` + default-type `UserDefaults` key (App Group suite, same as `ActionButtonMode.sharedDefaults`) is the right pattern for carrying the selected type from the intent to the host.
- **WCSession**: `LifecycleEvent.started(SportType)` and `WorkoutTickMessage.sport` already carry the active type — phone mirrors see it correctly from day one. What's missing is a message for syncing the user's *default* type selection from phone to watch (or watch to phone). Recommend a new `WCMessage.defaultWorkoutType(SportType)` case in v6.

**Concurrency:** No new hazards. Indoor workout simply skips the location manager entirely; HKWorkoutSessionDelegate callbacks (line 505) map HKWorkoutSessionState → WorkoutSubstratePhase independently of sport type.

**Pattern confirmed:** "Add computed properties, not framework imports." `SportType.isIndoor` and `SportType.baseActivity` belong in Core (pure Swift logic). The watch shell does the HealthKit mapping — same seam pattern as the existing `activityType(for:)` static method at line 495.

**Downstream dependencies identified:**
- Amber: TCX encoder Sport attribute for cycling.
- Richards: phone-side WCMessage v6 + default-type sync UI.
- Weiss: cycling HUD layout (speed, no pace) + Smart Stack default-type respect.

### 2026-05-27 - v0.5.20 monotonicity-guard chore SHIPPED (end-to-end smoke test PASSED)
- **PR #117** (https://github.com/jkrilov/AR-Runner/pull/117) squash-merged at `13c8f7a`. All 4 required checks green: ARRunnerPhone, ARRunnerWatch, ARRunnerCore Linux tests, CodeQL.
- **Tag v0.5.20-1** pushed against `13c8f7a`. `release-testflight.yml` auto-triggered as expected (run 26511705252).
- **Headline result: the guard step passed on tag-push.** First v0.5.x pre-release in project history to traverse the tag-push path cleanly without `workflow_dispatch` fallback. Both bugs (self-collision + `sort -V` semver mis-ordering) are confirmed fixed in production CI.
- **Self-test step ran first and passed all 11 fixture assertions** before the real guard ran. The defense-in-depth worked exactly as designed.
- **TestFlight upload completed**: archive + ipa export + ASC upload all green. Run: https://github.com/jkrilov/AR-Runner/actions/runs/26511705252 (total 3m40s on macos-26).
- **No surprises.** CodeQL took its usual ~35 min; everything else completed in normal windows. Push went through immediately after Joe's `gh auth refresh -s workflow`.
- **Lesson confirmed:** when fixing release infrastructure, the only proof that matters is the real-world tag-push trigger. The 11-assertion self-test in the workflow was useful for regression-proofing but the actual validation was watching v0.5.20-1 traverse the guard without intervention.
- **Skill confidence bumped** to `medium` on `.squad/skills/release-monotonicity/SKILL.md` (real-world verification, single observation - not yet `high` until next pre-release reconfirms).

