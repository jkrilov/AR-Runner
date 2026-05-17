# ActiveLook + BLE + AR Audit — 2026-05-16

**Auditor:** Weiss (AR Integration). Read-only. Scoped to ActiveLook /
CoreBluetooth / glasses HUD only — watchOS app shell + HealthKit are
Laughlin's, CI is Richards's, mocks are Amber's.

> Merged pass: incorporates the earlier sonnet-4.6 spawn's findings on
> per-reconnect `CBCentralManager` churn, dropped RSSI, and CB error-code
> drift; adds the unwired per-tick HUD path, scan-timeout task race, and
> silent layout re-apply errors that pass missed. Last-writer-wins per
> task directive.

## Summary

The BLE wrapper is architecturally sound: pure-Swift wire encoder lives
in Linux-buildable Core, an actor adapter owns all mutable state, a
nested `Coordinator` bridges the CB delegate boundary on a dedicated
queue, D4 auto-reconnect with capped backoff is implemented, and
`RunningHUDPreset` auto-applies on every (re)connect via one code path.
Wire-format regressions caught in v0.2 #1 (battery service discovery,
`0x62` framing) are now pinned by tests. The biggest hole is
**integration, not BLE**: the per-tick HUD field-update path is not
wired into the workout pipeline, so today the glasses get an initial
layout activation and then go silent for the rest of the workout.
Secondary concerns are `CBCentralManager` re-instantiation on every
reconnect attempt (up to 30 stale managers per workout), an untracked
scan-timeout task that can fire spuriously across reconnect cycles, and
discarded `controlChar` / RSSI notifications.

## ActiveLook SDK Integration

| Item | Finding |
|---|---|
| SDK import | No vendor SDK. `ARRunnerCore/Package.swift:11-39` has zero deps. iOS SDK v4.5.5 is UIKit-coupled; no watchOS target — direct CoreBluetooth is the right call (per spike + 2026-05-15 re-verification). |
| Version pinned | N/A — nothing to drift. No transitive StrictConcurrency churn either. |
| Patches / deprecated APIs | None. Command surface covers v0.1 (power/clear/luma/layout/widget/text/battery). |
| Wire-format encoder | `ActiveLookCommand.encode` (`ARRunnerCore/Sources/ARRunnerCore/Glasses/ActiveLookCommand.swift:83-111`) is Foundation-only, Linux-buildable. 1/2-byte length promotion via the format byte's `0x10` bit handled correctly (lines 89-94). `luma` clamps 0–15 (line 57). Frame footer `0xAA` in place. |
| GATT UUIDs | Single-sourced in `ActiveLookGATT` (`ActiveLookCommand.swift:119-130`) as plain strings; `CBUUID(string:)` wrap happens only at the watchOS boundary. ✅ |
| Concurrency annotations | `@preconcurrency import CoreBluetooth` at `ActiveLookGlassesAdapter.swift:5` is the only preconcurrency hop and is justified — CB delegate types aren't formally `Sendable` in iOS 18 / watchOS 11 SDKs. `Coordinator: @unchecked Sendable` (line 440) is contained to a stateless forwarder — acceptable. |
| `StrictConcurrency` flag drift | **Clean.** `Package.swift` documents at line 4 that `.enableUpcomingFeature("StrictConcurrency")` is a hard error under Swift 6.0 and uses `.swiftLanguageMode(.v6)` instead. Past landmine — do not re-introduce. |
| Curated device-ID catalog | **Placeholder values** `0x01/0x02/0x03` in `CuratedLayoutCatalog.mapping` (`ReconnectPolicy.swift:39-43`). Real IDs depend on Config-Generator output (D6). |

## BLE / CoreBluetooth Patterns

**Threading.** Single actor owns state; `Coordinator` forwards CB
callbacks on a private `DispatchQueue("com.arrunner.watch.activelook.ble")`
into the actor via `Task { await … }`
(`ActiveLookGlassesAdapter.swift:155-158, 440-507`). Continuations are
the only mutable hand-off. Clean.

**Discovery & state machine.**

- Scan filtered to ActiveLook service UUID (line 187) — power-efficient,
  watch-radio-friendly.
- `options: nil` (line 187) — no `allowDuplicates`. Correct for v0.2.
- `@unknown default` on `CBManagerState` (line 178) future-proofs against
  new states.
- `.connected` transition is gated on the **command-service** RX
  characteristic only (line 271). Battery service arriving late won't
  race readiness.
