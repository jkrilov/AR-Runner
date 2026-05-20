---
updated_at: 2026-05-20T14:50:00Z
focus_area: v0.4.0-rc2 on TestFlight (PR #79 merge auto-released). Awaiting Joe's bench: D1 discard smoke FIRST (data-integrity gate), then GPS+Strava 2-for-1 verification, finish screen visual, phone Started row. Three new skills added (HKRouteBuilder lifecycle, terminal-path data-leak QA, third-party fitness integration triage).
active_issues:
  - v0.4.0-rc2 shipped: PR #79 ready for merge → auto-release to TestFlight (GPS, discard/save fix, finish-screen, battery, phone mirror)
  - Joe's rc2 bench validation: D1 discard smoke test FIRST (data-integrity regression gate), then feature parity
  - Items #1 & #2 collapsed: Richards diagnosed Strava gap couples to GPS. Likely 2-for-1 fix with Laughlin's route-builder work.
---

# What We're Focused On

**Immediate (2026-05-20T14:50Z):** v0.4.0-rc2 shipped as PR #79. Four agents (Richards, Weiss, Amber, Laughlin) executed rc2-bench-feedback batch in parallel. PR ready for code review → auto-release to TestFlight on CI green + merge. Joe's bench validation next: **D1 discard smoke test FIRST** (highest-severity data-integrity gate), then GPS+Strava 2-for-1 verification, finish-screen visual, phone Started row parity.

**rc2 Delivered (2026-05-20T10:42–11:20Z, PR #79 pending merge):**

**Item #1 — GPS Route Recording (CLLocationManager + HKWorkoutRouteBuilder):**
- Location manager started at begin(), feeds route builder, finalized at end()
- Route samples drop on discard (no leak)
- NSLocationWhenInUseUsageDescription added to Info.plist via project.yml properties (NOT hand-edited plist)
- Tests: route builder lifecycle, discard semantics pinned

**Item #2 — Strava Ingestion (Diagnosis: coupled to item #1):**
- Richards verified: Strava ↔ Apple Health works on Joe's device; gap is AR-Runner's missing route data
- HKWorkoutRoute absence = outdoor workout filters for auto-import
- Cheap fix: Laughlin's item #1 implementation likely unblocks Strava for free (same subsystem bug)
- Escalation path documented if cheap fix doesn't work

**Item #3 — Finish-Screen Layout Reshape (3-line / 4-data, font 2 on line 3):**
- Finished! / distance / time+pace (vs. rc1 banner / distance / time)
- Y constants 239/151/63 derived under canonical rc16 formula (y_fb = 255 − wearer_top), unchanged from rc17
- Line 3 right-justify via two separate txt writes (finishPaceX = 180 fixed anchor)
- ALookFontMetrics extracted (heights + per-font widths); future work (rc3+) makes finishPaceX computed

**Item #4 — Discard-vs-Save Data Integrity (Terminal-Path Bifurcation — HIGHEST SEVERITY):**
- Root cause: confirmCancel was calling end() which always persisted HKWorkout regardless of user intent
- Fix: New WorkoutHealthSubstrate.discard(at:) method (protocol + all implementations)
- HealthKitWorkoutSubstrate.discard() = session.end() + builder.discardWorkout() (NO finishWorkout, NO route)
- confirmCancel routes through controller.discard() NOT controller.end()
- WorkoutDiscardTerminalPathTests pins: save → end 1× never discard; discard → discard 1× never end
- New skill: `terminal-path-data-leak-qa` (reusable pattern for future discard/save bifurcations)

**Item #5 — Phone Mirror "Started at HH:MM" Row:**
- WorkoutTickMessage.startedAt: Date? (optional, carried every tick)
- WC schema v3 → v4 (backward-compat: v3 snapshots decode, fallback to timestamp − elapsedSeconds)
- Phone-side: "Started" row with SF Symbol checkered flag + short DateFormatter

**Test Status:** 195/195 Core pass (+9 from rc1). xcodebuild ARRunnerWatch SUCCEEDED. CI ready.

**Current Activity (2026-05-20T14:50Z):**
1. **PR #79:** Code review pending (Killian or Lead). Auto-releases to TestFlight on CI green + merge.
2. **Joe:** Bench validation on rc2 build. **D1 discard smoke test FIRST** (data-integrity gate), then feature parity verification (GPS, Strava, finish screen, phone mirror).
3. **Team:** Monitoring for Joe's bench signal. No hotfixes; rc3+ driven by bench results.

**Canonical Artifacts:**
- ADR-1 (BLE-link lifecycle contract)
- Richards's Strava-integration diagnostic + escalation path
- Weiss's rc2 finish-screen coordinate spec + safety callouts
- Amber's rc2 acceptance criteria (§A–G, 30+ bench scenarios)
- Laughlin's PR #79 implementation (GPS, discard/save, finish, battery, mirror)
- Killian's `swift-comment-hygiene-checklist` (docs standards)

**New Skills Locked (rc2):**
- `hkworkoutroutebuilder-lifecycle-watchos` (Laughlin) — route-builder lifecycle, location filtering, discard semantics
- `terminal-path-data-leak-qa` (Amber) — 4 invariants, 6 bench checks, grep list, privacy gate pattern
- `third-party-fitness-platform-integration-triage` (Richards) — Strava auto-import filter model, escalation paths, diagnostic ordering
- `activelook-hud-rendering` updated (Weiss) — CRITICAL right-justifying + validate-X-extent

**Release Mechanics (rc2):** Bundle 32 → 33, MARKETING_VERSION stays 0.4.0 (fix-rc), tag v0.4.0-rc2 on merge.

**Updated:** 2026-05-20T14:50:00Z by Scribe (post-rc2-batch-complete session)
