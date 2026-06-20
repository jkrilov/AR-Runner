# Laughlin — History (Compacted 2026-06-18)

## Core Context

- **Project:** Apple Watch fitness app + ActiveLook AR glasses integration
- **Role:** watchOS Dev
- **Joined:** 2026-05-14

## Current Work (v0.6)

### 2026-06-18 — v0.6.1 Strava Upload Reliability Fix — SHIPPED
PR #123 merged, tagged v0.6.1-1, TestFlight run 27767550622. Three-part fix: (1) reclaim orphaned `.uploading` entries at queue init, (2) background URLSession with file body + PhoneAppDelegate hook, (3) new `.processing` state polling `checkUploadStatus`. State machine: `pickNext()` selects `.pending` and `.processing`; no unreachable states. 8 new phone tests. v0.6.1 baseline for post-release stale-task sweep.

### 2026-06-18 — v0.6.0 App-Shell Migration — COMPLETED
PR #121 merged. ARRunnerWatch/Phone/Widgets + Shared migrated to composite `WorkoutType`. Preference types in `Shared/Settings/` (App Group pattern). HealthKit tuple return `(HKWorkoutActivityType, HKWorkoutSessionLocationType)`. GPS gating on `!type.isIndoor`. Cycling speed/cadence mapped. Action Button expanded to 6 cases. WCMessage v6 bidirectional sync. 3 compile fixes post-merge (ActionButtonIntent, GlassesService, WorkoutMirrorViewModel). All CI validation pending.

### 2026-06-17 — v0.6 Multi-Sport Planning — LOCKED
10 working decisions for v0.6.0 Phase 1: sport enum (6 cases), HealthKit, speed metric, picker UI, defaults, WCMessage v6. All 215 Core tests pass (pre-v0.6.0 baseline).

## v0.5 Releases (Archived 2026-05-20—2026-05-27)

**Summary:** v0.5.1–v0.5.19 shipped Strava OAuth + TCX + Uploader + Action Button + Appearance. Key fixes: process isolation (AppGroup UserDefaults), wrong API surface (StartWorkoutIntent), missing framework link (AppIntents), v0.5.19 dialog message bug (copy is behavior contract), v0.5.20 release-guard SemVer bug (GNU sort -V incorrect for pre-releases).

**Learnings:**
- Lifecycle independence: Workout end ≠ BLE disconnect; discard ≠ Health persist.
- Copy is a behavior contract; audit all user-facing strings on behavior fixes.
- AppIntents run out-of-host; bridge via App Group UserDefaults.
- Schema evolution: Codable + Optional + version bump = mixed-version safe.
- Release guard: Pre-release suffix needs custom SemVer comparator, not `sort -V`.

See `.squad/decisions.md` for locked ADRs and `.squad/log/` for session detail.

## Core Patterns

1. **Coordinate System:** `y_fb = 255 − wearer_top` (test formula, not constants).
2. **Terminal Paths:** Distinct substrate verbs per path; never branch shared logic.
3. **App Group Pattern:** UserDefaults + process-boundary bridge for intents.
4. **Schema Evolution:** Optional fields + version bump for compat.
5. **Copy Audit:** On behavior fixes, scan all user-facing strings in the same PR.

## Test Status

- **ARRunnerCore:** 215/215 pass
- **ARRunnerPhone:** 39/39 pass (incl. 8 new Strava tests for v0.6.1)
- **ARRunnerWatch:** Build green (CI-gated full validation)

## Next

Post-release stale-task sweep. v0.6.1 stable; no blockers. v0.6.1+ custom-layout editor pending Weiss feasibility study.

---

## Learnings

### 2026-06-19 — Custom HUD Layout Phase A (persistence + sync + resolver, INERT)

**Scope (feat/custom-hud-phase-a):** Backend plumbing for user-defined HUD layouts. No UI, no version bump — byte-identical for users with no customs. Followed Richards' architecture (additive-within-WCMessage-v6, NOT a v7 bump — the envelope rejects higher-versioned peers wholesale and would break the live mirror).

