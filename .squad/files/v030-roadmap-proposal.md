# v0.3.0+ Roadmap Proposal

**Killian — Product Strategist**  
**Date:** 2026-05-18  
**For Review:** Joe Krilov

---

## TL;DR

v0.3.0 **must** address two hard blockers from v0.2.0 device testing and code audits: **(A)** `CKWorkoutBackgroundTask` so watches don't pause runs when the screen sleeps, and **(B)** AR HUD glyph rendering so the glasses aren't dead weight post-pairing. Suggested scope: Background Runtime (A), AR HUD MVP (B), plus one nice-to-have (Run History or Haptic Alerts). This keeps v0.3.0 focused, unblocks actual 30+ min runs, and ships real AR value. Themes below—pick your 2–3 + rationale, then we lock it.

---

## 1. Known Backlog Items

From agent audits, device testing, and v0.2.0 closure:

### LAUGHLIN (P0) — Background Workout Runtime

**Problem:**  
Watch app currently uses deprecated `UIBackgroundTaskIdentifier` for workout processing. When the watch screen sleeps (normal during a run), the app loses background runtime and workouts pause or terminate. v0.2.0 device testing confirmed this — any run longer than a few minutes hits the sleep timeout.

**Blocking:**  
Can't ship a real running app without this. Every 30+ minute run dies mid-activity.

**Fix:**  
Replace `UIBackgroundTaskIdentifier` with `CKWorkoutBackgroundTask` (WatchKit runtime API available in watchOS 9+). This gives the watch app dedicated background time while a `HKWorkoutSession` is active, independent of screen state.

**Estimated effort:** M (requires protocol update to `WorkoutController`, background-task lifecycle management, testing across wake/sleep transitions)

---

### WEISS (P1) — AR HUD Glyph Rendering

**Problem:**  
PR #42 completed pairing/connection flow but stopped short of actual HUD rendering. `GlassesService.updateField()` now wires metric ticks to the glasses (P1.2 fix), and placeholder device IDs are guarded (P1.4 fix), but the ActiveLook SDK call chain never actually draws glyphs (pace, HR, distance, time) on the Engo 2 display.

**Blocking:**  
User pairs glasses pre-run, sees the "Connected" status, starts workout, then glances at glasses and sees... nothing. The AR feature is inert.

**Fix:**  
Wire the actual glyph rendering (or dot-matrix) calls in `ActiveLookGlassesAdapter.selectLayout()` + `updateField()` to paint metrics on the display. Minimal MVP: 4 slots (pace, HR, distance, time) matching the watch HUD.

**Estimated effort:** M (requires real hardware testing with Engo 2; SDK integration for glyph APIs; probably 1–2 spike days + 3–4 implementation days)

---

## 2. Candidate Themes for v0.3.x

### Theme A: Background-Stable Run Tracking

**Description:**  
Replace deprecated background-task API with `CKWorkoutBackgroundTask`; ensure watch stays active during entire workout, independent of screen sleeps. No more 5-min cutoffs.

**Owner:** Laughlin (watchOS)  
**Effort:** M  
**Dependencies:** None (protocol-only change to `WorkoutController`)  
**User Story:** "I start a 30-min run, my watch screen sleeps at 2 min, but the app keeps recording until I tap Finish."

---

### Theme B: AR HUD MVP — Basic Glyph Display

**Description:**  
Wire glyph rendering on ActiveLook glasses. Paint pace, HR, distance, time on Engo 2 display during a run at ~1Hz cadence.

