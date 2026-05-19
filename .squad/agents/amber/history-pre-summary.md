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

### 2026-05-19T15:45:47-04:00 — rc17: watchOS workout-end lifecycle race + BLE keep-alive pattern

Joe bench-confirmed rc16 (icons + layout) and immediately surfaced a workout-end regression: "The connection drops when I finish a run, I don't see the finish screen we planned and the connection to the glasses is lost. I need to manually reconnect or restart the app." Two-bug compound; both lived in `WorkoutViewModel.confirmSave()` (and the mirror in `confirmCancel()`).

**Bug 1 — runtime race on HK session end.** Order was `controller.end()` → `pushHUDSummaryIfConnected()` → `teardownTransport()`. The HK session is the *lease holder* for the watch's foreground runtime allowance. Calling `HKWorkoutSession.end()` releases that allowance, after which the OS is free to suspend the process at any time. The BLE writes in `pushHUDSummaryIfConnected()` were therefore racing the suspend deadline. On real hardware the OS usually wins → finish frame's bytes vanish silently.

Lesson (file under "watchOS runtime budgets are lifecycle-coupled"):
- **Treat `HKWorkoutSession.end()` as a hard cliff.** All BLE / runtime work that depends on foreground execution must complete *before* you call `session.end()`, not after. There is no grace period; the suspend can land microseconds after `end()` returns.
- **`bluetooth-central` UIBackgroundModes only keeps the radio alive — it does not keep your process alive.** The radio stays warm enough that a *new* connect would succeed quickly, but pending CBPeripheral writes from a suspended process are dropped.
- **`WKExtendedRuntimeSession` is the canonical workaround** *if* you can't reorder. We considered `.mindfulness` runtime and rejected it for rc17 because reordering was strictly simpler (no auth prompts, no second lifecycle delegate, no HK re-entrancy edge cases). Future agents: reach for `WKExtendedRuntimeSession` only when you genuinely need work to span past the HK session, not as a default.

**Bug 2 — eager teardown.** Even if the frame had landed, the immediately-following `teardownTransport()` called `transport.disconnect()`, which severs the BLE link. Glasses go idle; user has to manually reconnect for the next workout. The eager-cleanup intent was wrong: post-run isn't a "we're done with this hardware" moment, it's a "user is reading their stats" moment.

Lesson (file under "Cleanup-on-completion is an anti-pattern for user-facing hardware"):
- **Don't tear down hardware sessions when the user might still be using them.** "User chose Save" ≠ "user is done with glasses." Treat session-end and hardware-disconnect as two separate user intents wired to two separate buttons.
- **The user already has an explicit disconnect path** (`disconnectGlasses()`). When you find yourself adding an *implicit* second teardown path, you've created a UX trap.
- **Pattern: persist HUD frames indefinitely; rely on the wearer's own disconnect / power-off as the natural cleanup signal.** The ActiveLook frame is one BLE write; the cost of "leaving it up" is essentially zero.

**Fix shipped (rc17):**
```swift
launchState = .ending
stopRuntimeTasks()                  // freeze live HUD writes
await pushHUDSummaryIfConnected()   // ship while HK runtime + radio guaranteed
let summary = try await controller.end()
launchState = .ended(summary)
await mirror?.sendLifecycle(.ended)
// No teardownTransport — finish screen persists; user disconnects manually.
```

Deleted the `teardownTransport()` helper outright. The only remaining disconnect path is the user-explicit `disconnectGlasses()`. Same pattern in `confirmCancel()` (no finish frame, but also no implicit disconnect — cancel may immediately precede a new run).

**Why this matters for future Amber/Laughlin work:** any new lifecycle hook on HK session-end (post-workout widget refresh, summary export, etc.) must do its work BEFORE `controller.end()`. The `confirmSave` docstring now spells this out — future contributors who try to "clean things up" after `controller.end()` are walking into the rc16 trap.

Tests: no new XCTest cases (WorkoutViewModel is in the watch target with no test host). Existing `RunningHUDFrameTests` (4-frame Time+Distance "Workout Complete" pin from rc14) and `DisconnectResilienceTests` still pass — the frame builder and disconnect-signal handling are untouched. Bench verification by Joe is the canonical post-merge gate.

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

### 2026-05-19T18:15:00Z — rc15 HUD: mixed-font 3-line layout; icon pipeline deferred to rc16 (PR TBD)

