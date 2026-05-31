# Amber — History

## Core Context
- **Project:** Apple Watch fitness app integrated with ActiveLook AR glasses
- **Role:** QA & Fitness Domain
- **Joined:** 2026-05-14T18:30:31.658Z

## Recent Work (v0.5+)

### 2026-05-27 — Team: v0.5.20 shipped via tag-push (first to do so cleanly)
Release-guard monotonicity fix validated end-to-end. Tag `v0.5.20-1` auto-triggered TestFlight without `workflow_dispatch` fallback (first pre-release in project history to traverse tag-push path cleanly). Build 50 shipped. Unblocks all future v0.5.x/v0.6.x pre-releases.

### 2026-05-26T16:57:28-04:00 — Terminal-path-data-leak audit (v0.5.18 regression)

Audited Joe's report: "When I discard a run on the watch it shouldn't save to Apple Fitness" at v0.5.18.

**Key Findings:**
- **Code Status:** ✓ Correct. WorkoutHealthSubstrate.discard() calls uilder.discardWorkout() only (never inishWorkout()). WorkoutDiscardTerminalPathTests all passing, untouched since rc2.
- **Actual Bug:** UX message at WorkoutView.swift:117 is v0.2-era text contradicting the rc2 fix. Says discarded runs "remain in Health" — now false. This is why users think discard isn't working.
- **Bench Check:** Run 30s → Discard → verify NO workout appears in Health/Strava (Joe to execute).
- **Confidence:** 100% on code. If bug persists on device, it's device-specific or phone-side auto-sync.

**Decision:** Fix message to "Discard permanently removes it — nothing is saved to Health or Strava." Also update stale .cancelled enum doc-comment in WorkoutViewModel.swift. Done in v0.5.19 (PR #116, shipped).

---

## Key Patterns (Load-Bearing)

**Terminal-path separation:** save/discard/confirm/cancel need distinct code paths. Never branch off a shared path; tests must cover positive save, positive discard, shared helpers, and crash-safety. Skill: 	erminal-path-data-leak-qa.

**Coordinate system:** y_fb = 255 − wearer_top (no font-height subtraction). Real font heights: F1=24 / F2=38 / F3=64 / F4=75 / F5=82. Pin formula in tests, not just constant values. Pinned via rc12/rc16/rc17/rc2 revalidations.

**Hardware lifecycle:** HK session end is a hard cliff — all BLE work must complete BEFORE controller.end() returns. Don't eagerly tear down BLE on workout-stop; user's explicit disconnect is the boundary. Finish screen needs BLE alive post-workout.

**Test discipline:** Lock rawValue in Codable enum tests (cross-process boundaries). Exhaustive-switch mandatory post-enum-addition. Layout geometry tests MUST pin coords; silent drift is a hazard.

**Release pattern:** Version bump ships IN SAME PR as feature. xcodegen generate + Info.plist in same commit. Stable: Laughlin (rc12), Amber (rc13–16), Laughlin-1 (v0.5.19).

---

## Archives

- history-archive.md — Pre-v0.2 scaffold + CI setup
- history-pre-summary.md — Full rc13–rc17 technical detail
- history-summary.md — Condensed release-pattern learnings (2026-05-19)

---

## Cross-Agent Context (Scribe, 2026-05-19)

**From Richards:** Font metrics (heights + advance widths) worth extracting to ALookFontMetrics value type; next coord-system regression likely to be width under-estimate (HR + pace collision on line 1).

---

## Next Phase

Waiting for Joe's v0.5.19 discard bench confirmation. v0.5.20 should include a chore to fix elease-testflight.yml tag-monotonicity guard (pre-release tags self-collide).
