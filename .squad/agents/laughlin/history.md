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

### 2026-06-18 — Strava Upload Reliability (v0.6.1)

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
