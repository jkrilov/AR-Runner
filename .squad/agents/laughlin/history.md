# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings


## Summary

**Archive:** Pre-rc12 development (rc5-rc11) documented in history-archive.md. Key patterns:
- rc5–rc8: 4-release blank-screen saga (power-on, write serialization, queryID, cfgSet). All fixes load-bearing.
- rc9: Polish (rotation 0→2, holdFlush wrap). Went blank on bench.
- rc10: Bisect (reverted rotation, kept holdFlush). Text upside-down but readable.
- rc11: Tried rotation=4. Went blank. Directive issued: bundle version bump into feature PRs.

**Active sessions: rc12+**

### 2026-05-19T15:55:00Z — rc12: Four-Constant Coordinate Fix + Bundled-Bump Release Pattern Validated

**Work:** Shipped v0.3.0-rc12 fixing rotation=4 coordinate placement bug uncovered by textrotation forensic research. Updated 4 Layout constants (leftMargin 20→284, timeY 40→166, distanceY 120→86, paceY 200→6) in single PR #71 COMBINED with version bump (26→27), xcodegen regen, and Info.plist placeholder check — all committed together per Joe's bundled-bump directive.

**Outcome:** 154/154 Core tests pass. TestFlight upload succeeded. Tag v0.3.0-rc12 released.

**Pattern validation:** First release using Joe's bundled-bump pattern (feature + version bump in same PR, no separate follow-up bump PR). Cuts release cycle from 2 PRs to 1, no wasted merge round. End-to-end validated.

**Key learning:** Coordinate errors and firmware rejections have different diagnostic signatures. Off-screen clipping per spec §5.5.6 is silent (no 0xE2 error), but rotation + anchor corner interactions are subtle. When text goes blank, check bounding box vs. framebuffer bounds before escalating to firmware hypothesis.

### 2026-05-19T22:25:00Z — rc17: Workout-Stop Keeps BLE Link Up, Finish-Screen Y Recompute, Battery → Phone, MARKETING_VERSION 0.4.0

**Context:** Richards formalized the BLE-link lifecycle contract (ADR-1: user-managed peripheral, not workout-scoped). Joe's rc16 bench report flagged two failures: (1) finish frame disappears, (2) glasses disconnect mid-stop, forcing manual re-pair. Root cause: `WorkoutViewModel.confirmSave` and `confirmCancel` were calling `teardownTransport()` immediately after (or instead of) pushing the finish frame, severing the link and wiping the screen.

**Work:** Three coordinated pieces:
1. **Lifecycle fix:** Reordered `confirmSave`/`confirmCancel` to stop per-tick HUD task → push finish frame while HK extended-runtime still held → end HK session → **delete `teardownTransport()` call** (deleted the helper entirely to prevent future re-introduction). User's only explicit disconnect affordance is now the UI-facing `disconnectGlasses()` button per Richards's ADR rule R5.
2. **Finish-screen Y anchor recompute:** Old constants (timeY=166, distanceY=86, paceY=6) were derived under obsolete `y_fb = 206 − T` formula (pre-rc16). rc16 introduced canonical formula `y_fb = 255 − wearer_top`. Walked the old layout through new formula and found distance text 57 px off bottom of panel (clipped). Recomputed:
   - finishBannerY = 239 (wearer-top 16)
   - finishTimeY = 159 (wearer-top 96)
   - finishDistanceY = 79 (wearer-top 176)
   - Result: symmetric, even 16-px gaps, fully on-panel. Old names deprecated with compiler nudges.
3. **Battery → iPhone:** `WCMessage` schema v3 adds `glassesBattery(level: Int)` case. Wired through existing three-tier `transmit(..., preferQueued: true)` helper (queued, survives transient disconnect). Phone shows battery via `GlassesBatteryIcon` (SF Symbol, red/orange/green) in `WorkoutMirrorView` above metrics. **Phone-optional contract:** silent no-op if phone unreachable.

