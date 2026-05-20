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

### 2026-05-20T12:42:23-04:00 — rc3: GPS-route auth fix + discard-returns-to-start (BLE preserved)

**Context:** Joe's v0.4.0-rc2 bench test surfaced two bugs from the same release. Finish screen ✅. Two failures: (1) GPS route still doesn't reach Apple Health even though the location prompt now appears (so the Info.plist fix worked, CoreLocation is producing fixes); (2) Discard tears the BLE link into a stuck state — UI shows "connected" but disconnect/reconnect both no-op until the app is force-killed.

**Root cause #1 — GPS:** `HKWorkoutRouteBuilder.insertRouteData` requires the user to grant share authorization for `HKSeriesType.workoutRoute()`. We never asked for it. The auth request in `HealthKitWorkoutSubstrate.sharedTypes` included workouts + heart rate + distance + energy but **omitted the workout-route series type**. Every `insertRouteData` call returned `success=true` (HK accepts the buffer) but nothing ever reached the persisted polyline, and `finishRoute(with:metadata:)` produced no attached route on the workout. Two prior fixes had been red herrings: the Info.plist location-usage string (needed, but not sufficient) and the substrate's CoreLocation wiring (correct, but blocked downstream by the missing auth). **Add `HKSeriesType.workoutRoute()` to `sharedTypes`** so the next HK auth prompt asks for route-write permission. Also replaced `try?` on `finishRoute` with explicit success/error logging and added per-step `os.Logger` traces (`subsystem=com.arrunner.watch category=WorkoutRoute`) for ingest count, accuracy-filter drops, insert success/error, and finishRoute sample count — the next missing-route regression will surface in Console.app instead of needing another bench bisect.

**Root cause #2 — Discard kills BLE observation:** `WorkoutViewModel.stopRuntimeTasks()` cancelled `glassesStateTask` and `glassesStatusTask` alongside the workout-runtime streams. Per ADR-1, the BLE link is **user-managed and transport-scoped**, not workout-scoped. Cancelling the glasses observers after a discard left the view-model blind to subsequent connection-state events: the UI froze on the last-observed "connected" state while the transport itself was effectively orphaned. `disconnectGlasses()` did call `transport.disconnect()` — but the resulting `.disconnected` event was never observed, so the UI never updated; and `connectGlasses()` early-returned on the stale `.connected` read. Force-kill of the app was the only recovery (rebuilds the view-model + observers from scratch).

**Fix:** Split task-cancellation by scope. `stopRuntimeTasks()` now only cancels workout-scoped tasks (state, metric, elapsed, mirror-tick). Glasses observers are intentionally preserved, with a docstring pinning the contract so a future agent doesn't re-introduce the bug. `confirmCancel` now transitions to `.idle` (not `.cancelled`) after `controller.discard()`, drops the now-finished controller reference, and resets live counters — landing the user on a clean, fully-functional start screen with the BLE link still alive and ready for another run.

**Key learnings:**

1. **HKWorkoutRouteBuilder needs its own share-auth.** `insertRouteData` accepting samples doesn't mean it'll persist them. The route series type is a separate auth grant from the workout type, and the auth API silently degrades to "buffered but never written" without it. Pattern: every HK series type used in a workout (route, environmental audio exposure, etc.) MUST be in `sharedTypes` for its `insertX` calls to take effect. The diagnostic signature was "Info.plist prompt appears, CoreLocation delivers fixes, but Apple Health workout has no map" — that exact signature → check `HKSeriesType.workoutRoute()` is in the share set first.

2. **Best-effort completion handlers hide auth failures.** Pre-rc3 `insertRouteData(filtered) { _, _ in }` swallowed the error parameter. We thought we were tolerating transient transport hiccups; we were actually masking a permanent permission gap. New rule: when the completion handler can surface an auth/config error (vs. just a transient I/O failure), log it loudly. `os.Logger` at `.error` level with `privacy: .public` for non-PII fields keeps the trace useful in production.

3. **Lifecycle scope boundaries must be encoded in helper names.** `stopRuntimeTasks()` was ambiguous — does "runtime" include the transport observers? The old answer was yes; the new answer is no. Either rename to `stopWorkoutRuntimeTasks()` (we considered this and dropped it as redundant since only one cancellation method exists now) OR pin the contract in a docstring (we did this) so the boundary is unmistakable to the next reader. The decision file documents the choice.

4. **Terminal UI states should match user mental model.** `.cancelled` is a terminal state that says "this workout is done, just not saved" — but Joe's mental model on Discard is "go back to where I was before I started, glasses still on." `.idle` matches that mental model. The state-machine purist in me liked `.cancelled` for distinguishability, but the UX wins: the start screen treats `.idle / .ended / .cancelled / .failed` identically anyway, so the distinction was paying for nothing.

**Files changed (2):** `ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift` (route auth + logging), `ARRunnerWatch/Workout/WorkoutViewModel.swift` (discard → idle, BLE observers preserved).

**Tests:** Core 195/195 pass. `xcodebuild -scheme ARRunnerWatch` SUCCEEDED (signing skipped for local validation).