**Context.** rc14 (PR #74) shipped 4-line × font 3 × 55-px wearer-space spacing. Joe's bench: *"fonts are too large and text on each line is overlapping"* + a redesign request: icons on every line + two metrics (Time + HR) on line 1. Brief gave an explicit escape hatch for the icon-pipeline scope; phase-0 research showed it tripped.

**Lessons (file under "spec-research-before-implementation; escape hatches are real"):**

- **The rc15 brief had three wrong command IDs.** Brief said `imgList=0x42`, `imgDisplay=0x44`, `imgSave=0x41`. Spec §4.7 (modern, post-4.0.0) says `imgList=0x47`, `imgDisplay=0x42`, `imgSave=0x41`. The 0x40/0x44 IDs the brief referenced are in §4.16 "Deprecated commands" — they exist on the wire for backward-compat but should not be used in new code. **Lesson: when a task brief lists hex command IDs, cross-check them against the spec §4.x active table before pinning encoder tests to them.** A test pinning the wrong cmdID byte would still pass the encoder unit test but the glasses' firmware would reject the frame as protocol error 0x04. Cost of cross-check: one fetch. Cost of skipping: a full rc cycle to debug a "why does my imgDisplay do nothing" report.

- **`imgSave` requires `cfgWrite` first (spec §5.5 prelude). That's the whole iceberg.** `cfgWrite` modifies a named configuration's namespace. The stock "ALooK" config that ships pre-installed and contains fonts 1–5 is marked `isSystem` and can't be deleted (§4.14 cfgList response). If we cfgWrite to a new config like "ARRunner" and then cfgSet to it to display our icons, **we lose access to the stock fonts** — our existing `txt(font:3)` calls go blank because font 3 doesn't exist in the new config's namespace. So the rc15-as-scoped task wasn't just "add 3 encoder methods and an upload helper" — it was either (a) attempt to overwrite the system ALooK config (requires Microoled-supplied credentials, possibly unsupported) OR (b) install ARRunner as a new user config AND upload fonts into it (font-upload protocol is also chunked, also deprecated/superseded at the API boundary, also requires its own pixel-packing pipeline). Either path is at least one full rc cycle of work on the adapter layer alone.

- **Escape hatches in task briefs are LOAD-BEARING — use them.** The rc15 brief explicitly said *"If asset upload chunking turns out to be a large undertaking (multi-MTU bitmap fragmentation with sequence numbers), STOP and report — we'd want to consider deferring to rc16 with just rc15 = layout-only fixes (no icons)."* The temptation to plow ahead with a half-baked icon pipeline (no `cfgWrite`, hope the system ALooK config accepts our `imgSave`) would have produced a PR that compiles, has tests, and bricks the device's view of its own config in production. **Lesson: when a brief has a written escape hatch, the brief's author has already done a risk-assessment YOU haven't done; respect it.** The shipped rc15 delivers the bench-visible half of Joe's request (no more overlapping text) on the rc-cadence with full test coverage; the icon half ships in rc16 once the underlying plumbing is properly scoped.

- **Mixed-font layouts are valid and cheap.** Joe's own feedback contained the workaround: *"I think the fonts will need to be smaller, at least for the first line since we are showing two data points."* rc15 reads as "trust Joe's instinct; ship exactly that." Line 1 (Time + HR) drops to font 2 (38 px tall, ~18 px/char); lines 2–3 (Distance, Pace) stay at font 3 (49 px) for arm's-length readability. The implementation is one new constant (`liveLine1Font = 2`) and per-line font selection in `frames(for:)`. **Lesson: when the rc13 splash-font-fit problem reappeared on the run HUD, the rc13 solution (drop to font 2 for the long string) generalized cleanly to "drop to font 2 for the two-metric line." Pattern is now: font 3 by default, font 2 for any line with ≥ 2 metrics or ≥ 10 chars.** Pinned in `test_liveHUDLine1_usesShorterFontForTwoMetricLine` and `test_runHUDFont_distanceAndPaceStayAtFont3` — together they prevent both a "make everything font 2" mass-edit AND a "make everything font 3" rollback.

- **Two metrics on one line = two `txt` commands at shared y, different x_fb.** The topLR rotation anchors at the text block's top-right and grows left. For the LEFT-side metric (Time), anchor at the high-x leftMargin (284 → wearer-left ≈ 20). For the RIGHT-side metric (HR), anchor at a lower-x value (`liveHRX = 133` → wearer-left ≈ 170, mid-panel). Both `txt` commands share `liveLine1Y`. No new encoder surface; no width-aware right-alignment math (which we explicitly avoided in rc14's Option B for the same reason — the stock-font advance table isn't documented and we'd be re-deriving it from bench observations). **Lesson: when you need columns on a single line under topLR, pick the right-column's x_fb empirically (mid-panel for two columns) rather than computing it from glyph widths.** The wearer's eye is forgiving of "Time near the left, HR somewhere on the right"; it's not forgiving of "Time overlapping HR." Trade an inch of precision for a yard of robustness.