**Owner:** Weiss (AR/glasses)  
**Effort:** M–L (spike + hardware iteration)  
**Dependencies:** Theme A (background task) not strictly required, but recommended (smoother testing if watch doesn't drop mid-session)  
**User Story:** "I pair my glasses, start a run, glance at them, and see my pace + HR live."

---

### Theme C: Run History View on iPhone

**Description:**  
iPhone app gains a "Past Runs" tab showing completed workouts: date, distance, duration, average pace, calories. Read-only, sourced from HealthKit via WCSession sync or direct local query.

**Owner:** Laughlin + Amber (watch subscription + fitness domain)  
**Effort:** M  
**Dependencies:** None (uses existing HealthKit read path + WCSession)  
**User Story:** "I tap iPhone after a run and see all my workouts this week, sorted by date."

---

### Theme D: Haptic Alerts for Pace / Zone Warnings

**Description:**  
Watch emits haptic feedback when runner drops below target pace, exceeds HR zone, or hits distance milestones (every 1 mi). Configurable thresholds via watch-side Settings app.

**Owner:** Laughlin + Amber  
**Effort:** M (haptic generation + threshold tracking + Settings UI)  
**Dependencies:** None (pure watch-side logic)  
**User Story:** "My watch taps my wrist if I slow down too much, keeping me accountable during a run."

---

### Theme E: Split / Lap Tracking on Watch

**Description:**  
Track splits by distance (every 1 mi) or by time (every 5 min). Display splits on post-run summary; optionally show split pace + best/average pace on the live HUD during a run.

**Owner:** Laughlin + Amber  
**Effort:** M–L (derived metric calculation + persistence + HUD slot management)  
**Dependencies:** Theme A (background task ensures full capture) and Theme B (HUD MVP to have space for split display)  
**User Story:** "After a 5-mile run, I see my mile splits on the watch summary and know where I faded."

---

### Theme F: iPhone Settings / HUD Layout Customization

**Description:**  
iPhone gains a "HUD Layout" settings screen. User can reorder/hide the 4 core metrics (pace, HR, distance, time), or pick from preset layouts (Minimal: pace+HR / Detailed: all 4 + split pace). New layout syncs to watch + glasses on next workout start.

**Owner:** Laughlin + Weiss  
**Effort:** L (layout serialization + sync protocol change + glasses re-render on layout change + validation tests)  
**Dependencies:** Theme B (HUD MVP must be stable before adding customization)  
**User Story:** "I customize which metrics show on my glasses via the iPhone app; during my next run, my glasses HUD reflects my choice."

---

### Theme G: Run Export to Strava / Apple Health / GPX

**Description:**  
Post-run, user can tap "Export" and choose format (GPX, TCX, Strava upload). Enrich saved `HKWorkout` with route data (currently just summary); generate portable files.

**Owner:** Laughlin + Amber  
**Effort:** L (Strava API integration, GPX/TCX format generation, OAuth handling, route reconstruction from HK samples)  
**Dependencies:** Theme C (need post-run history view as the export surface)  
**User Story:** "After a run, I export to GPX and upload it to Strava; my friends see my activity."

---

## 3. Suggested v0.3.0 Scope (2–3 Themes)

### Recommended: Theme A + Theme B + (Theme C or D)

**Rationale:**

1. **Theme A (Background Runtime)** — P0 blocker. v0.2.0 device testing proved the app dies on long runs. Shipping v0.3.0 without this is shipping a broken product. Must include.

2. **Theme B (AR HUD MVP)** — P1 blocker. Users pair glasses, feel invested, then discover they're inert. AR is your differentiator vs. standard watch workout apps. At least basic glyph rendering (pace, HR, distance, time) before shipping v0.4.0. Must include to justify the glasses integration.

3. **Theme C or D (Pick One):**
   - **Theme C (Run History):** Closes the loop on post-run reflection. Cheap to implement (no new HealthKit reads, just UI); provides obvious value (users want to see their workouts). Low risk.
   - **Theme D (Haptic Alerts):** High engagement; turns watch into a coach. Slightly more effort (threshold logic, Settings UI), but pure watch-side—no AR complexity or cross-device sync. Medium risk, high reward.

**Recommendation:** Start with Theme A + B as hard requirements, then pick C or D based on Joe's testing priority. Theme C (history) feels more "app complete"—users expect to review past runs. Theme D (haptics) is more "power user"—rewarding for engaged runners but less critical for v0.3.0's MVP.

---

## 4. Out of Scope for v0.3.0 (Deferred to v0.3.5, v0.4.0+)

| Theme | Reason |
|-------|--------|
| **Theme E (Splits)** | Requires Theme A + B stable first; adds complexity to HUD slot management. Post-v0.3.0. |
| **Theme F (Layout Customization)** | Requires Theme B (HUD MVP) + stable glasses connection. Low priority until core metrics proven. v0.4.0. |
| **Theme G (Export/Strava)** | Nice-to-have; requires OAuth + API integration. v0.4.0+. |
| Multi-sport support | Locked running-only (D3). v0.5.0+. |
| Offline map / live route on phone | Out of scope (route is "nice-to-have," not core). v0.5.0+. |
| Apple Watch Ultra complication | Feature parity with Series 9 first. v0.3.5+. |

---

## 5. Open Questions for Joe

Before we lock scope, clarify:

1. **Long-run assumption?** When you test v0.3.0, are you doing 30-min runs or 60+ min? Background task urgency depends on this. (If mostly 15-min runs, Theme A can shift to "nice-to-have"; if always 30+, it's P0.)

2. **AR HUD mirror or minimal?** Should glasses HUD mirror the watch UI exactly (pace, HR, distance, time in same order/formatting), or design a minimal Engo 2-optimized layout (e.g., pace + HR only, bigger glyphs)? Affects Theme B scope.

3. **Haptic preference (if choosing Theme D)?** Do you want pace-zone alerts (e.g., "tap if pace > 10:00/mi"), distance milestones (every 1 mi tap), or both? Threshold design.

4. **Test device reality?** Do you have a working Engo 2 glasses + watch pairing set up for Theme B testing, or is that a blocker we need to account for in the spike?

5. **Post-v0.3.0 focus?** Is v0.4.0 planned for Q3 2026, or are you pivoting to multi-sport or other features after v0.3.0 ships?

---

## 6. Effort Rollup & Timeline

**If v0.3.0 = Theme A + Theme B + Theme C:**

| Workstream | Theme | Owner | Effort | Weeks |
|-----------|-------|-------|--------|-------|
| Watch | Theme A (Background Runtime) | Laughlin | M | 1.5–2 |
| Watch | Theme C (History View) | Laughlin + Amber | M | 1–1.5 |
| Glasses | Theme B (HUD MVP) | Weiss | M–L | 1.5–2 (spike + iteration) |
| QA | Integration + device test | Amber | M | 1 |
| **Total** | — | — | — | **4–5 weeks** |

*If Theme D instead of C: ~4–5 weeks (haptic logic slightly heavier than history UI).*

---

## Next Steps

1. **Joe's feedback:** Answer the 5 open questions above.
2. **Scope lock:** Confirm Themes A + B + (C or D).
3. **Kickoff:** Once locked, Laughlin + Weiss begin Theme A spike (background runtime investigation) while Killian + Laughlin sketch Theme C/D UI.
4. **v0.3.0-rc1 baseline:** v0.3.0-rc1 cut after Themes A + B land + integration tests pass (estimated 2–3 weeks in).
5. **Device test:** Joe runs multi-week real-world testing; feedback informs v0.3.1–v0.3.5 point releases.

---

**End Proposal**  
*Awaiting Joe's review + answers to open questions. This proposal will iterate based on feedback.*
