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
