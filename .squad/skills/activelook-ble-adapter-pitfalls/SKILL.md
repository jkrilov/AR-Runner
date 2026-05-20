# Skill: ActiveLook BLE Adapter Pitfalls (watchOS, v0.2)

**Owner:** Weiss
**Domain:** AR Integration / ActiveLook / CoreBluetooth on watchOS
**Last updated:** 2026-05-15

## When to reach for this

You are wiring or extending an `ActiveLookGlassesAdapter`-style transport
on watchOS, or reviewing a PR that touches the ActiveLook GATT profile or
wire format. You have already read
`.squad/skills/watchos-corebluetooth-swift6-actor/SKILL.md` for the actor
plumbing pattern and want the **vendor-specific** gotchas.

## Hard facts (re-verified 2026-05-15 against SDK v4.5.5)

- **No watchOS target in the official iOS SDK.** Manifest is iOS-only,
  singleton wraps `UIApplication` notifications, image helpers use
  `UIImage`. Do not try to port; reimplement the BLE layer directly on
  CoreBluetooth.
- **Custom service UUID:** `0783B03E-8535-B5A0-7140-A304D2495CB7`.
- **Standard Battery Service is separate.** ActiveLook publishes the
  standard BLE Battery Service (`0x180F` / `0x2A19`). You must discover
  it explicitly — it is not nested in the custom command service.
  Forgetting this leaves your battery-level handler as dead code.

## Wire-format pitfalls

