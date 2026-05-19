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
