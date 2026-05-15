# Amber — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** QA & Fitness Domain
- **Joined:** 2026-05-14T18:30:31.658Z

## Active Learnings

### 2026-05-15T14:01:55-04:00 — Rebase + reconciliation onto post-#5+#7 main (PR #6)

Both Weiss (#5 `feat/ble-wrapper`) and Laughlin (#7 `feat/workout-controller`) merged into `main` while my mocks PR was still open. My branch was `CONFLICTING`; my stub protocol files duplicated the canonical types those PRs landed. Notes for future parallel-spawn → independent-merge → final-reconciliation flows:

- **Three-way collision audit before rebasing.** `git fetch && git log origin/main` confirmed both PRs on main. Then `grep -lR <stub-type-name>` against the merged tree showed which of my protocol stubs were now duplicated by canonical types: `Protocols/GlassesConnection.swift` redeclared `GlassesConnectionState` (canonical: `Glasses/GlassesConnectionState.swift` from #5), and `Protocols/HealthKitSubstrate.swift` shadowed `Workout/WorkoutHealthSubstrate.swift` from #7. The collisions weren't textual conflicts — they were *redeclaration* errors that only surface once you try to compile. Always grep-audit type names before assuming `git rebase` covers it.
- **`git checkout --ours` for the file that gets dropped wholesale.** My stub `WorkoutController.swift` had to vanish in favour of Laughlin's full implementation; `git checkout --ours` (since rebase swaps `ours`/`theirs` from intuition) on the conflicted file took main's verbatim. Same trick for `Package.swift` where main's `.macOS(.v14)` superseded my `.macOS(.v13)`.
- **Adapt mocks to the **canonical** surface, never the other way around.** `MockGlassesFrame` had to lose `pushLayout`/`updateMetric(_:value:)` (my invented surface) and pick up `selectLayout(id:)` + `updateField(_:HUDFieldUpdate)` + `statusEvents()` from `GlassesFrameTransport`. `FakeHealthKitSubstrate` had to switch from `start`/`metrics()`/`phases()` to `begin(sport:startedAt:)`/`pause(at:)`/`resume(at:)`/`end(at:) -> WorkoutHealthResult` with `nonisolated let stateEvents/metricEvents` stored properties (matching Laughlin's `InMemoryWorkoutHealthSubstrate` shape).
- **Richer mock vs. simpler stub — both belong in the test target.** Weiss's `StubGlassesTransport` and Laughlin's `InMemoryWorkoutHealthSubstrate` are the canonical "happy-path" doubles meant to live in `ARRunnerCore` for SwiftUI previews and basic unit coverage. Mine (`MockGlassesFrame`, `FakeHealthKitSubstrate`) live in the test target and add scenario controls that the simpler doubles deliberately don't carry: explicit `simulateDisconnect`/`simulateReconnect`, one-shot failure injection on connect/selectLayout/updateField, pre-canned scenario replay (steadyRun/intervals/explicit). When to reach for which: prototyping or covering the happy path → use the canonical stub; exercising D4 corner cases (drop reasons, reconnect timing, connect-failure-at-start) or D9 stable-UUID round-trips → use my richer mocks.
- **Integration test must wire mocks through the canonical controller.** Laughlin's `WorkoutController(substrate:)` does NOT take a glasses transport — glasses signals reach it through `reportGlassesSignal(_:)`. So the integration test now subscribes to `glasses.connectionStates()`, maps each state through `GlassesConnectivitySignal.from(_:)`, and forwards into the controller. That bridge is what makes the D4 happy path exercisable end-to-end with the real controller.
- **Region-based isolation checker bug on `Self`-capture in cross-actor closures.** Putting the metric-formatter as `Self.formatMetric(...)` inside a `Task { for await metric in stream { ... } }` triggered `error: pattern that the region-based isolation checker does not understand how to check. Please file a bug` (Swift 6.0). Workaround: hoist the formatter out to a free file-private function (`formatMetricImpl`) so the closure no longer captures the non-`Sendable` `XCTestCase` subclass type. Worth knowing — the bug recurred with both `[glasses]` capture lists and `async` helper signatures; only de-`Self`-ing fixed it.
- **Preserved the prior Scribe commit through rebase.** My branch already had a Scribe session-log commit on top; using `git rebase main` (default — picks both commits in order) replayed mocks first, then Scribe untouched. No interactive surgery needed once conflicts resolved.

47/47 swift tests pass post-rebase, including 6 new integration tests in `WorkoutControllerIntegrationTests`.

### 2026-05-15T14:33:20-04:00 — v0.2 #4 anticipatory D4 resilience tests (PR #8)

Wrote `DisconnectResilienceTests.swift` BEFORE Weiss + Laughlin implement the auto-reconnect / haptic surface. Patterns worth keeping:

- **`XCTSkipIf(true, "EXPECTED-FAILING-UNTIL: ...")` is the right anticipatory-test idiom under XCTest.** It (a) keeps CI green, (b) leaves the test body compiled and live so it doesn't bit-rot, (c) makes the "delete this one line when the impl lands" workflow obvious to the reviewer. Cleaner than commenting tests out, cleaner than skipping the suite. Swift Testing's `.disabled` would be slicker but the rest of the codebase is XCTest, so don't mix.
- **Contract gaps belong in the test docstring AND in `decisions/inbox/`.** The test docstring tells a code reviewer "here's what's expected"; the inbox entry tells the implementing agent "here's the menu of fixes." Both reference the same test name so they cross-link.
- **Always wait for the bridge task to forward signals before asserting controller state.** First pass had three real failures (not the expected ones) because I asserted `controller.recordedDisconnectCount() >= 1` immediately after `simulateDisconnect`. The bridge `Task { for await state in stream }` runs on its own scheduler and the test thread races it. Fix: every cross-actor signal forwarding assertion goes inside a `waitUntil { … }` that polls the *consuming* side's observable state, not the *producing* side. Same applied to status-event collection (`statusCollector.droppedCount == N`).
- **Test the "exactly N" contract on both ends of the stream.** For multi-cycle disconnect/reconnect: assert N drops on the transport's `statusEvents()` AND N count increments on `controller.recordedDisconnectCount()`. Mismatches between those numbers are exactly the kind of bug the haptic-1:1 contract needs to catch.
- **Don't blindly delete unstaged WIP from another agent's branch.** When I checked out my branch, Weiss's uncommitted v0.2 BLE work travelled with the working tree (it was on `feat/v02-ble-activelook` HEAD). Stashed it with a clearly-labelled message (`weiss-wip-on-ble-activelook`) instead of nuking. Restore it with `git stash apply stash@{N}` after switching back. Skill writeup queued: see `.squad/skills/anticipatory-contract-tests/`.
- **Resilience contract gaps surfaced (also in inbox entry):** auto-reconnect surface absent on `GlassesFrameTransport` (Weiss); no layout auto-re-apply post-reconnect (Weiss); `glassesDisconnectCount` is global not session-scoped (Laughlin); no dedicated `controller.alerts` stream for haptic triggers (Laughlin); `reportGlassesSignal` mutates state even in `.ended` phase (Laughlin, low pri).

PR #8 ships 7 anchoring tests + 3 expected-failing skip-marked tests. `swift test` → 57 pass / 3 skipped / 0 fail.

## Archive

See `history-archive.md` for earlier 2026-05-14 learnings (scaffold validation, CI toolchain, integration mocks v0.1, PR #4 nit follow-up).
