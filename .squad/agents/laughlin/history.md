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


### 2026-05-20T11:00:00-04:00 — rc2 (v0.4.0-rc2): Joe's 5K bench-feedback bundle (4-of-5 items, Strava parallel)

**Context:** Joe ran a real 5K with the rc1 (v0.4.0-rc1) build. Five issues; I owned items 1, 3, 4, 5; Richards owned 2 (Strava) in parallel. Single bundled-bump PR per Joe's standing directive.

**Key learnings:**

1. **xcodegen `Config/` is gitignored — Info.plist edits must go in `project.yml properties`, not the plist itself.** I edited `Config/ARRunnerWatch-Info.plist` directly first; the change vanished because the file is regenerated from `project.yml` on every xcodegen run AND because the whole Config/ directory isn't tracked. The correct surface is `targets.ARRunnerWatch.info.properties.NSLocationWhenInUseUsageDescription: ...`. Without that, `CLLocationManager` silently rejects every fix on watchOS and `HKWorkoutRouteBuilder` stays empty — exactly the missing-polyline bug Joe saw on the 5K. **Rule for future Info.plist additions: always touch project.yml first, never the generated plist.** (Pinned in skill `release-mechanics-bundle-bump` gotcha follow-up.)

2. **Terminal-path data integrity: discard MUST be a distinct substrate method, not a branch off save.** The rc17 `confirmCancel` reorder kept calling `controller.end()` because the protocol had no discard verb — only end. So even though the UI branched to `.cancelled`, the substrate still ran `builder.finishWorkout()` and wrote the `HKWorkout`. The fix is structural: add `WorkoutHealthSubstrate.discard(at:)` as a required protocol method, implement it as `session.end()` + `builder.discardWorkout()` (no `finishWorkout`, no route finalize), and route `confirmCancel` through a new `controller.discard()`. No "save then maybe delete" — that branch leaks partial data if delete fails. Tests assert the negative: discard path NEVER calls substrate.end; save path NEVER calls substrate.discard. Pinning the **absence** of a call is the discriminator that catches future regressions of this class. Amber landed `terminal-path-data-leak-qa` SKILL.md in parallel that captures exactly this pattern.

3. **HKWorkoutRouteBuilder lifecycle is workout-scoped, not session-scoped.** `HKWorkoutRouteBuilder` must be created in `begin(...)` (so it captures fixes from start), fed from `CLLocationManagerDelegate.didUpdateLocations` via `insertRouteData(_:)` (filter horizontalAccuracy out-of-range / negative per Apple docs), and finalized via `finishRoute(with: workout, metadata: nil)` **inside `end(...)` AFTER `builder.finishWorkout()` resolves with the persisted HKWorkout**. The finishRoute call associates the polyline with that specific workout sample; if you call it before the workout exists, there's nothing to attach to. **discard(...) MUST NOT call finishRoute** — without it, the route samples drop with the builder when it deallocates. This is the discard-vs-save isolation extended to GPS data.

