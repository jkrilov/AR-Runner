# Weiss — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** AR Integration
- **Joined:** 2026-05-14T18:30:31.656Z

## Learnings


## Summary
Pre-RC5 development and audits (2026-05-14 through 2026-05-17) archived in history-archive.md.

## Active Sessions (Compacted)

### 2026-05-18T22:30:00Z — rc5 release: HUD power-on fix shipped
- PR #53 carried the HUD power-on handshake fix into `v0.3.0-rc5`; CI was green, but later hardware feedback proved the hypothesis incomplete.
- Keep this milestone as the point where HUD failures became clearly end-to-end path problems, not isolated command-content bugs.

### 2026-05-18T23:00:00Z — lockout after rc5 failure
- After two failed HUD hypotheses, lockout transferred diagnosis to Richards; the real failure was delivery-layer protocol handling: no `didWriteValueFor` serialization and no flow-control-notify gate.
- Durable lesson: for ActiveLook, the vendor SDK write path is canonical. Read it before forming command-content hypotheses.

### 2026-05-19T09:00:00Z — v0.4.0 queued
- v0.4 planning kept glasses scope intentionally light: raw `txt` plus `imgDisplay` primitives, with the rc9 seven-PR stack as the reference implementation.
- The old curated-layout bugs are dormant until gesture-driven layout work returns.

### 2026-05-19T15:05:00Z — bundle-bump directive
- From rc12 onward, feature/fix PRs must carry the `CURRENT_PROJECT_VERSION` bump and `xcodegen generate` output in the same PR; no separate bump PR.
- Release checklist remains `.squad/skills/release-mechanics-bundle-bump/SKILL.md`.

### 2026-05-19T15:55:00Z — blank symptoms can mean coordinate errors
- Blank `txt` with no 0xE2 usually means off-screen clipping, especially with `rotation=4` + `topLR`; validate the full bounding box in framebuffer space first.
- Use the lens-flip transform `x_wearer = 303 − x_fb` when reasoning between wearer and framebuffer coordinates.

### 2026-05-19T19:45:00Z — rc1 battery service
- Battery telemetry rides the standard Battery Service (0x180F/0x2A19) alongside the ActiveLook custom profile, with immediate `readValue` after notify and WatchConnectivity mirroring as a phone-optional side channel.
- Scope guard: battery stays phone-side only; no HUD layout changes.

### 2026-05-19T18:30:00-04:00 — rc17: adapter audit per ADR + battery filter
- Adapter teardown was already clean relative to the BLE-link ADR; the substantive changes were `ExponentialBackoff.adrV04`, effectively unbounded reconnects, and `BatteryLevelFilter` for range-check/dedup plus reset-on-drop.
- **Future-Weiss should remember:**
  - The bare `setNotifyValue(true, for:) + readValue(for:)` pair is the entire battery subscription contract on watchOS; CoreBluetooth writes the CCCD automatically.
  - `BatteryLevelFilter.reset()` is where “link drop = UI clears” semantics live; keep last-known battery policy in the consumer, not the filter.

### 2026-05-20T10:55:00-04:00 — rc2 finish-screen coord spec
- Chose a fixed-anchor two-write pattern for the shared time/pace line, pinned Y coords under `y_fb = 255 − wearer_top`, and identified rc1 cut-off as a likely X-overflow bug rather than a Y bug.
- **Future-Weiss should remember:**
  - The “two text writes with a fixed second anchor” pattern is the workaround until `ALookFontMetrics` lands.
  - Add X-extent assertions alongside Y-extent assertions for finish/banner strings.

---

### 2026-05-20T12:42:23-04:00 — rc3: BLE-link UI-freeze on discard (observer-scope fix)

**Context:** Joe's rc2 bench finding #4 — discarding a run leaves the watch chip on "Glasses: Connected" while the BLE link is dead, and the Disconnect button is inert. Only killing the app recovers. Laughlin owns the discard-returns-to-start-screen workout state machine in parallel; my half was the BLE/observer-lifecycle audit.

**Root cause (single line, but architectural):** `WorkoutViewModel.stopRuntimeTasks()` — called by both `confirmSave()` and `confirmCancel()` — cancelled `glassesStateTask` and `glassesStatusTask` alongside the workout-scoped tasks. These two are the only consumers of `transport.connectionStates()` / `statusEvents()`. The `start()` path reuses an existing transport without re-calling `attachGlasses`, so once cancelled they were gone for the VM's lifetime. ADR-1 held at the transport layer (no `disconnect()` calls from workout-end paths) but was being violated at the observer layer.

**Symptoms it produced:**
- UI shows stale `.connected` because nothing forwards transport-state changes into `glassesLinkState` anymore.
- `disconnectGlasses()` actually disconnects the link (`cancelPeripheralConnection` runs and transitions to `.disconnected`), but the VM never sees the new state, so “Disconnect button does nothing” is purely UI not reflecting the underlying tear-down.
- `connectGlasses()` early-returns on the stale `.connected` read.
- App restart rebuilds the VM and re-attaches the observers, so a clean relaunch is the only recovery — exactly what Joe reported.

**Whether the BLE link physically drops on discard is a separate question** (it almost certainly does — watchOS suspends CoreBluetooth once `HKWorkoutSession` ends and the app loses extended runtime), but that doesn't matter once the observer survives: the UI will simply follow the link to `.disconnected`, the Disconnect button becomes a no-op-but-visible, and Reconnect actually works because the short-circuit on `.connected` no longer fires.

**Fix:** Remove `glassesStateTask?.cancel()` and `glassesStatusTask?.cancel()` from `stopRuntimeTasks()`. The `attachGlasses` cancel-then-replace pattern at the top of that method remains the only sanctioned cancellation site for these tasks. A rationale comment block on `stopRuntimeTasks()` carries the contract forward (no watchOS unit-test target yet).

**Coordination with Laughlin:** Touched only `stopRuntimeTasks()` in `WorkoutViewModel.swift` — no edits to `confirmSave` / `confirmCancel` state machine code, no edits to `launchState` cases, and no changes to discard navigation/state behaviour. Laughlin's parallel work on discard-returns-to-start is uncoupled from this fix.

**Scope guards held:** No edits to adapter internals, `write()` serialization, flow-control gate, queryID stamping, cfgSet, HUD encoders, rotation, lens-flip coords, the rc1/rc2 finish-screen path, or v0.4 metric routing. No package version bump in this PR (bundled into the rc3 fix train Laughlin is assembling).

**Tests:** 195/195 ARRunnerCore tests still pass. No watchOS unit-test target exists yet, so the regression guard is the rationale comment + decision record. If/when a watch test target lands, the regression case is `start → confirmCancel → toggle link state on adapter under test → assert glassesLinkState updates`.

**Two things future-Weiss should remember:**
- **Two lifetimes coexist on the workout view-model.** Workout-scoped observation tasks (state/metric/elapsed/tick) end at every save/discard. Transport-scoped observation tasks (`connectionStates` / `statusEvents`) live as long as the transport does. Any cleanup helper that touches both is a bug waiting to happen.
- **“Disconnect button does nothing” is a UI-observer symptom, not an adapter symptom.** The adapter's `disconnect()` transitions state synchronously and tears down the CB connection. If you can't see the effect, inspect the consumer of `transport.connectionStates()` before suspecting CoreBluetooth or the adapter.

**Decision filed:** `.squad/decisions/inbox/weiss-rc3-ble-observer-transport-scoped.md`.
**Skill updated:** `activelook-ble-adapter-pitfalls` — new "View-model: observer tasks are TRANSPORT-scoped, not workout-scoped (rc3)" section.

---
