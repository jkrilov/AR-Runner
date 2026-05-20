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

### 2026-05-20T10:42:31-04:00 — rc2 QA scenarios (post-rc1 bench: route + Strava + finish-rework + discard-leak + mirror start-time)

Wrote acceptance criteria for rc2 covering Joe's five bench-return items from the 2026-05-20 real-5k run on v0.4.0-rc1. Output: `.squad/decisions/inbox/amber-rc2-bench-feedback-qa.md`. Sections A (route recording — HKWorkoutRouteBuilder + CLLocationManager lifecycle), B (Strava ingestion — pending Richards's diagnosis, scenarios written to span options a/b not c), C (3-line finish screen rework — Finished! / distance / time-LEFT pace-RIGHT), D (🚨 discard-gating — the data-integrity item), E (phone mirror start-time + WCMessage v3→v4 compat), F (regression — rc17 contracts, 186/186 floor, bundled-bump 32→33), G (bench execution order, severity-first).

**QA patterns reinforced / new:**

- **Terminal-path bifurcation as a QA invariant.** rc1's discard-leak (confirmCancel hit save path) generalizes: any save/discard, submit/cancel, commit/rollback fork needs four pinned tests (positive save → only save; positive discard → only discard; shared helpers → neither; process-kill during confirm → discard). Extracted as new skill `terminal-path-data-leak-qa`. The diagnostic is asymmetry of attention: after Save users look for data, after Discard they look away — so the leak hides.

- **Privacy-incident escalation path.** When the leaky store auto-syncs downstream (HK→Strava, drafts→sent, local→cloud), a discard-leak becomes a privacy incident. rc2 §B3 (discarded run does NOT appear in Strava) is the load-bearing privacy test for AR-Runner; same shape applies anywhere persistence has an auto-sync edge.

- **Secondary-builder leak shadow.** HK route builder is a sibling persistence boundary to the workout builder; the discard-path bug almost certainly has a route-builder twin (D2 catches this). Generalizes: every persistence boundary has its own bifurcation invariant; tests on the primary don't cover the secondary.

- **Right-alignment math forces font-metrics extraction.** rc2 §C4 (time LEFT + pace RIGHT on one line) requires computing `paceX = leftMargin + textBoxWidth − textWidth(paceString, font)`. This is the forcing function for Richards rec #2 (`ALookFontMetrics` typed table). Pinning the test pre-implementation means Laughlin can't ship without either the table or a hand-rolled equivalent that the test will lock against.

- **WC schema-bump backwards-compat test as load-bearing.** WCMessage v3→v4 means a phone on the older build will receive an unknown case. The decoder MUST treat unknown as no-op (not throw, not crash, not break the message loop). E6 is the canonical test; same pattern applies to any versioned wire format crossing a process boundary (`MetricKind.energy` rawValue lock from v0.2 was the same shape).

- **Permission-deny as a "feature still works" test, not just a "no crash" test.** A2 asserts that denying location permission lets the workout still record distance/HR/time without route — the failure mode is over-broad gating (`guard authStatus == .authorizedWhenInUse` at session-start instead of at route-recording only). Pattern: any optional capability's deny path is a feature-still-works test; "no crash" is necessary, not sufficient.

- **Bench execution order = severity-first, with a 60-second smoke at #1.** D1 is the rc2 60-second smoke (start → 30 s → discard → check Health). If D1 fails, halt the bench. Matches the rc17 pattern of leading with the load-bearing scenario before any wider sweep.

Skill extracted: `terminal-path-data-leak-qa/SKILL.md` (four invariants + six bench checks + anti-pattern grep list + reuse contexts).