**Process notes:**

- **Fourth release under the bundled-bump directive.** `CURRENT_PROJECT_VERSION 29 → 30` + `xcodegen generate` + Info.plist placeholder verification (all 4 targets) in the same PR. Pattern fully stable now across Laughlin (rc12), me (rc13, rc14, rc15).
- **167 tests pass** (was 166 in rc14). Net: 1 added (`test_liveHUDLine1_usesShorterFontForTwoMetricLine`); 4 rewritten (`test_frames_renderTimeAndHROnLine1ThenDistanceThenPace_rc15`, `test_frames_textPayloadGeometryMatchesEngo2Layout`, `test_liveHUDYCoords_followLensFlipFormula`, `test_runHUDFont_distanceAndPaceStayAtFont3`).
- **Phase-0 research artifact lives in `.squad/files/hud-icon-research.md`** — rc16 picks up from there; ground-truth IDs and the cfgWrite-prereq trap are pinned so the next agent doesn't re-derive them from a fresh spec read.

### 2026-05-19T18:50:00Z — rc16 HUD: preloaded icons + layout fix (correct font heights, drop BPM text) (PR TBD)

**Context.** rc15 (PR #75, build 30) shipped the mixed-font 3-line live HUD. Joe's bench surfaced three issues that all trace to ONE root cause — font 3 height was under-estimated. Joe verbatim: *"the layout is almost there. The top line is just slightly cutoff, 1 or two pixels on the 'm' in 'BPM' are missing on the right side. After that there's a large gap before the distance, then the pace is almost completely off the screen, I can see just one pixel at the bottom of the screen. Can we try to fix the layout and add the icons in the next PR?"*

**Outcome.** PR with five bundled changes (correct font heights, corrected lens-flip formula, drop " bpm" text, add 4 preloaded ALooK icons via `imgDisplay`, build bump 30→31). 172 tests pass (was 167 in rc15). New `ActiveLookCommand.imgDisplay(id:x:y:)` encoder (cmdID 0x42 per spec §4.7). Brief hypothesis under test on the bench: preloaded icons ship pre-rotated for the lens; if Joe sees them upside-down, rc17 adds rotation.

**Key learnings:**

- **The real ActiveLook font height table is F1=24 / F2=38 / F3=64 / F4=75 / F5=82** per the `ActiveLook/Activelook-Visual-Assets` repo README (the README that ships the ALooK config). rc12/14/15 all assumed font 3 = 49 px from spec §5.9's generic txt-font table — **that's a different font table** than what ALooK actually preloads. 15 px taller per font-3 line × 2 lines = 30+ px of unmodeled drift that pushed the pace line off the bottom of the panel. **Lesson: when ActiveLook ships multiple font tables (spec §5.9 generic vs ALooK-config-specific), the config-specific table wins because that's what the firmware addresses. Always cross-check font heights against the asset repo's README before deriving layout coords.**

- **The empirically-correct topLR lens-flip formula is `y_fb = 255 − wearer_top` (no font-height subtraction).** rc12 derived `y_fb = 255 − T − font_height` (anchor at top-of-rotated-glyph) and shipped working text, but the working-ness was coincidence — text landed in visible regions even though the anchor semantics were wrong. Joe's rc15 bench data is the smoking gun: `livePaceY=26 + font_3 = 64 → wearer_top = 229, wearer_bottom = 293`. **Only `y_fb = 255 − wearer_top` predicts 293 (= 229 + 64) which matches Joe's "just one pixel at bottom" exactly.** Under `y_fb = 255 − T − h`, livePaceY=26 would put pace at wearer 165..229 — fully visible — which Joe definitively didn't see. **Lesson: when bench evidence contradicts a derived formula, trust the bench. The "large gap before distance" symptom AND the "pace off-screen" symptom AND the rc15 line-1 working AND the rc11 blank all line up under the corrected formula; they were partially consistent with the old one only by coincidence.**

- **Preloaded ALooK icons skip the entire cfgWrite/imgSave upload iceberg.** rc15's `.squad/files/hud-icon-research.md` correctly identified that custom icon upload needs `cfgWrite` (system ALooK config can't be modified without Microoled credentials) + chunked binary upload + 4bpp pixel packing + new adapter surface. **What that research missed is that ALooK already ships with the 4 icons we need preloaded** (40_chrono_40x40, 12_heart-beat_28x28, 9_distance_28x28, 17_pace-avg_28x28 — the leading number in each asset filename is the literal flash ID the firmware indexes by). The demo app uses them. `imgDisplay(id, x, y)` (cmdID 0x42) works on a stock-config glasses with no upload work — we just call it. **Lesson: before scoping a "build an asset upload pipeline" subtask, check whether the assets you need are already preloaded in the active configuration. ALooK has 40+ preloaded images (per `imgList` 0x47 response on demo-app inspection); custom-asset work is only needed for artwork outside that catalog.** This collapses the rc15-projected "multi-rc-cycle adapter rework" down to "one new encoder method + 4 frames per tick."

