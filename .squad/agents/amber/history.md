# Amber — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** QA & Fitness Domain
- **Joined:** 2026-05-14T18:30:31.658Z

## Active Learnings

### 2026-05-16T20:36:00-04:00 — v0.2 P1.3 prereq: `MetricKind.energy` (commit 9571e23)

Laughlin's v0.2 audit flagged that `HealthKitWorkoutSubstrate.metric(for:)` was mapping `.activeEnergyBurned` → `WorkoutMetric.kind = .duration` because Core's `MetricKind` enum had no kcal case. Downstream consumers (HUD formatters, controller `ingest`) default-coalesce `.duration` so live HK kcal was being silently dropped on the wire — the saved `HKWorkout` still had it (Laughlin reads it directly in `end()`), but the per-tick "flame" reading only ever showed the local `EnergyAccumulator` estimate. Added `.energy` as a new `MetricKind` case (kcal, mirrors HK units). Laughlin's Phase B work will retarget the HK adapter to emit it.

Bug pattern (file under "Core enum gaps → silent downstream drop"):

- **A `String, Codable, CaseIterable` enum that's missing a case isn't a compile error at the producer site.** The producer just picks the "closest" wrong case (here `.duration`) and the type system has no way to flag it. Downstream switches with a default branch (or `case .pace, .duration: break` collapses) then silently coalesce. The bug only manifests as "the UI never updates" — there's no log, no crash, no warning.
- **Defence:** every time a substrate / adapter writes `WorkoutMetric.kind = .X` for a HealthKit / sensor source, the test target should have a unit test that round-trips a representative value AND asserts the kind matches what the spec says — not just that *some* metric arrived. Worth adding to the substrate test plan when Laughlin's HK adapter lands.
- **Where the enum lives** (for future test authors): `ARRunnerCore/Sources/ARRunnerCore/Models/WorkoutMetric.swift`. Tests: `ARRunnerCore/Tests/ARRunnerCoreTests/WorkoutMetricTests.swift`. NOT under `Packages/` — the repo layout uses a top-level `ARRunnerCore/` SwiftPM package, not the more common nested-`Packages/` form. Task brief had it nested; the search above (`find . -name WorkoutMetric*`) is the reliable locator.
- **Exhaustive-switch sweep is mandatory after adding an enum case.** Adding `.energy` broke compile in two test helpers (`formatMetricImpl` in `WorkoutControllerIntegrationTests`, `formatMetricForResilience` in `DisconnectResilienceTests`) — both had exhaustive switches without default. Also touched `WorkoutController.ingest(metric:)` (folded `.energy` into the no-op `.pace, .duration` arm — controller doesn't track accumulated kcal state; that's substrate territory). The compiler caught every site; ran `swift test` to confirm. 80/80 (1 skipped, the pre-existing v0.2 #5 skip).
- **Test contract added two assertions for the new case:** (a) `MetricKind.allCases.contains(.energy)` + Codable round-trip with `unit = "kcal"`; (b) `MetricKind.energy.rawValue == "energy"` to lock the JSON / WC-payload key (would otherwise silently break already-shipped watch↔phone decode if someone renames it). Pattern: when adding a string-backed Codable enum case, *always* lock the rawValue in a test, especially if it crosses a process boundary (WCSession, persisted JSON, BLE payload).

## Archive

See `history-archive.md` for learnings from 2026-05-14 through 2026-05-15 (scaffold validation, multi-agent merge, anticipatory contract tests, Linux CI debugging).

---

### 2026-05-19T09:00:00Z — v0.4.0-rc1 HealthKit observer pattern assignment

**Context:** v0.4.0 scope locked. rc1 = Live HR with HealthKit HR observer.

**Amber's role:** Implement HealthKit HR observer pattern to feed live heart-rate samples into the workout view model. Observer will:
- Start on workout begin
- Stream `HKQuantityType.quantityType(forIdentifier: .heartRateVariability)` samples to ViewModel observable
- Format as `String` for display (`RunningHUDFrame.Payload.heartRate`)
- Collaborate with Killian (HUD frame builder) for rendering coordinates

**Scope notes:** Live HR is a primary running metric. Finish screen (rc2) will reference this observer pattern (steady-state HR vs. final HR). Battery indicator (rc3) follows similar subscription architecture.

**Next:** Coordinate with Killian on `RunningHUDFrame.Payload` extension and with Weiss on glasses-side `txt` command timing once rc9 is bench-validated.

### 2026-05-19T16:50:00Z — rc13 HUD: workout-lifecycle race + splash font fit (PR #72)

**Context.** rc12 (Laughlin) finally got the HUD rotation/coords right but Joe's bench surfaced three new bugs. Two were on the workout-lifecycle layer (my domain): the HUD froze on the connect splash through the entire first run, and the second run only rendered 2 of 3 metric lines. Third was a mechanical splash-font fit. Bundled into one PR per Joe's bundle-bump directive.

**Lessons (file under "actor reentrancy + async fan-out gotchas"):**

- **A `Task { await foo() }` spawn from a MainActor-isolated timer is NOT a serialization tool.** It detaches from the caller's flow and joins the cooperative pool. If the receiving actor (here `ActiveLookGlassesAdapter`) only enforces serial writes WITHIN a single function call (`for frame in frames { try await write(frame) }`), two concurrent callers will interleave their per-frame writes mid-function because the actor is reentrant between `await`s. The fix that doesn't touch the BLE layer is to **`await` the push directly** from the timer so the next tick can't issue until the prior `sendCommands` returns. Made `tickElapsed()` async, called `await pushHUDFrameIfConnected()` directly. End of race.
- **`holdFlush(hold:true) … holdFlush(hold:false)` is a NESTED-FUNCTION-ARGUMENT-style contract over BLE.** If a different caller's `holdFlush(hold:false)` lands inside your sequence, it commits whatever partial buffer is there and your subsequent writes draw into a fresh frame with no hold. The display then shows whatever the previous caller's residue was — in Joe's case, the splash, forever. **Defensive pattern for any future multi-frame BLE sequence:** if you wrap N frames in a state-machine prologue/epilogue (holdFlush, layoutBegin/End, transaction, etc.), the *caller* MUST serialize against itself — the BLE actor's per-write `pendingWrite` continuation does NOT protect the prologue↔epilogue span.
- **`needsHUDPowerOn` semantics are subtle.** It tracks whether the NEXT BLE write should re-assert `cfgSet + power(on:true)`. The connect splash sets it to `false` after sending. But that leaves the FIRST per-tick frame of a subsequent workout without the belt-and-braces re-assertion. If the display drifted into low-power between splash and Start tap, the first burst lands on a dark panel. Fix: `start()` flips it back to `true` so each new workout's first per-tick frame uses `framesWithPowerOn(for:)`. Both prepended commands are idempotent per-connect — cost is two short BLE writes, benefit is no dark-panel race.
- **Splash and run HUD CAN use different fonts.** They're separate `txt` frames at separate Y coords. With `rotation=4` (topLR — text grows LEFT from `x_fb=284`), a 15-char string at font 3 (~28 px/char) extends to `x_fb ≈ −136` → silently clipped per spec §5.5.6. Font 2 (~18 px/char) fits the same 15 chars in 270 px ≤ 284. The Y coords MUST recompute for the new font height (`y_fb = 255 − T − font_height`); for font 2 that's `y_fb = 217 − T`. Pinned the math in `test_bannerYCoords_compensateForShorterFontHeight` so a future font/Y retune can't silently drift off-screen.
- **The "ViewModel coordinates lifecycle, BLE actor coordinates writes" boundary is sharp.** Two of three rc13 fixes were on MY side of the fence (timer awaiting, needsHUDPowerOn reset), not the BLE adapter's. Weiss + Richards have been locked from HUD render after the v0.3 saga; Laughlin had two override turns. Fresh eyes (me) found the issue was actually in the workout-lifecycle wiring — exactly the kind of cross-layer surface where a fresh perspective wins.

**Process notes:**

- **Second release under the bundled-bump directive (rc12 was first).** `CURRENT_PROJECT_VERSION 27 → 28` + `xcodegen generate` + Info.plist placeholder verification shipped in the same PR as the code fix. Worked smoothly — confirms the pattern generalizes beyond Laughlin's rc12.
- **`gh pr merge --squash --admin` to bypass CodeQL pending check** — directive said skip CodeQL. All other checks (ARRunnerPhone, ARRunnerWatch, Linux swift test) passed before merging.
- **xcodebuild watch build with `CODE_SIGNING_ALLOWED=NO`** is the fastest way to validate `ARRunnerWatch/` Swift compiles without round-tripping through CI. Swift Package tests cover `ARRunnerCore` but not the watch target.
- **154 → 157 tests** (4 added, 1 existing updated to compile after Layout const additions).

### 2026-05-19T17:30:00Z — rc14 HUD: live HR (pulled forward from v0.4.0-rc1) + dedicated finish screen + splash polish (PR TBD)

**Context.** rc13 (PR #72) fixed the workout-lifecycle freeze. Joe's bench
test on rc13 surfaced 3 follow-ups: splash still said "AR-Runner Ready"
(wants just "AR-Runner"), live HUD only showed Time + Distance (wants Time
+ HR + Distance + Avg Pace), and workout-end leaves the live frame frozen
(wants a dedicated finish card with just Time + Distance). Bundled into a
single PR per the bundle-bump directive.

**Lessons (file under "discovery before architecture"):**

- **HR already arrives end-to-end at the ViewModel; only the HUD payload was
  missing wiring.** The v0.4.0-rc1 roadmap subtask "implement HealthKit HR
  observer pattern" was scoped as a substantial new subscription layer.
  Actually doing the discovery (read `HealthKitWorkoutSubstrate.swift:281-283`,
  read `WorkoutViewModel.swift:629`) showed HR is already collected by
  `workoutBuilder(_:didCollectDataOf:)`, already mapped through
  `WorkoutMetric(kind: .heartRate)`, already captured in
  `WorkoutViewModel.heartRate` via `apply(metric:)`, and already rendered on
  the wrist UI at `WorkoutView.swift:169 → "\(Int($0)) bpm"`. The actual
  rc14 work was 6 lines: extend `RunningHUDFrame.Payload` with a `heartRate:
  String` field, extend the payload builder to take `heartRate: Double?` and
  format it through a new `formatHeartRate(_:)` helper, plus wire `heartRate:
  heartRate` into the two existing `RunningHUDFrame.payload(...)` call sites
  in `pushHUDFrameIfConnected` and `pushHUDSummaryIfConnected`. **Lesson:
  walk the actual code before estimating a feature; the roadmap can over-
  scope a task by an order of magnitude if upstream substrate work already
  happens to land what you need.** Worth pre-reading the substrate
  end-to-end for the next v0.4.0 metric pulled forward (battery, cadence)
  before scoping it as an "observer pattern" subtask.

- **`-- bpm` is the placeholder for both pre-first-sample AND sensor-dropout
  states; sub-30 BPM in a running workout treated as "no signal."** HK can
  emit sub-30 readings during a strap dropout (or wrist-off detection). Mid-
  run rendering of "12 bpm" would alarm the user. Floor at 30 BPM; otherwise
  pass through verbatim (don't cap the high end — a real max-effort 220 is
  useful telemetry, not noise to hide). Mirrors what the wrist UI does
  implicitly by relying on HK's own filtering; the HUD's `formatHeartRate`
  makes it explicit and testable without a HK test host. Pattern: `nil ||
  !isFinite || < 30 → "-- bpm"` else `"\(Int(round(bpm))) bpm"`.

- **Live vs finish HUD field split is a NEW directive worth pinning in
  decisions.md.** Joe explicitly distinguished: "Those [time + distance] are
  supposed to be the final stats. During the run we should see Time, HR,
  Distance, Avg Pace." Two different field sets for two different lifecycle
  states. The architectural consequence: `summaryFrames(for:)` deliberately
  takes a fully-populated `Payload` but discards `heartRate` and `pace`. Test
  pin: `test_summaryFrames_renderTimeAndDistanceOnlyPerFinishScreenDirective`
  asserts pace + HR strings do NOT appear in any summary frame's UTF-8
  region — so a future "let's add HR back to the summary because we have it"
  PR has to explicitly delete the test and confront the decision.

- **4 lines × font 3 at 55-px wearer-space spacing fits in the 256-px panel
  with 6-px gap between glyph blocks.** Engo 2 panel = 256 px tall, font 3 =
  49 px tall. 4 lines × 49 = 196 px text, 3 × 6 = 18 px gaps, 21 px top
  margin + 20 px bottom margin = 255 px. Tight but legible at arm's length.
  The alternative (drop to font 2 for breathing room) would have invalidated
  rc13's `test_runHUDFont_staysAtFont3` guard and given up readability for a
  comfort we didn't need. **Lesson: a "tight" layout test that's been
  validated on-bench is a feature, not a bug — defend it; don't relax the
  constraint when you add fields.** New constants `liveTimeY/liveHRY/
  liveDistanceY/livePaceY` live alongside (not replacing) the original
  `timeY/distanceY/paceY` which the summary screen still uses.

- **The "summary screen" Y constants stay at the OLD 3-position layout
  (timeY=166, distanceY=86, paceY=6) but now host different content
  (banner, time, distance instead of banner, distance, pace).** Renaming
  them to `summaryTimeY/...` would have rippled across 6 tests for zero
  semantic gain. Renaming is cheap when constants are pure data; here they
  also serve as the lens-flip anchor for a known-good 3-line layout that
  even the v0.4.0 trophy-imgDisplay screen will probably reuse. Kept the
  names, added a doc comment explaining the dual purpose.

**Process notes:**

- **Third release under the bundled-bump directive.** Worked cleanly:
  `CURRENT_PROJECT_VERSION 28 → 29` + `xcodegen generate` + Info.plist
  placeholder verification (all 4 targets) in the same PR as the code work.
  This pattern has now stabilized across Laughlin (rc12), me (rc13), me (rc14).
- **166 tests pass** (was 157 in rc13). Added 9 new: 5 HR-formatting cases
  (nil/normal/sub-30/non-finite/high-end + payload default), 1 live-HUD
  geometry (`test_liveHUDYCoords_followLensFlipFormula`), 1 splash trim
  (`test_connectFrames_defaultBannerIsTrimmedToARRunner`), 1 finish-screen
  contract (`test_summaryFrames_renderTimeAndDistanceOnlyPerFinishScreenDirective`),
  1 4-line frame structure (`test_frames_startWithHoldFlushThenClearThenFourTxtThenFlush`
  renamed from the 3-line version).
- **xcodebuild watch-target Debug build with `CODE_SIGNING_ALLOWED=NO`** as
  the fast pre-CI sanity check for the watch target (`swift test` covers
  Core but not the watch app target).