**New Core types (`ARRunnerCore/Sources/ARRunnerCore/Models/`):**
- `HUDLayoutCatalog{ schemaVersion, layouts: [HUDLayout] }` — custom layouts only; built-ins stay code-defined. `static let currentVersion = 1`; `layout(id:)` helper.
- `WorkoutLayoutDefaults{ schemaVersion, assignments: [String:String] }` — keyed by `WorkoutType.rawValue` → custom `HUDLayout.id`. `layoutID(for:)` helper.
- `HUDLayout.validated(for:)` — blanks slots whose metric `!isValid(for:)` to `nil`, **preserving slot indices/count** (never compact/reorder).
- `enum HUDLayoutResolver.activeLayout(for:defaults:catalog:)` — PURE: assigned custom in catalog → return it; else `HUDLayout.default(for:)`. Dangling/unknown id falls through to built-in. Does NOT apply `.validated` (callers do at render time, per Weiss).

**Messaging:** Added `case layoutCatalog(HUDLayoutCatalog)` + `case layoutDefaults(WorkoutLayoutDefaults)` to `WCMessage` — additive in v6 (`currentSchemaVersion` stays 6). Mirrored `defaultWorkoutType`/`unitPreference` exactly: Kind enum, CodingKeys (`layoutCatalog`/`layoutDefaults` value keys), encode/decode switches. `.unknown` lenient fallback preserved — a pre-layout v6 peer decodes the new kinds to `.unknown`, never throws.

**Persistence:** `Shared/Settings/HUDLayoutStore.swift` — App Group (`group.com.arrunner.shared`) JSON store, keys `"hudLayoutCatalog"`/`"hudLayoutDefaults"`. Mirrors `WorkoutTypePreference`: `currentCatalog`/`currentDefaults` get/set + change-detecting `store(catalog:)`/`store(defaults:)`. `Shared/` is globbed into watch+phone targets (`- path: Shared`) so NO project.yml change needed (unlike widgets, which list `WorkoutTypePreference.swift` explicitly).

**Watch:** `WatchConnectivityService.persist(inbound:)` now persists `.layoutCatalog`/`.layoutDefaults` → `HUDLayoutStore`; added distinct applicationContext keys `hudLayoutCatalog`/`hudLayoutDefaults` to `didReceiveApplicationContext`. `WorkoutViewModel.pushHUDFrameIfConnected` (~line 809) swapped hardcoded `HUDLayout.default(for: sport)` → `HUDLayoutResolver.activeLayout(for: sport, defaults: HUDLayoutStore.currentDefaults, catalog: HUDLayoutStore.currentCatalog).validated(for: sport)`. Downstream (metricStrings/orderedSlotStrings/frames) unchanged.

**Phone:** Added `sendLayoutCatalog(_:)`/`sendLayoutDefaults(_:)` + `transmitLayout` — reachable → `sendMessageData`, always reconcile latest into `applicationContext` under DISTINCT keys (not the `"wcMessage"` slot) so a catalog push doesn't clobber the live snapshot (Richards' note). Not wired to any caller until Phase B editor.

**Gotchas:**
- Docker swift test: the Windows bind-mount `.build` dir copies a stale ModuleCache → `PCH was compiled with module cache path '/work/...'` + `missing required module 'SwiftShims'`. Fix: `cp -a /work /src && rm -rf /src/.build && cd /src && swift test`. Always nuke `.build` after copying off the bind mount.
- Field names from task spec override Richards' sketch: catalog field is `layouts` (not `custom`), defaults key file is `hudLayoutDefaults` (not `workoutLayoutDefaults`).

**Tests:** +18 Core tests (15 `CustomHUDLayoutTests` + 3 in `WCMessageV6Tests`). `swift test` GREEN: **328 executed, 0 failures, 1 skipped** (was 310). App-target compile is CI-gated (no Xcode on Windows bench).



**The bug:** Long runs stuck in `.uploading`. `StravaUploadQueue.uploadOne` persisted `.uploading` BEFORE awaiting URLSession upload. iOS suspension mid-upload orphaned the entry; `pickNext()` only selected `.pending` → stuck forever.

**Three-part fix:**

1. **Reclaim orphans** — `reclaimOrphans` (pure, tested) rewrites any persisted `.uploading`→`.pending` at init (no retry consumed). Idempotency via `external_id` (HKWorkout UUID) → 409 dup detection.

