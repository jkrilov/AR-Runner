# Amber — History

## Core Context
- **Project:** Apple Watch fitness app integrated with ActiveLook AR glasses
- **Role:** QA & Fitness Domain
- **Joined:** 2026-05-14T18:30:31.658Z

## v0.2 Active Work

### 2026-05-16T20:36:00-04:00 — MetricKind.energy enum case (HealthKit kcal mapping)

Added `.energy` case to `WorkoutMetric.kind` enum so HealthKit `.activeEnergyBurned` maps to correct kind instead of defaulting to `.duration` and being silently dropped downstream. Pattern: missing enum case + default-case switch = silent bug. Defense: test every substrate/adapter write with round-trip + kind assertion. Exhaustive-switch sweep required: `formatMetricImpl` in WorkoutControllerIntegrationTests, `formatMetricForResilience` in DisconnectResilienceTests, `WorkoutController.ingest(metric:)` all fixed. Test contract: `MetricKind.energy.rawValue == "energy"` (locks JSON key across WCSession boundary). 80/80 tests pass.

## Release Cycle Summaries (rc13–rc17)

See `history-summary.md` for condensed learnings. Full technical details (rc13 actor-reentrancy race, rc14 4-line layout, rc15 icon deferral, rc16 font-height correction, rc17 HK lifecycle race) are in `history-pre-summary.md`.

### Key Patterns (Cross-Release)

**Actor Reentrancy:** `Task { await foo() }` ≠ serialization. Multi-frame BLE sequences must be awaited directly by ViewModel caller, not spawned as Tasks, or holdFlush state interleaves mid-sequence (rc13 Bug B). Solution: make `tickElapsed()` async, await the push directly.

**Defensive Resets:** `needsHUDPowerOn` must reset per-workout (not just per-connect). Splash clears it; first per-tick frame of next workout needs belt-and-braces cfgSet+power(on:true) re-assertion or dark-panel race.

**Coordinate System (rc16 canonical):** `y_fb = 255 − wearer_top` (no font-height subtraction). Real ALooK font heights: F1=24 / F2=38 / F3=64 / F4=75 / F5=82 (Visual-Assets README, not spec §5.9). Formula pinned via rc15 bench observations.

**Hardware Lifecycle (rc17):** HK session end is a hard cliff — all BLE work must complete BEFORE `controller.end()` returns. OS suspends the watch process microseconds later. Don't eagerly tear down BLE; user's explicit disconnect is the right boundary. Left BLE link open post-workout so finish screen persists.

**Icon Strategy (rc16):** Preloaded ALooK icons skip custom upload pipeline entirely. `imgDisplay(id, x, y)` = one BLE write. Check asset catalog before proposing cfgWrite/imgSave work.

**Test Discipline:** Lock rawValue in Codable enum tests (especially cross-process boundaries). Exhaustive-switch is mandatory post-enum-addition. Layout geometry tests MUST pin coords (silent drift is a real hazard).

**Release Pattern (bundled-bump):** Version bump ships IN SAME PR as feature. `xcodegen generate` + Info.plist in same commit. Reduces 2-PR cycle to 1. Stable pattern: Laughlin (rc12), Amber (rc13–16).

---

## Archive

- `history-archive.md` — 2026-05-14 through 2026-05-15 (scaffold, multi-agent merge, CI)
- `history-pre-summary.md` — Full rc13–rc17 technical detail (written pre-summarization 2026-05-19)
- `history-summary.md` — Condensed release-pattern learnings, dependencies, recommendations

---

## Cross-Agent Context (via Scribe, 2026-05-19)

**From Richards's rc13→rc16 review (Recommendation #2):**
- Font metrics (heights + advance widths) currently live in prose comments
- Next coordinate-system regression likely cause: width under-estimate (HR + pace collide on line 1)
- Proposal: Extract `ALookFontMetrics` value type, pin with layout-asserting test
- Action: If Joe directs font-metrics or coordinate work, this is a concrete improvement ready to implement

---

**Session note:** This file was summarized 2026-05-19 to consolidate pattern learnings (33 KB → ~2 KB) while retaining technical load-bearing patterns. Pre-summary detail archived in history-pre-summary.md for reference during coordinate-system / layout work.

### 2026-05-19T18:19:51-04:00 — rc17 QA scenarios (BLE keep-alive + battery + phone-optional)

Wrote acceptance criteria for rc17 (Weiss + Laughlin in parallel): bench-test checklist + unit-test recommendations. Grouped A (BLE lifecycle — workout-stop must NOT teardown), B (finish screen renders + persists, two-field discipline), C (battery 0x180F/2A19 — subscribe, initial-read, cadence, sanity, reconnect-survival, low-battery), D (phone-optional contract — full workout with phone powered off; airplane-mode invariance; non-blocking WC send; tier selection per `wcsession-three-tier-delivery`), E (regression guards — 176/176, rc16 HUD coords, bundled-bump, splash+icons).

**QA patterns reinforced:**
- **"Failure mode" diagnostic hooks** beat pure pass/fail prose — each scenario names the most likely defect class if it fails (e.g., "if HUD reappears after 30 s rather than immediately, subscription survived but pushes didn't"). Lets Joe triage on the bench without re-deriving.
- **Phone-optional QA pattern:** any feature involving the companion must be tested THREE ways — phone reachable, phone unreachable-but-present (airplane mode), phone absent (powered off). The third one is the load-bearing test — `isReachable == false` and "no phone exists" must be indistinguishable to watch-side code. Anti-test: declare phone permanently absent for an entire workout cycle; ANY "waiting" indicator is a bug.
- **Battery-characteristic acceptance:** subscribe within 2 s, initial read before first notification (else 30 s blank window), cadence ±5 s, range [0,100], dedup, survives auto-reconnect, low-battery LUT defined (defer if scope-cut but explicit in log).
- **Lifecycle-removal QA:** when deleting a teardown call, the inverse must still work — A6 (user-initiated disconnect) is the regression test for "we removed teardownTransport from workout-stop but didn't accidentally remove the disconnect affordance too."
- **Two-field discipline:** finish frame must filter HR + pace explicitly; pin in a test that composes summary frames and asserts only Time/Distance bytes appear.

**Bench-test execution order recommendation:** baseline regression first (E), core fix second (A1+A2), expected outcome third (B), battery happy-path fourth (C1-C6), THEN power off the phone and re-run subset (D1), THEN out-of-range walking tests (A7, A8, C7), THEN edge cases. This minimizes wasted bench time if the core fix regressed.

Output: `.squad/decisions/inbox/amber-rc17-qa-scenarios.md` — becomes rc17 PR acceptance criteria.