### 2026-05-20T13:19:07-04:00 — rc4: confirmationDialog binding race strands discard on running screen

**Context:** Joe's rc3 (v0.4.0-rc3) bench test: discard still doesn't return to start screen. The rc3 fix (separate `controller.discard()` terminal path, glasses observers preserved, transition to `.idle`) was correct on paper — `xcodebuild` succeeded, 195/195 Core tests passed, code inspection of `confirmCancel()` showed all the right writes. But on-device the wearer lands back on the live running screen post-discard.

**Root cause — SwiftUI `confirmationDialog` ordering race.** When the user taps "Discard" in the dialog, SwiftUI synchronously (same runloop tick) does TWO things:

1. Invokes the Button action → `Task { await viewModel.confirmCancel() }` (enqueued, not yet executing).
2. Dismisses the dialog → invokes the `isPresented` binding's `set(false)` synchronously next.

At step 2, the `confirmCancel` Task hasn't started, so `launchState` is still `.pendingFinish`. The setter's guard (`if !isPresented, viewModel.launchState == .pendingFinish`) — added in rc1 to recover from "stray tap-out" auto-dismissals — fires and spawns `Task { await viewModel.resumeFromFinish() }`. Now two terminal actions race on the same `controller`:

- `confirmCancel` writes `.ending`, suspends on `controller.discard()`.
- During that suspension, `resumeFromFinish` → `resume()` enters; its `guard let controller` captures the still-non-nil property and calls `controller.resume()`.
- `confirmCancel` resumes, sets `controller = nil`, lands `launchState = .idle`.
- `resume()` then resumes from `controller.resume()` (which succeeded — the workout was merely paused), writes `launchState = .running`.

Final state: `.running`. UI shows Pause/Finish. Discard appears "to have done nothing" — the user is stranded on the live screen. Same race latently afflicted Save, but Save's symptoms were masked because the running screen renders briefly before the user dismisses the app or starts another action.

**Fix:** Add a synchronous `acknowledgeFinishChoice()` method on the view-model that transitions `.pendingFinish` → `.ending` (idempotent guard). Call it from the Save / Discard / Resume button actions BEFORE the `Task { … }` is scheduled. Now when SwiftUI synchronously invokes the binding's `set(false)` next, `launchState` is `.ending` — the setter's `launchState == .pendingFinish` guard fails and `resumeFromFinish()` is NOT auto-spawned.

For Resume, the synchronous pre-transition prevents a benign-but-wasteful double-resume() call (one from the Button action, one from the binding setter). The brief `.ending` flash shows a ProgressView for one frame before `.running` lands — acceptable for a tap.

**Key learnings:**

1. **SwiftUI's `confirmationDialog` invokes BOTH the Button action AND the `isPresented` binding's `set(false)` in the same synchronous tick.** This is well-known but easy to forget. If your dismissal binding has side effects gated on view-model state (like the "stray tap-out → resume" recovery here), those side effects WILL fire even on explicit-choice taps unless your state mutation happens BEFORE the binding setter runs. That means **the state mutation must be synchronous from the Button action's closure** — `Task { await … }` is too late because the Task body runs on the next runloop tick at the earliest, after the binding setter has already executed.

2. **`@Observable` view-model state changes inside async functions are not "racing" via @MainActor isolation alone.** Both `confirmCancel` and `resumeFromFinish` run on @MainActor, so they don't *interleave* at instruction level — but they do *interleave at suspension points* (every `await`). The state transitions `.pendingFinish → .ending → … → .idle` and `.pendingFinish → … → .running` both go through suspension points (`controller.discard()`, `controller.resume()`), and which one wins the final assignment depends on which substrate call resolves last. Lesson: in any async terminal flow, assume any other async caller can interleave at every `await`. The synchronous pre-transition is the load-bearing primitive that makes the dialog's "two simultaneous tasks" actually mutually-exclusive — by collapsing the pre-condition check (`launchState == .pendingFinish`) into a single MainActor tick, only one of the two enqueued tasks ever satisfies it.

3. **The "guard on state" pattern in SwiftUI binding setters needs synchronous corroboration from the button action.** The rc1-era `if !isPresented, viewModel.launchState == .pendingFinish { Task { resumeFromFinish() } }` setter is the right pattern for catching stray dismissals, but it ONLY works correctly when the button actions synchronously move out of the gated state. The view-model needs both an async terminal method (for `confirmCancel`) AND a sync acknowledger (for the button action) — two halves of one contract.

4. **A six-RC-old comment can encode a stale assumption.** The rc1 setter comment ("a stray tap-out can't strand the workout in pendingFinish") was correct then because the buttons synchronously mutated state via the legacy non-async API. When the buttons were converted to `Task { await … }` (rc16 or so), the synchronous-pre-condition guarantee was lost silently — no warning, no test break, just a latent race that didn't surface until rc3's discard finally produced an observably-broken UI (rc1/rc2's discard didn't return to start anyway because of the data-leak bug, masking this race). Lesson: when refactoring a sync→async boundary, audit every state-gated callback within two hops for the previously-held synchrony assumption.