2. **Background URLSession** — `BackgroundStravaUploadTransport`: background config `com.arrunner.phone.strava-upload`, file-based multipart, `CheckedContinuation` delegate bridge, `PhoneAppDelegate` background-launch hook. GET polls use separate ephemeral session (bg sessions can't run data tasks).

3. **Confirm processing** — new `.processing` state. After 2xx POST with null `activity_id`, poll `checkUploadStatus` with bounded backoff `[2,5,10,20,30]s` / max 12 polls. Outcomes: `activity_id` → `.completed`; `error` → `.failed`; budget exceeded → `.pending` (re-POST → 409 → completed).

**State machine:** `pickNext()` selects both `.pending` and `.processing`; `.uploading` reclaimed at init. No unreachable states.

**Gotchas:**
- Optional `confirmPollCount: Int? = nil` for pre-v0.6.1 queue file compat (uses `decodeIfPresent`).
- `externalID` threaded through `StravaUploadTransport` for background task tagging.
- UIKit completion handler non-`Sendable`; wrapped in `@unchecked Sendable` CompletionBox for `DispatchQueue.main.async` hop.
- `.processing` maps to `.uploading` in HistoryViewModel so History UI needs no new case.

**Learnings:**
1. Persist-before pattern is dangerous — state-machine invariants > Codable atomicity.
2. Background URLSession requires file bodies; in-memory won't survive suspension.
3. 409 Duplicate is idempotency's friend; unlock retry/confirmation patterns.
4. Polling with max-attempt gates prevents infinite loops; budget→reclaimable bridges to re-POST.

---

## v0.6.2 — Autonomous queue scheduling (the v0.6.1 follow-up)

User reported the 3.25 mi run STILL stuck on "uploading" in v0.6.1 — foregrounded, hit Retry, never finished. Short runs fine. The v0.6.1 fix (orphan reclaim + background URLSession + confirm-poll state) was correct but INCOMPLETE: it added a `.processing` poll phase but never built anything to *drive* it while the app stays open.

### Root cause (the lesson)
`StravaUploadQueue.process()` drained only entries currently *due* via `pickNext()`, then returned. When `uploadOne` moved an entry to `.processing` with a fresh `lastAttemptDate`, the next `pickNext()` found it not-yet-due (poll backoff `[2,5,10,20,30]s`) and returned nil — so `process()` exited. **Nothing ever called `process()` again.** No timer, no scheduler. A `.processing` entry's confirm poll never fired → stalled forever. The History UI showed `.processing` as "uploading", which is exactly the stuck spinner the user saw. The same gap froze any `.pending` entry whose retry backoff hadn't elapsed.

### The fix (v0.6.2 A–D)
- **A — self-rescheduling drain.** After `process()` drains the due-now pass, compute the soonest future due-time (`nextDueDate`, pure/tested) across non-terminal entries and arm exactly ONE follow-up `Task { await sleep; await process() }`, cancel/replace each pass. Loop self-terminates when no non-terminal entries remain. Injected `sleep` seam so tests drive the scheduler deterministically via the mutable clock.
- **B — upload continuation timeout.** `BackgroundStravaUploadTransport` now arms a 120s `DispatchWorkItem` watchdog per upload; on timeout it cancels the URLSession task and resumes the continuation with a network error → `uploadOne` catch marks the entry retryable `.pending`. Single-resume guard = whoever removes the continuation from the dict first wins.
- **C — orphaned-completion reconcile.** `didCompleteWithError`'s no-waiter branch no longer DROPS the result; it hands `(externalID=taskDescription, statusCode, body)` to a queue-registered `OrphanReconciler` that finds the entry by `workoutID == UUID(externalID)` and advances it (→ `.processing`/`.completed`) or marks `.pending`.
- **D — visible status.** `HistoryViewModel.UploadDisplay` gained `.processing(message:)` and `.pending(message:)`; History rows now surface the queue's `errorMessage`/Strava processing note so a stuck/failed upload shows WHY instead of an indefinite spinner.

### Learnings
1. **A new non-terminal state needs a DRIVER, not just a transition.** v0.6.1 added `.processing` but no scheduler — adding a state without an autonomous advance path is how you build a new stall. State-machine invariant: no non-terminal entry may sit without an autonomous path to advance while the app runs.
2. **`CheckedContinuation` with no timeout is a latent hang.** Always race a bridged continuation against a timeout and guarantee exactly-once resume.
3. **Don't drop orphaned async results — reconcile them.** A completion with no in-process waiter still carries truth (`taskDescription` = externalID); route it back into the state machine.
4. **An actor's fire-and-forget scheduler Task must re-enter via `await self?.method()` and be cancelled in `deinit`** so it can't outlive the instance (critical for test hygiene — a real-`Task.sleep` drain would otherwise hit the stub transport after the test ended).

## Custom HUD Phase B — phone editor + per-type defaults (v0.6.4, 2026-06-19)

Built the phone UI on Phase A's inert backend: `HUDLayoutStore` (App Group),
`HUDLayoutResolver`, and the v6 `WCMessage.layoutCatalog`/`.layoutDefaults`
sync cases (first real caller). Three screens under
`ARRunnerPhone/Views/GlassesLayouts/`: list (presets/custom/per-type),
4-slot editor with metric picker + static amber preview, metric-picker sheet.
Pure logic lives in `static` methods on `HUDLayoutsViewModel` (auto-name,
unique-name, cap, dedup slot-build, assignment updates, validity warning).

### Learnings
1. **Keep view-model pure logic SwiftUI-free and `static`.** Auto-naming,
   cap, dedup, assignment edits as `static` funcs made them unit-testable
   without a `WCSession` or App Group, and let the Core preview helper carry
   the Linux-tested width/sample logic. The VM file imports only
   `ARRunnerCore`/`Foundation` — so `remove(atOffsets:)` (a SwiftUI API) is
   NOT available there; delete via `enumerated().filter` instead.
2. **Sync behind a one-method protocol for testability.** `HUDLayoutSyncing`
   (conformed by `WatchConnectivityService`) let a `SpySync` assert that
   mutations push to the watch without a live session.
3. **Exhaustive `MetricKind` switches are the CI-only trap.** New
   `sampleValue`/`displayLabel`/`shortLabel` switches cover all 8 cases with
   no `default:` so a future metric forces a compile error, not a silent gap.
4. **Width warning is conservative + non-blocking.** Reused
   `ALookFontMetrics` + the grid's line-1-right anchor (83px) as the budget;
   left `// TODO(bench): calibrate line-1 width threshold`. Saving never
   blocks on it.
5. **Prune dangling assignments on delete.** Deleting a custom layout strips
   any per-type assignment referencing it (resolver would fall back anyway,
   but it keeps the synced blob tidy) and syncs both catalog + defaults.

## Learnings — v0.6.5 (configurable grid + compass + preview icons), 2026-06-19

1. **Optional Codable field = free backward compat.** Adding
   `HUDLayout.grid: HUDGridConfig?` lets Swift's synthesized decoder map a
   missing `grid` key to `nil` with no custom `init(from:)`. `nil` ⇒
   `resolvedGrid == .standard`, so every v0.6.4 layout (and `default(for:)`)
   decodes byte-identical. Proven by a legacy-JSON decode test. No WCMessage
   schema bump needed — the field rides inside the existing `HUDLayout` in
   `.layoutCatalog`.
2. **Keep pixels in code, shape in the model.** Only the grid *shape*
   (`lines: [Int]`, 2–4 lines × 1–2 items) is Codable/synced; all
   coordinates/fonts stay in `HUDGridDefinition.make(for:)` (Core code).
   Geometry can be recalibrated by shipping an app update without migrating
   any stored/synced layout.
3. **standard4 isn't formula-clean.** Its slot0 `iconWearerCenterY=35` was
   hand-bumped from the computed 34, so `make(for:)` early-returns the
   literal `standard4` for the `[2,1,1]` case and only runs the general
   factory for other shapes. All non-`[2,1,1]` coordinates are EXTRAP and
   marked `// TODO(bench): calibrate on Engo 2`.
4. **Recurring CI-only exhaustive-switch failures bite test helpers too.**
   Adding `MetricKind.heading` broke two *test* `switch metric.kind` helpers
   (`WorkoutControllerIntegrationTests`, `DisconnectResilienceTests`) that
   the source-only grep missed. Always `swift test` (Docker) — the Linux
   build catches every switch, app code AND tests.
5. **Thread workout-start flags without touching the Core protocol.** Rather
   than change `begin(sport:startedAt:)` (touches all mocks + controller
   tests), added a separate `setNeedsHeading(_:)` substrate method with a
   default no-op. The watch VM computes `needsHeading` from the resolved
   active layout and calls it before `controller.start()`. Magnetometer only
   spins up when a `.heading` slot is actually on screen; works indoors (NOT
   gated on `!isIndoor`).
6. **Compass formatting is pure + testable in Core.** `formatHeading` lives
   in `RunMetricFormatting` (no CoreLocation); the watch shell sources
   `CLHeading` behind the substrate and yields `WorkoutMetric(.heading,…)`.
   8-point cardinal via `Int((d+22.5)/45)%8`, normalized 0–359, non-finite →
   `--`. trueHeading preferred, magneticHeading fallback, bucketed to integer
   degrees to throttle BLE.