- **`imgDisplay` is framebuffer-direct — no rotation flag.** Spec §4.7 confirms `imgDisplay(id, x, y)` has NO rotation parameter. The Engo 2 lens still applies its 180° point-symmetric flip to whatever pixels we send, so a bitmap rendered "naturally" appears upside-down to the wearer. ActiveLook handles this by pre-rotating their shipped assets in the Visual-Assets repo (per the README convention) — so the post-lens result reads upright. **Working hypothesis for rc16: preloaded ALooK icons follow the same convention and read upright with no compensation.** If they don't, rc17 either pre-rotates at upload time (custom path — needs cfgWrite) or accepts that preloaded icons appear inverted and we ship our own pre-rotated copies via the upload pipeline. The encoder + flash IDs are the same either way; the only delta is the asset bytes.

- **"Drop ' bpm' from HR" was the cheap fix for the rightmost-pixel clipping.** Joe's "1 or two pixels on the 'm' in 'BPM' are missing" was a horizontal-extent problem, not a vertical one. "165 bpm" at font 2 is ~126 px wide; "165" is ~54 px. Width budget shrunk by 72 px → easily fits inside the wearer-x [220..274] slot. **Lesson: when a HUD field has both a numeric value AND a unit suffix, an icon almost always frees more pixels than the unit text consumes (heart icon is 28 px wide vs " bpm" being ~72 px wide).** This generalizes: the v0.4.x cadence icon, splits icon, battery indicator should all use the same "icon-carries-unit-semantic" pattern. Less text = more legible at arm's length AND fewer right-edge clipping risks.

- **The five-line `Layout` doc block in `RunningHUDFrame.swift` is now load-bearing.** I documented the full wearer-space layout math (top margin / line / gap / line / gap / line / bottom margin = 255 total), the corrected lens-flip formula derivation with the empirical evidence trail, the icon framebuffer arithmetic, AND the icon-rotation hypothesis under test. Any future Y-coord tuner has the math right there in the source. **Lesson: when a derivation involves multiple non-obvious transforms (lens flip + glyph rotation + font-height anchoring), document the WORKED EXAMPLE in code — not just the formula. The next agent (or future me) won't have to re-derive from scratch.**

**Process notes:**

- **Fifth release under the bundled-bump directive.** `CURRENT_PROJECT_VERSION 30 → 31` + `xcodegen generate` + Info.plist placeholder verification (all 4 targets) in the same PR. Pattern fully stable now across Laughlin (rc12), me (rc13, rc14, rc15, rc16).
- **First release under the CodeQL-skip directive** (codified by Scribe today in `.squad/skills/release-mechanics-ci-polling/SKILL.md`). Merged via `gh pr merge <n> --admin --squash --delete-branch` once required non-CodeQL checks passed.
- **172 tests pass** (was 167 in rc15). Net: +5 added (3 `imgDisplay` encoder byte-pin tests, 1 icon-geometry test, 1 icon-ID test); 6 HR-formatter tests retargeted from " bpm" → no-suffix; 4 layout-shape tests rewritten for the new 11-frame sequence; 1 lens-flip formula test renamed `_rc16` and pinned to the corrected formula.

---

### Cross-Agent Note (via Scribe, 2026-05-19)

**From Richards's rc13→rc16 review:**
- **Recommendation #2:** Extract the font-metrics table into typed code. Font heights + per-glyph advance widths currently live in prose comments ("Font 3 = 64 px", "Font 2 ≈ 18 px/char"). The rc15→rc16 cycle's root cause was a height under-estimate; the next cycle's likely failure is a width under-estimate (long pace + 3-digit HR collide on line 1). A small `ALookFontMetrics` value type sourced from the Visual-Assets repo README, with a layout-asserting test, would prevent the next coordinate-system regression.

**Action:** If Joe directs font-metrics or coordinate-system work, this is a concrete improvement flagged for the next release cycle. Hardcoding is currently OK but a regression vector.