**Release mechanics:** `project.yml` bundle 31→32, `MARKETING_VERSION` 0.3.0→0.4.0, Info.plist placeholders verified untouched. Tag v0.4.0-rc1. TestFlight upload queued (automatic per Joe's directive).

**Tests:** 186/186 Core pass (baseline 176; +10 from filter/backoff/schema, +2 from finish-screen Y pins). New tests pin Y-anchor formula AND on-panel invariant. Per-frame wire-byte assertion guards against coordinate-order regression. `xcodebuild` ARRunnerWatch build SUCCEEDED.

**Key learning:** The user mental model for paired peripherals is "they stay paired until I explicitly unpair." Making AR glasses uniquely tear themselves down on "finish run" violates principle-of-least-surprise and breaks the finish-screen UX. The rc16 bench regression ("connection drops on stop, I have to re-pair") is exactly that violation. rc17 fixes it by keeping the link up and letting the user read the finish stats at their own pace.

**Pattern: Bundled-bump release.** Feature + version bump + tag in single PR, merged once, TestFlight upload automatic post-CI-green. Cuts release cycle from 2+ PRs to 1, no manual coordination. Fifth release using this pattern (rc12–rc17); proven reliable.

---

---

### Cross-Agent Note (via Scribe, 2026-05-19)

**From Richards's rc13→rc16 review:**
- **Recommendation #1:** Revalidate the finish-screen Y anchors (timeY=166, distanceY=86) under the rc16 formula `y_fb = 255 − wearer_top`. They were derived under the obsolete `y_fb = 255 − T − font_height` formula. They happen to render OK on bench, but may be off by a font-height. A 30-minute pass with the corrected formula closes a known gap.

**Action:** If Joe directs finish-screen revalidation work, you have context. The rc16 formula is now canonical (`y_fb = 255 − wearer_top`; **no font-height subtraction**). The corrected ALooK font-height table: F1=24 / F2=38 / F3=64 / F4=75 / F5=82.

---

### 2026-05-19T18:45:00-04:00 — rc17: workout-lifecycle / BLE / finish / battery

**Branch:** `fix/rc17-lifecycle-finish-battery`. Joe's three tasks: (1) workout-stop must not tear the BLE link down, (2) finish screen actually renders + Y coords revalidated, (3) glasses battery → phone via WatchConnectivity (phone-optional). Tests 178/178 green (+2 from finish-screen pinning).

**Key learnings to internalize:**

1. **Workout lifecycle ≠ peripheral lifecycle.** rc13→rc16 conflated them — `confirmSave/Cancel` were calling `teardownTransport()` because the watch app's mental model was "the workout owns the link." Joe's directive (and Richards's ADR) splits them: workouts are HK + UI state; the link is a user-managed peripheral session. Workout-stop is now: (a) stop runtime tasks BEFORE push (so live HUD can't race the summary), (b) push the finish frame while HK is still alive (foreground runtime + radio guaranteed), (c) end HK, (d) leave the BLE link up — the user disconnects explicitly when done. Delete `teardownTransport()` outright so a future agent can't re-introduce the bug structurally.

2. **Finish-screen Y revalidation pattern under rc16 formula.** Old `timeY/distanceY/paceY` (166/86/6) were derived under `y_fb = 206 − T` (font height subtracted). Under the canonical rc16 `y_fb = 255 − wearer_top` (NO subtraction), `paceY=6 → wearer_top 249 → bottom 313` = 57 px off-screen for a font-3 line. The disconnect-on-stop bug hid this for 4 RCs because the link tore down before anyone could inspect the finish screen. Lesson: when the rendering surface changes "from coincidentally-on-screen to persistently-inspected-by-Joe," every coordinate derived under a superseded formula needs a re-walk. Recomputed: `finishBannerY=239 / finishTimeY=159 / finishDistanceY=79` (wearer T=16/96/176, 16-16-16 margins, even 16-px gaps). Renamed to surface-scoped names (Richards's rec #3 — old `paceY` was rendering DISTANCE text, the name lied). Old names retained as `@available(*, deprecated, renamed:)` aliases. Pin both the literal values AND the formula (`finishTimeY == 255 - 96`) so an edit that touches one without the other trips CI; also pin the per-frame y-anchor in a wire-byte-decoding test so a banner/time/distance order swap is caught.

3. **WatchConnectivity phone-optional pattern.** For low-frequency low-stakes data (battery, ambient stats), `transferUserInfo` is the right tier — queued, survives transient disconnect, OS wakes the receiver, no blocking on `isReachable`. `sendMessage` is wrong (requires reachable); `updateApplicationContext` is close but doesn't wake the receiver via a delegate callback. The phone-optional contract falls out **for free** from `WatchConnectivityService.transmit(..., preferQueued: true)` because the helper already silent-no-ops when the session is unactivated/unreachable. Watch-side flow: subscribe to glasses event stream → on `.batteryLevel(level)` event call `mirror?.sendGlassesBattery(level)` (the `?` is the phone-optional safety net). Phone-side flow: `WorkoutMirrorViewModel.glassesBatteryLevel: Int?` starts nil; only updated on first `didReceiveUserInfo`. The "nil" state is the source of truth for "no value yet" — no fake "100%" placeholder.

4. **Bundled-bump v4 (rc17 — first cross-MARKETING_VERSION application).** `project.yml` bumped 31→32 AND `MARKETING_VERSION` 0.3.0→0.4.0 in the same PR as the feature work. The pattern (skill `release-mechanics-bundle-bump`) is unchanged from rc12-16 application except: when MARKETING_VERSION rolls, the next tag is `v0.4.0-rc1` (rc counter resets), not `rc17`. xcodegen produced no `.pbxproj` delta — only the project.yml line moved — because the build settings are sourced from xcconfig placeholders. The Info.plist placeholders (`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`) verified preserved per the skill's gotcha #2.

5. **Coordination via inbox decision files (parallel agents).** Weiss owned the BLE-adapter half (battery service discovery, characteristic subscription + initial read so we don't wait 30 s for the first value, event emission). I owned the consumer side (`WorkoutViewModel` event handler, `WCMessage` schema, `WatchConnectivityService` send, phone-side ViewModel + View). We never touched each other's files — `git status` confirms a clean ownership boundary in the diff. Richards filed his ADR `richards-adr-ble-link-lifecycle.md` in parallel; Amber filed QA scenarios `amber-rc17-qa-scenarios.md`. The pattern works: contract negotiated in a brief, individual decision files filed concurrently, Scribe merges. No agent-to-agent direct messaging needed.