4. **Finish-screen reshape: the two-field encoder rule was a one-RC rule, not a permanent invariant.** rc14 (Richards's call) said "discard HR/pace at the encoder, finish = Time+Distance only." Joe's rc2 directive reshapes to 4 data items / 3 visual lines (banner / distance / time+pace shared row). I superseded the rc14 rule explicitly (documented in the decision file as evolution, not violation) and renamed `finishBannerY/finishTimeY/finishDistanceY` → `finishLine1Y/finishLine2Y/finishLine3Y` because the rc17 names lied about line content under the new layout. Old names kept as deprecated aliases (compiler nudge for anyone who reaches for them).

5. **Right-justify on ALooK txt = measure string width, compute anchor.** ALooK's `txt` (0x37) under rotation=4 (topLR) anchors text in wearer space at the LEFT edge and grows RIGHT (after the lens flip — empirically validated rc12+). There's no native right-justify primitive. For a right-justified field at wearer_right = R, set wearer_left = R − text_width, then map to framebuffer via `x_fb = 303 − wearer_left`. This finally justified extracting `ALookFontMetrics` (height + per-font average glyph width table) per Richards's rc13 nudge — heights live in one place, widths are addressable, and the right-justify formula is one helper call away (`summaryPaceXFB(for:)`). Conservative width estimates work because the HUD strings are ≤ 10 chars and the slack lands inside the panel margins.

6. **Font selection on a shared line: drop to font 2.** Line 3 hosts two metrics (time + pace) on a 304-px panel. At font 3 (~28 px/char) a 5-char time + 7-char pace span ~336 px and collide. Font 2 (~18 px/char) spans ~216 px with ~88 px of clearance. Same trick rc16 used for the live-HUD line 1 (Time+HR shared, `liveLine1Font = 2`). The encoder enforces this via `Layout.finishLine3Font: UInt8 = 2`; tests pin the on-panel + clearance-from-time-column invariant so a future "but it'd look more readable at font 3" tweak trips CI.

7. **WC schema bump for an additive optional field: make the new field `Optional`, not required, and the version bump documents intent without breaking peers.** `WorkoutTickMessage.startedAt: Date?` (optional) means v3 snapshots from older watch builds still decode on v4 phones — the `Codable` synthesized init treats a missing optional as nil. Phone-side falls back to `timestamp − elapsedSeconds` when nil so the user-visible "Started" row shows a sensible time even without a watch upgrade. WC schema v3 → v4 documents that there's a new field; phones running v4 advertise that to themselves and the watch knows to populate it. The backward-compat test (`testV3SnapshotWithoutStartedAtStillDecodesOnV4`) pins the OLD wire format against the NEW type so a regression that makes the field required trips CI.

**Tests:** 186 → 195 Core. ARRunnerWatch xcodebuild SUCCEEDED.

**PR:** [#79](https://github.com/jkrilov/AR-Runner/pull/79).

---

## rc12–rc2 Pattern Evolution (Consolidated Summary, 2026-05-20)

**Six releases, one bundled-bump pattern.**

From rc12 through rc2, the release cadence has been **feature + version bump + tag in a single PR**, automatically TestFlight'd on CI green. This pattern cuts per-release overhead and eliminates manual coordination. All rc12–rc2 work has followed it consistently.

**Recurring learnings across the six-release span:**

1. **Coordinate-system clarity matters more than exact X,Y values.** The canonical `y_fb = 255 − wearer_top` (no font-height subtraction) formula has been revisited three times (rc12 → rc16 revalidation → rc17 finish-screen → rc2 reflow). Each revalidation either caught silent bugs (off-screen rendering) or re-confirmed the math. Lesson: pin the formula in tests, not just the constant values. When the formula changes OR a new rendering surface requires re-validation, the tests catch missing updates.

2. **Lifecycle ownership clarity prevents UX bugs.** rc17's discovery that "workout lifecycle ≠ peripheral lifecycle" (teardown-on-stop was breaking finish-screen readability) generalized to rc2 data-integrity: "confirm-save lifecycle ≠ persist-to-health lifecycle." Both required new protocol methods and terminal-path separation (never branch off a shared path). Pattern: when a UI action should have multiple outcomes (save = persist, cancel = discard, draft = auto-save), the substrate must have distinct verb methods. rc2 formalized this as a skill: `terminal-path-data-leak-qa`.

3. **ALooK font metrics deserve a typed constant.** Passed the same (height, per-font-width) pairs into layout calculations at least four times across rc12–rc2 (live HUD, finish screen, rc2 reflow). Richards recommended extraction in rc13; didn't land until rc2 via `ALookFontMetrics` struct. Lesson: extract early when you see a pattern repeat 2+ times. The 3rd and 4th use cases are slower and riskier than the 1st.

4. **xcodegen `Config/` is a generated artifact — edit project.yml, not the generated plist.** Cost of breaking this rule: silent data loss (the Info.plist edit vanishes on next xcodegen run). Lesson learned the hard way in rc2 with NSLocationWhenInUseUsageDescription. Rule: always touch project.yml first; never hand-edit generated files in Config/.

5. **WatchConnectivity schema bumps are backward-compat opportunities.** rc17 + rc2 both added optional fields (`glassesBattery`, `startedAt`) without requiring watch/phone version alignment. Lesson: Codable + Optional field + version bump in schema = old peers decode, don't block each other.

**Tests growth: 154 (rc12) → 195 (rc2), +41 tests across 6 releases.**

Most additions were pattern tests (pinning formulas, invariants, wire-byte contracts) rather than new feature coverage. The test cadence became denser as the protocol surface stabilized — more regression coverage per release.

---