**Files changed (2):**
- `ARRunnerWatch/Workout/WorkoutViewModel.swift` — add `acknowledgeFinishChoice()` (sync MainActor method, idempotent guard `.pendingFinish → .ending`).
- `ARRunnerWatch/Views/WorkoutView.swift` — call `viewModel.acknowledgeFinishChoice()` synchronously from Save / Discard / Resume button actions before scheduling the Task.

**Tests:** Core 195/195 pass. `xcodebuild -scheme ARRunnerWatch` SUCCEEDED.


### 2026-05-20T15:33:22-04:00 — v0.5 PR 2: Strava OAuth + Token Store + Settings tab

**Work:** Shipped phone-side Strava plumbing per D-Strava-1/3/5/6 on `feat/v05-strava-oauth` (branched from main, clean rebase off Amber's TCX PR which lives on `feat/v05-tcx-encoder`).

**Files added (all under `ARRunnerPhone/`):**
- `Strava/StravaConfig.swift` — clientID resolved from `STRAVA_CLIENT_ID` env → Info.plist → placeholder. Worker base `https://strava-connect.ar-runner.app`. App Group `group.com.arrunner.shared`. `isConfigured` flag drives a UI warning when the placeholder is still in place.
- `Strava/StravaOAuthService.swift` — `ASWebAuthenticationSession` driving `https://www.strava.com/oauth/authorize?...&approval_prompt=auto`. Callback parsed by pure `StravaOAuthURLBuilder` (testable without a UIWindow). Code exchanged via POST to worker `/token`. `StravaOAuthError` enum keeps framework types out of the VM layer. `MainActor.assumeIsolated` used for the `presentationAnchor` hop because `ASWebAuthenticationPresentationContextProviding` is `nonisolated`.
- `Strava/StravaTokenStore.swift` — single JSON record in shared keychain (`KeychainStravaTokenStore`, access group = `StravaConfig.appGroup`). Auto-refresh via worker `/refresh` when `expiresAt - now < 60s`. `StravaTokenBackingStore` + `StravaTokenRefresher` protocols make the store fully testable in-memory. Update-then-add on save avoids a window where readers see "no tokens".
- `Views/SettingsView.swift` + `SettingsViewModel.swift` — gear tab replaces the old placeholder. Sections: Strava (Connect/Connected/Disconnect + auto-upload toggle) and About (app version). Auto-upload toggle defaults OFF per D-Strava-5 and resets on disconnect. Branded orange `#FC4C02` `Color.stravaOrange` extension for the CTA only.
- `Tests/{StravaOAuthURLBuilderTests, StravaTokenStoreTests, SettingsViewModelTests}.swift` — 16 tests, all green.

**Project changes:**
- `project.yml`: new `ARRunnerPhoneTests` xcodegen target (type `bundle.unit-test`, hosts on ARRunnerPhone, `GENERATE_INFOPLIST_FILE: YES` to dodge code-sign-without-plist error). Excluded `ARRunnerPhone/Tests/**` from the app target sources so test files don't leak into the app binary. Registered `arrunner://` URL scheme via `CFBundleURLTypes` and `StravaClientID: $(STRAVA_CLIENT_ID)` Info.plist key on the phone target.

**Verification:** ARRunnerPhone build green. ARRunnerPhoneTests: 16/16 pass. ARRunnerCore: 215/215 still pass.

**Key learning:**
- Phone app had no test target until now. Pattern for adding one in xcodegen: `type: bundle.unit-test` + `GENERATE_INFOPLIST_FILE: YES` + `TEST_HOST: $(BUILT_PRODUCTS_DIR)/ARRunnerPhone.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ARRunnerPhone` + matching `BUNDLE_LOADER`. Forgetting `GENERATE_INFOPLIST_FILE` fails build-for-testing with "Cannot code sign because the target does not have an Info.plist file".
- When adding a test directory inside an existing target's source path, MUST add `excludes: ["Tests/**"]` to the app target's source spec or the test files compile into the app bundle (and the app fails to link XCTest).
- App Group keychain pattern: pass the raw entitlement group string (`group.com.arrunner.shared`) as `kSecAttrAccessGroup`. The OS resolves it via the entitlement plist; no team-ID prefix needed in client code.
- `ASWebAuthenticationPresentationContextProviding.presentationAnchor(for:)` is `nonisolated`, so the implementation hops to MainActor with `MainActor.assumeIsolated { ... }` to read `UIApplication.shared.connectedScenes`. Cleaner than wrapping the whole conformance in `@preconcurrency`.
- `Config/` is gitignored — Info.plist edits don't ship. Always express plist additions in `project.yml` `info.properties`; xcodegen regenerates the plist on build.

**Cross-agent note:** Amber's `feat/v05-tcx-encoder` branch holds the TCX encoder + activity naming (PR 1). This work (PR 2) is independent — branches share no code. Both should rebase cleanly onto each other when both land in main; PR 3 (upload pipeline) will wire them together via `tokenStore.validAccessToken()`.