| Command | Wrong shape (don't!) | Right shape |
|---|---|---|
| `0x62` displayLayout | `[id, utf8(text)…, 0x00]` | `[id]` only — push initial content via `0x3A` widgetUpdate. |
| `0x3A` widgetUpdate | (correct in v0.1) | `[layoutID, fieldIndex, utf8(value)…, 0x00]` |
| Length encoding | always 1 byte | bit `0x10` of the format byte selects 2-byte big-endian length. Always check `oneByteTotal > 0xFF`. |
| Frame end | "any byte" | terminator is exactly `0xAA`. Tests should assert this. |

## CoreBluetooth on watchOS — adapter checklist

1. `discoverServices([commandService, batteryService])` — both, not just one.
2. `discoverCharacteristics(...)` separately for each service.
3. Gate the `.connected` transition on the **command service's** RX
   characteristic, not the battery one. Battery arrives later.
4. `setNotifyValue(true, ...)` for TX, control, and battery
   characteristics. Issue an explicit `readValue(for:)` for battery so
   you get an initial level without waiting for the next push.
5. `writeValue(... type: .withResponse)` is the safer default until
   profiled on real hardware. Switch to `.withoutResponse` only after
   measuring write throughput on the bench.
6. After a drop and reconnect, **re-apply the active layout** before
   resuming field updates — the glasses forget the active layout when
   the link drops.

## Adapter wiring pattern (DEBUG vs hardware)

Don't sprinkle `#if DEBUG` across the SwiftUI layer. Centralise the
choice in one factory:

```swift
enum GlassesTransportFactory {
    static func makeDefault() -> any GlassesFrameTransport {
        #if targetEnvironment(simulator) || DEBUG
        return StubGlassesTransport()
        #else
        return ActiveLookGlassesAdapter()
        #endif
    }
}
```

The view model takes an *optional* `(@Sendable () -> any GlassesFrameTransport)?`
closure so previews can omit it entirely without smuggling fake state.

## Workout-lifecycle integration

Per D4, **never block workout start on `transport.connect()`**. The
correct shape:

```swift
if let transportFactory {
    let transport = transportFactory()
    self.transport = transport
    attachGlasses(transport: transport)         // forward state stream
    Task.detached { [transport] in
        try? await transport.connect()           // fire-and-forget
    }
}
```

`attachGlasses(...)` already exists on the view model; it forwards the
connection-state and status streams into `WorkoutController` as
`GlassesConnectivitySignal` so the HUD-online indicator and disconnect
counter update without coupling the workout to the link being up.

## Hardware-test scaffold

Hardware tests should compile to nothing on CI:

```swift
#if AR_RUNNER_HARDWARE_TESTS
import XCTest
@testable import ARRunnerWatch
final class FooHardwareTests: XCTestCase { /* … */ }
#endif
```

Run locally with `OTHER_SWIFT_FLAGS='-D AR_RUNNER_HARDWARE_TESTS'`. CI
runs (Linux SPM + macOS xcodebuild matrix + CodeQL) never see the
symbol so the matrix stays green without a paired pair on the bench.

## Don't bother

- Trying to add `.watchOS(.v11)` to the ActiveLook iOS SDK manifest.
  UIKit is everywhere and the SDK's BLE layer is what you're already
  reimplementing.
- Adding a phone-relay path "just in case." watchOS CoreBluetooth on
  watchOS 11 is fully featured for central role; the radio works while
  an `HKWorkoutSession` is active. No relay needed.
- Holding `CBPeripheral` references across the actor boundary without
  `@preconcurrency`. CoreBluetooth types are not formally `Sendable`;
  the import-with-`@preconcurrency` escape hatch is documented as the
  Swift 6 path until Apple updates the framework.

## Test-side gotcha: `AsyncStream` is single-consumer

When writing integration tests that bridge metrics from a substrate into a
`MockGlassesFrame`, **do not iterate the substrate's raw metric stream
directly** if the system-under-test (e.g. `WorkoutController`) already
iterates it. Swift's `AsyncStream` delivers each yielded value to whichever
iterator calls `next()` first — it is *not* broadcast. Two competing
iterators race, and the loser sees nothing.

**Symptom:** macOS CI green; Linux CI fails the "metric updates reach
glasses before disconnect" assertion at exactly the `waitUntil` deadline
(the substrate's emissions all got drained by the controller's forwarder
before the test bridge woke up). Linux's scheduler is the trigger, the race
is the cause.

**Fix:** Subscribe the test bridge to the controller's *re-published*
stream (e.g. `controller.metrics`). The controller already fans values out
on its own continuation inside `ingest(metric:)`; the test gets a clean
fan-out point and stops fighting the SUT for individual emissions. This is
also the more correct layering — glasses display reflects what the
controller has accepted, not raw substrate output.

If a future scenario genuinely needs N independent consumers of the same
upstream, reach for `AsyncChannel` or `AsyncBroadcastSequence` from
`swift-async-algorithms`. Don't try to multiplex a bare `AsyncStream`.

**Heuristic:** "macOS passes, Linux fails at the waitUntil deadline" is
almost always a hidden race, not a slow-CI timeout. Bumping the timeout
hides the bug; fixing the fan-out kills it.

## Auto-reconnect loop — pitfalls and contract (v0.2 #4)

The full D4 auto-reconnect contract is more than just "exponential backoff":

1. **Cap the loop.** Without a max-attempts cap, a powered-off pair of
   glasses keeps the radio busy for the entire workout. Cap at ~30 attempts
   with the default backoff (≈230 s of attempts before terminal failure).
2. **Emit a terminal event.** Add `.reconnectAbandoned(attempts:)` to the
   status-event enum so observers can distinguish "give up" from "still
   trying" and run-metadata can log it. Per D4 the workout still continues —
   the terminal event is informational, not a workout abort.
3. **Re-apply layout on reconnect.** The glasses **forget** the active
   layout on link drop. Pre-seed `activeLayoutDeviceID` (from
   `RunningHUDPreset.default` or whatever the user picked) and unconditionally
   re-write it in `handleCharacteristicsDiscovered` after the connect
   transition. One code path covers both "first connect" and "post-drop
   reconnect."
4. **Cancel on actor `deinit`.** `Task.cancel()` is nonisolated, so
   `deinit { reconnectTask?.cancel() }` is legal in Swift 6. Belt-and-
   suspenders alongside the `[weak self]` capture in the loop body.
5. **Cancel on user-initiated `disconnect()`.** Set a
   `userDisconnectRequested = true` flag and check it inside the loop —
   cancelling the Task alone is not enough because the loop may already
   have started a `beginConnect()` that won't unwind on cancellation.

## `RunningHUDPreset` — preset → BLE bytes contract (v0.2 #5)

The watch app applies `RunningHUDPreset.default` on connect; there is no
picker UI in v0.2 (Joe locked scope to backend only). When extending:

- **`layoutDescriptor() -> [UInt8]?`** is the public contract. Callers don't
  reach into `ActiveLookCommand` — they get pre-encoded `0x62 displayLayout`
  bytes ready to write to the RX characteristic.
- **`Optional` is intentional.** Returning `nil` flags presets that aren't
  in `CuratedLayoutCatalog`. Treat as a configuration error; do NOT silently
  ship `0x00` to the glasses.
- **Stable `rawValue`s.** They will become persisted preferences when the
  picker ships. Locked by `testAllCases_HaveStableRawValuesForPersistence` —
  rename only with a migration story.
- **Wiring lives in the adapter, not the view model.** Pre-seed
  `activeLayoutDeviceID` from the preset in `init`; the existing post-
  reconnect re-apply path then handles initial connect AND every reconnect
  with one code path. View-model-side selection would skip the post-
  reconnect re-apply unless you also re-wired a re-select on `.reconnected`
  events.

## Mock-augmentation pattern: opt-in flags beat default-behavior changes

When you need to add real-adapter-style behavior to a shared mock (e.g.
`MockGlassesFrame` adding auto-reconnect), prefer **opt-in init flags**
over flipping the default behavior:

```swift
public init(
    failures: MockGlassesFailureConfig = MockGlassesFailureConfig(),
    autoReconnect: Bool = false,       // ← opt-in
    autoReconnectDelay: TimeInterval = 0.05,
    autoReapplyLayout: Bool = false,   // ← opt-in
    clock: @escaping @Sendable () -> Date = { Date() }
)
```

Flipping defaults breaks anchor tests that drive `simulateDisconnect` +
`simulateReconnect` manually. Opt-in flags isolate the blast radius to the
test that needs the new behavior.

## Adding cases to public `Sendable` enums in Core

Before adding a case (e.g. `GlassesStatusEvent.reconnectAbandoned`),
grep for `switch event` + `case .` patterns. If every callsite has a
`default:` clause or uses `if case` pattern matching, the addition is
source-compatible. Otherwise it's a breaking change and you need either
a migration or a new sibling enum.

In practice, code paths in `WorkoutViewModel`, `StubGlassesTransportTests`,
and the resilience-test event collector all use `if case` or `switch
{ case .x; default }`, so additive enum changes have been safe so far.

## Per-link subscriptions (rc17 ADR — `richards-adr-ble-link-lifecycle`)

Characteristic subscriptions (HUD writes, flow-control notify, battery
0x2A19 notify, future HR push, …) are properties of **the link**, not of
the workout. They are established on every `.connected` transition
(initial and every auto-reconnect) and survive every workout boundary.

Anti-patterns to reject in code review:

- A `setNotifyValue(true, …)` call inside `WorkoutController.start` or
  `WorkoutViewModel.start`. Move it into the adapter's connect path.
- A `transport.disconnect()` call inside a workout-shutdown path
  (`confirmSave`, `confirmCancel`, `end`). The only legal call sites are
  the explicit user "Disconnect Glasses" affordance and the adapter's
  own unrecoverable-error teardown.
- Re-subscribing characteristics from scratch on workout-start. Symptom:
  2-5 s of "blank glasses" lag at every run start — the cost of the
  subscription that should already be live.

The generalised pattern lives at
`.squad/skills/paired-hardware-lifecycle-contract/SKILL.md`.

## Battery characteristic dedup + range guard (rc17)

The standard Battery Service (0x180F / 0x2A19) re-publishes the same
percent on the ~30 s notify cadence more often than not. The adapter
funnels every raw byte through `BatteryLevelFilter` (Core) instead of
emitting `.batteryLevel` directly. Three semantic actions:

| Input byte | Action |
|---|---|
| `0`–`100`, differs from last emitted | `.emit(Int)` |
| `0`–`100`, equals last emitted | `.dropDuplicate` (silent) |
| `> 100` | `.dropInvalid(rawByte:)` — log warning, drop |

`filter.reset()` is called on **every** transition out of `.connected`
(drop, user disconnect, `handleDisconnect`). Rationale: the UI clears
the value during a gap; the first post-reconnect read deserves a fresh
emit even when the percent hasn't moved. Keeping the filter alive across
a drop would silently suppress that first re-emit and the UI would sit
on "—" forever.

If a future PR wants to keep the last-known battery visible across a
drop, the right place is the *consumer* of the stream (WC sender, UI
view-model), not the filter. The filter's job is "what does the BLE
link say *right now*."

## Reconnect schedule (rc17 ADR)

The canonical reconnect cadence is `ExponentialBackoff.adrV04`
(1 → 2 → 4 → 8 → 16 → 32 → 60 s, capped at 60 s steady) paired with
`maxReconnectAttempts: .max`. Rationale per the ADR:

- A pair of glasses left in a drawer must reconnect when retrieved
  without UI intervention — capping attempts at 30 was wrong.
- The 60 s ceiling is what bounds radio cost (≈ 1 attempt / minute);
  the attempt counter does not need to.
- Workout state is irrelevant to the reconnect loop. Drops mid-run and
  drops mid-idle follow the same schedule.

Tests can still inject `maxReconnectAttempts: 1` (etc.) to exercise the
terminal `.reconnectAbandoned` path without waiting for the unbounded
default.

## View-model: observer tasks are TRANSPORT-scoped, not workout-scoped (rc3)

Symptom — Joe rc2 finding #4: discard a run → glasses BLE link physically
drops → watch UI still shows "Glasses: Connected" → tapping Disconnect
does nothing → only an app restart recovers.

This is **not** a transport bug. It is a view-model lifecycle bug. Things
to remember when wiring an `AsyncStream`-based BLE observer to a SwiftUI
view-model in this codebase:

1. **Two distinct lifetimes coexist on `WorkoutViewModel`.** Workout-scoped
   tasks (`stateTask`, `metricTask`, `elapsedTask`, `tickTask`) end on
   every save/discard. Transport-scoped tasks (`glassesStateTask`,
   `glassesStatusTask`) MUST live as long as the transport instance does.
   Mixing them in a single `stopRuntimeTasks()` is the bug.

2. **If you cancel a transport-state observer at workout end, you also
   need to recreate it at workout start.** Our `start()` reuses an
   existing transport without re-calling `attachGlasses` — there is no
   re-creation site, so once cancelled the observer is gone for the
   life of the VM. Easy mistake. Either guarantee re-attach on every
   start *or* (preferred, ADR-1 aligned) never cancel.

3. **"Disconnect button does nothing" is a tell-tale UI-only symptom.**
   The adapter's `disconnect()` is synchronous about transitioning to
   `.disconnected` and tears down the CB connection. If the user sees
   no UI change, the suspect is almost always the consumer of
   `transport.connectionStates()`, not the producer.

4. **Test rule:** whenever a fix changes which tasks `stopRuntimeTasks()`
   cancels, add an XCTest (or hardware integration check) that drives
   `start → confirmSave → externally toggle link state → assert
   `glassesLinkState` reflects the new state`. We don't have a watch
   unit-test target yet, so the rationale comment block on
   `stopRuntimeTasks()` is currently the load-bearing artifact. Don't
   delete it without a replacement test.

