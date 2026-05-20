### 2026-05-20T14:50:00Z — Session: rc2-bench-feedback-fixes (v0.4.0-rc2)

**Session ID:** 2026-05-20T14-50-00Z-rc2-bench-feedback-fixes  
**Scope:** rc2 — Five items from Joe's morning 5k bench run on v0.4.0-rc1 TestFlight  
**Outcome:** ✅ v0.4.0-rc2 shipped as PR #79 (auto-release to TestFlight on merge)  
**Agents Deployed:** 4 (Richards, Weiss, Amber, Laughlin) + Coordinator  

---

## Flow Summary

**User Input:** Joe Krilov reported 5 defects / feature gaps from live 5k run:
1. GPS not recorded (no route on workout)
2. Strava ingestion broken (runs not flowing Health → Strava)
3. Finish screen layout too crowded (banner + distance + time line overflow)
4. **Data integrity regression:** Cancel workout was persisting to Apple Health (discarded workouts appearing)
5. Phone mirror missing "Started at HH:MM" row

**Coordination:** Spawn manifest dispatched 4 agents in parallel:
- **Richards (Lead/Architect):** Diagnostic on Strava gap — determined items #1 & #2 are **single bug** (missing HKWorkoutRoute couples to GPS)
- **Weiss (AR Integration):** rc2 finish-screen coordinate spec + safety callouts for Laughlin
- **Amber (QA):** Acceptance criteria (§A–G) + 30+ bench scenarios + terminal-path-data-leak pattern
- **Laughlin (watchOS):** Implementation of all 5 items → PR #79

**Key Discovery:** Richards's diagnostic revealed items #1 (GPS) and #2 (Strava) **are the same subsystem failure**, not two separate bugs. Fixing GPS recording likely unblocks Strava ingestion for free.

**Critical Fix:** Item #4 (data-integrity regression from rc17 reorder) required **terminal-path bifurcation** — separate `discard(...)` from `end(...)` in the health substrate to prevent confirm-cancel from persisting incomplete workouts. This was the highest-severity issue.

---

## rc2 Implementation (Laughlin / PR #79)

**GPS Route Recording (Item #1):**
- CLLocationManager integrated into HealthKitWorkoutSubstrate (kCLLocationAccuracyBest, .fitness activity type)
- HKWorkoutRouteBuilder constructed at begin(...), location fixes filtered (accuracy > 50m), finalized at end(...)
- Discard path explicitly skips finishRoute (no route leak)
- NSLocationWhenInUseUsageDescription added to watch Info.plist via project.yml

**Finish Screen Reshape (Item #3):**
- 3-line layout: Finished! / distance / time+pace
- Line 1–2 keep font 3; line 3 drops to font 2 for dual-metric fit
- Y coordinates 239/151/63 derived from canonical lens-flip formula (unchanged from rc17 names)
- ALookFontMetrics extracted per Richards recommendation
- Right-justify approach (b): two separate `txt` writes per line with fixed finishPaceX=180

**Discard-vs-Save Bifurcation (Item #4 — Data Integrity):**
- New WorkoutHealthSubstrate.discard(at:) method (protocol + all implementations)
- WorkoutViewModel.confirmCancel routes to controller.discard(), not controller.end()
- HealthKitWorkoutSubstrate.discard() calls builder.discardWorkout() + session.end() with NO finishWorkout/finishRoute
- WorkoutDiscardTerminalPathTests pins regression: save → end 1× never discard; discard → discard 1× never end

**Phone Mirror Started Row (Item #5):**
- WorkoutTickMessage.startedAt (optional Date) carried on every tick
- WC schema v3 → v4 (backward-compat: v3 snapshots decode, fallback to timestamp − elapsedSeconds)
- Phone-side row added with checkered flag SF Symbol + short DateFormatter

**Release:** Bundle 32 → 33, MARKETING_VERSION stays 0.4.0, tests 186 → 195 (+9), xcodebuild succeeded, CI ready.

---

## New Skills & Patterns

1. **hkworkoutroutebuilder-lifecycle-watchos** (Laughlin) — CLLocationManager lifecycle coupling, route-builder finalization contract, discard semantics
2. **terminal-path-data-leak-qa** (Amber) — 4 invariants + 6 bench checks + grep list + privacy gate pattern (reusable for future discard/save bifurcations)
3. **third-party-fitness-platform-integration-triage** (Richards) — diagnostic framework for health-app → third-party bridge gaps (Strava auto-import filter model, escalation paths, cheap-fix-first ordering)
4. **activelook-hud-rendering** updated (Weiss) — CRITICAL right-justifying on shared line + validate-X-extent coverage

---

## Strava Item (#2) — Dependent on Item #1

Richards confirmed: **Strava ingestion gap is NOT a separate Strava-side toggle issue** (Joe's apple-workout app runs DO sync to Strava). The gap is item #1 (GPS route recording). Once Laughlin's fix lands and Joe re-runs a bench 5k, Strava ingestion re-tested; high confidence both clear together.

Escalation path documented if cheap fix doesn't work: verify route in Health app, force Strava re-poll, then investigate source-app filter hypothesis.

---

## Risk & Validation

**Highest Risk:** Line 3 right-justify gap math (4 px worst-case) — Weiss spec pinned with invariant test; bench-test required on live hardware before rc2 release.

**Test Additions:** 9 new unit tests (186 → 195 core); Amber's terminal-path-data-leak pattern directly instantiated.

**Bench Coverage:** 30+ scenarios documented (Amber); Joe runs live device validation before merge approval.

---

## Coordination & Handoff

- **PR #79 ready for:** Code review (Killian or Lead) → merge (auto-releases to TestFlight on CI green)
- **Joe's bench run:** D1 discard smoke test FIRST (data-integrity gate), then GPS+Strava 2-for-1 verification, finish screen visual, phone Started row
- **README update pending:** Killian notified that item-level features have evolved (see Task 5)

---

**Metadata:**
- Spawn time: 2026-05-20T10:42:31-04:00 UTC
- Session duration: ~18 minutes (Laughlin heavy-lift agent)
- Deliverable: PR #79 on branch rc2/v0.4.0-rc2-bench-feedback, +983/−184, 15 files
- Auto-release: On CI green + PR merge
- Next gate: Joe's bench validation (D1 discard first, then feature parity)