- Service + characteristic discovery is now complete (v0.2 #1 fix):
  both `commandService` and `batteryService` are discovered
  (lines 212-215); battery char is `setNotifyValue(true)` AND
  `readValue` (lines 257-262).

**Reconnect loop.**

- Backoff 1s → 2s → 4s → 8s (max), 30-attempt cap (~230s budget)
  matches spike doc. ✅
- `userDisconnectRequested` flag, in addition to `Task.isCancelled`,
  prevents reconnect after intentional disconnect (lines 110-113, 331).
- `deinit { reconnectTask?.cancel() }` (line 81) — `Task.cancel()` is
  nonisolated, so this is legal in Swift 6. ✅
- Emits `.reconnectAbandoned(attempts:)` + `.failed` on exhaustion
  (lines 335-337) per the v0.2 #4 contract.

**🐛 Debt — `CBCentralManager` re-created on every `beginConnect()`.**
`ActiveLookGlassesAdapter.swift:154-159` instantiates a fresh
`CBCentralManager` + `Coordinator` + `DispatchQueue` **per attempt**,
including each iteration of `runReconnectLoop` (up to 30). Old
managers/coordinators are silently overwritten but CB's internal queue
may still deliver delegate callbacks from the old instance after the
reference is dropped — stale callbacks land on a now-unowned coordinator.
Also: 30× `DispatchQueue` allocations per failed workout = churn.
**Fix (M):** Construct `CBCentralManager` + `Coordinator` + queue once in
`init`; reconnect should only reset peripheral/characteristic references
and call `centralManager.connect(peripheral, options:)` again, or
re-scan if the peripheral reference is gone.

**🐛 Debt — Scan-timeout task is not retained or invalidated.**
`startScan` (lines 189-192) spawns `Task { try? await Task.sleep(...) }`
without holding a reference; on reconnect, multiple stale timeout tasks
pile up. The guard at `timeoutScanIfStillScanning` (line 196) only
checks `case .scanning`, so a stale timer firing during a fresh scan
attempt can flip the adapter to `.failed` and resolve the in-flight
`pendingConnect` with a misleading `scanTimeout` error. **Fix (S):**
Track as `private var scanTimeoutTask: Task<Void, Never>?`; cancel on
scan-stop and on every state transition out of `.scanning`.

**🐛 Debt — Control-characteristic notifications subscribed but
discarded.** `controlChar` is `setNotifyValue(true)`
(`ActiveLookGlassesAdapter.swift:254-256`) but
`peripheral:didUpdateValueFor` only routes battery
(`ActiveLookGlassesAdapter.swift:498-507`). ActiveLook's control char
carries flow-control / write-readiness signals. With current
`.withResponse` writes this is moot; the moment the spike-doc-
recommended switch to `.withoutResponse` happens (post-bench-profile),
missing flow control becomes a frame-loss bug. Decide now: honor it
(preferred) or document why we ignore.

**🐛 Debt — RSSI discarded at discovery.** The coordinator receives
`RSSI` (line 456) but `handleDiscovered` is invoked with only the
peripheral (line 458). `GlassesStatusEvent.signalQuality(Int)` exists in
Core (`GlassesStatusEvent.swift:29`) but is never emitted — dead enum
case. Becomes meaningful when D9 side-store logging and any "weak
signal" UX land. **Fix (S):** forward RSSI through `handleDiscovered`
and emit a one-shot `.signalQuality(rssi)` event.

**🐛 Debt — Disconnect error-code mapping is fragile.**
`ActiveLookGlassesAdapter.swift:302-308` matches raw `nsError.code`
values `6, 7 → linkLoss`, `10 → peerPoweredOff`. These match
`CBError.peripheralDisconnected (6)`, `connectionTimeout (7)`,
`peripheralPoweredOff (10)` in current SDKs but the codes drift across
OS versions. **Fix (S):** prefer `CBError(_:)?` rawValue init and switch
on the typed enum.

**`writeValue(... type: .withResponse)`** (`line 371`) is the safer
default per spike §4 and skill notes. Don't switch to `.withoutResponse`
without honoring `controlChar` and adding
`peripheralIsReady(toSendWriteWithoutResponse:)` handling.

**Backoff has no jitter.** `ExponentialBackoff.delay`
(`ReconnectPolicy.swift:27-31`) is deterministic. Single-user is fine;
cheap fix (±20%) if we ever face simultaneous power-cycle scenarios.

**Background mode is correctly declared.**
`Config/ARRunnerWatch-Info.plist:29-33` lists `workout-processing` +
`bluetooth-central`, mirrored in `project.yml:53-55`. watchOS 11 has no
`restoreIdentifier` support — relying on `HKWorkoutSession` to license
the background radio is the spike-documented design.

## HUD & Draw-Loop Hygiene

ActiveLook renders autonomously from baked layouts; runtime traffic is
~20–40 byte field-value updates. There is no GPU/CPU draw loop on the
watch — the budget that matters is the BLE link.

**🚨 Debt — The per-tick HUD path is not wired up.**
`GlassesService.update(...)`
(`ARRunnerWatch/Glasses/GlassesService.swift:48-56`) exists, but
`GlassesService` is **never instantiated** anywhere in the watch app.
`WorkoutViewModel` constructs the transport directly
(`ARRunnerWatch/Workout/WorkoutViewModel.swift:120-127`) and only calls
`.connect()`. There is no callsite of `transport.updateField(...)`
outside `StubGlassesTransportTests` and the hardware test. Net effect:
on real hardware the glasses receive the pre-seeded layout activation on
connect and then **nothing for the rest of the workout**. This is the
single highest-impact gap in the AR surface and almost certainly the
first thing a hardware test will reveal.

**No rate limit / coalescer on `updateField` (when it is wired).**
`ActiveLookGlassesAdapter.swift:137-150` writes synchronously per call.
At 1 Hz × 4–5 fields = ~150 B/s (≈10% of practical ceiling) we are fine;
at higher rates or with the `telemetryRun` 6-slot preset there is no
backstop. Needed: per-`fieldIndex` last-write-wins coalescer + a
token-bucket / fixed-cadence drainer in the adapter or a service layer.

**`updateFields` default is serial** — one `writeValue` per call
(`GlassesFrameTransport.swift:52-56`). For 4 slots that is 4 framed BLE
writes per tick. Could be merged into a multi-slot frame; not v0.2-
urgent.

**`write(_:)` is `async throws` but synchronous internally.**
`ActiveLookGlassesAdapter.swift:360-362` — the `async` wrapper provides
actor-serialization but no backpressure. Document before adding any
bulk-write path.

## Error & Disconnect Handling

| Scenario | Behavior | Assessment |
|---|---|---|
| Glasses drop mid-workout | `handleDisconnect` → `.dropped` → `.reconnecting` → loop | ✅ D4 |
| Workout continues? | `Task.detached { try? await transport.connect() }` in `WorkoutViewModel.start` — fire-and-forget, never blocks workout | ✅ |
| Haptic alert | Debounced (10 s) and gated to `.running` | ✅ (`WorkoutViewModel.swift:247-271`) |
| HUD-offline hint | `hudOffline = true` on `.dropped` + `.reconnectAbandoned`; cleared on `.reconnected` | ✅ |
| BT off / unauth | `handleCentralStateUpdate` non-`.poweredOn` → `bluetoothUnavailable` + `.failed` | ✅ |
| Scan timeout | 15 s → `.failed` + `scanTimeout` (subject to stale-task race above) | ⚠️ |
| Layout re-apply on (re)connect | `activeLayoutDeviceID` pre-seeded from `RunningHUDPreset.default`; one re-apply path serves first connect + every reconnect | ✅ |

**🐛 Debt — Re-apply layout swallows errors.**
`_ = try? sendRaw(frame)` (`ActiveLookGlassesAdapter.swift:283`) loses
any error from the post-reconnect re-apply. If the RX char is in fact
unusable at that moment, the glasses sit with their forgotten-layout
state for the rest of the workout with no telemetry. **Fix (S):** emit
a new `GlassesStatusEvent.layoutReapplyFailed(error:)` so the side
store (D9) can log it.

**Status snapshot is partial.** `connectionStates()` replays the current
state to new subscribers (`ActiveLookGlassesAdapter.swift:36-42`), but
`statusEvents()` does not replay the last battery / signal level
(lines 44-49). A late-subscribing UI won't show battery until the next
push. Minor.

**No idle-disconnect / pause-suspension.** When the workout pauses,
there is no signal to stop pushing field updates (when wired) or to
drop the link to save the glasses' battery. Future work.

## Privacy & Permissions

| Key | Location | Status |
|---|---|---|
| `NSBluetoothAlwaysUsageDescription` | `Config/ARRunnerWatch-Info.plist:23-24` (mirrored `project.yml:52`) | ✅ Present; wording explains direct watch↔glasses use during workouts — App-Review-quality |
| `NSBluetoothPeripheralUsageDescription` | absent | ✅ Not required — central role only, iOS 13+ |
| `UIBackgroundModes: workout-processing` | `Info.plist:30-31` | ✅ Required for HK session |
| `UIBackgroundModes: bluetooth-central` | `Info.plist:31-32` | ✅ Required for BLE during workout |
| Phone BT permission | absent on phone | ✅ Phone owns no BLE per D1 |
| App Group (`group.com.arrunner.shared`) | declared on watch + phone + both widget extensions (`Config/*.entitlements`) | ✅ Used for HealthKit / widget data only; **not** used to share BLE state — correct per D1 watch-authoritative posture |

No gaps on the AR/BLE privacy surface.

## Currency (ActiveLook + CoreBluetooth, 2026)

| Component | In codebase | Latest known (2026-05) | Gap |
|---|---|---|---|
| ActiveLook iOS SDK | not imported (reimplemented) | v4.5.5, iOS-only | N/A — no watchOS target; CB direct remains the only path |
| ActiveLook GATT profile | per `Activelook-API-Documentation`, re-verified 2026-05-15 | stable, no v5 break | none detected |
| CoreBluetooth surface | watchOS 11 / iOS 18 | watchOS 11 / iOS 18 | `@preconcurrency import` still required — no new `Sendable` annotations on `CBPeripheral` / `CBCharacteristic` / `CBService` in 18.x SDKs. Re-audit after WWDC 26. |
| Swift language mode | `.v6` in `Package.swift:39` | Swift 6.3.2 (Xcode 26.5) | ✅ |
| Deployment targets | iOS 18 / watchOS 11 | current | ✅ |

**Not adopted (intentionally):** `CBCentralManagerOptionRestoreIdentifierKey`
(unsupported on watchOS); `CBPeripheral.maximumWriteValueLength(for:)`
(small frames never hit MTU at v0.2); `canSendWriteWithoutResponse` /
`peripheralIsReady(toSendWriteWithoutResponse:)` (mooted by current
`.withResponse` choice). All become relevant if/when we move the hot
path to `.withoutResponse`.

## Top 5 Debt Items (Prioritized)

| # | Item | Effort | Impact | File:Line |
|---|---|---|---|---|
| 1 | **Wire per-tick HUD updates.** `GlassesService.update(...)` is dead code; `WorkoutViewModel` connects then never calls `updateField`. Real glasses get an initial layout and silence for the rest of the workout. | M | 🔴 HIGH | `ARRunnerWatch/Glasses/GlassesService.swift:48-56` (unused); `ARRunnerWatch/Workout/WorkoutViewModel.swift:120-127` (no updateField path) |
| 2 | **Curated device IDs are placeholders** (`0x01–0x03`). Layout-bake step deferred; real hardware will activate wrong slots. Blocking for any meaningful hardware test. | M | 🔴 HIGH | `ARRunnerCore/Sources/ARRunnerCore/Glasses/ReconnectPolicy.swift:39-43` |
| 3 | **`CBCentralManager` re-created on every `beginConnect()`** including up to 30 reconnect iterations. Stale CB-queue callbacks possible; queue/coordinator churn. | M | 🟠 HIGH | `ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift:154-159` |
| 4 | **Throttle / coalesce `updateField`** before #1 lands or first hardware run will saturate the radio at higher rates; today there's no backstop. | M | 🟠 MED | `ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift:137-150`; `ARRunnerCore/Sources/ARRunnerCore/Protocols/GlassesFrameTransport.swift:44-56` |
| 5 | **Track + cancel the scan-timeout task; honor `controlChar`; surface re-apply errors; emit RSSI.** Four small, related fixes that close silent failure modes around scan/reconnect/flow-control. Group into one PR. | S each | 🟡 MED | `ActiveLookGlassesAdapter.swift:189-200` (timeout), `:254-256, 498-507` (controlChar), `:280-289` (re-apply `try?`), `:452-459, 202-208` (RSSI) |

**Effort key:** S = hours, M = 1–2 days, L = 1+ week.

### Bonus (not top-5 but worth a tracking issue)

- Replace placeholder `CuratedLayoutCatalog` IDs with Config-Generator
  output before TestFlight (subsumed by #2).
- Map disconnect errors via typed `CBError(_:)` instead of raw `nsError.code`
  (`ActiveLookGlassesAdapter.swift:302-308`).
- Add ±20% jitter to `ExponentialBackoff.delay`
  (`ReconnectPolicy.swift:27-31`).
- Replay last battery/RSSI to new `statusEvents()` subscribers
  (`ActiveLookGlassesAdapter.swift:44-49`).
- Suspend transport writes during workout `.pause()` to save glasses
  battery (after #1).
- Re-evaluate `@preconcurrency import CoreBluetooth` after WWDC 26 SDKs
  ship; if `CBPeripheral` becomes `Sendable`, drop the hop and convert
  `Coordinator` from `@unchecked Sendable` to proper `Sendable`.

## Out of Scope

- HealthKit / `HKWorkoutSession` lifecycle, watch SwiftUI views, haptic
  policy details — Laughlin.
- CI matrix / xcodegen / SPM-Linux split / GitHub workflows — Richards.
- `EnergyAccumulator` / `EnergyEstimator`, mock/test scaffolding beyond
  the BLE-adjacent `AsyncStream`-race already pinned in the
  `activelook-ble-adapter-pitfalls` skill — Amber.
- Phone-side `WorkoutMirrorView` / WCSession transport — read-only
  mirror per D5, not an AR debt surface.
