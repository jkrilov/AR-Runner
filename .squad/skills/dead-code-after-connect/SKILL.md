# Skill: Dead-Code-After-Connect — fan-out wire with per-key throttle + connected-state guard

**Author:** Weiss (AR Integration)
**Established:** 2026-05-16
**Related:** `activelook-ble-adapter-pitfalls/SKILL.md`, `wcsession-three-tier-delivery/SKILL.md`

## Problem

A common shape in async-transport code: a transport adapter exposes both lifecycle (`connect`, `disconnect`) and a hot-path write (`updateField`, `send`, `publish`). The caller wires up `connect()` early during a session, the unit tests for the write path pass against a stub, and everyone moves on — but **no production callsite ever invokes the write path**. The transport is dead code from the moment `connect()` returns.

Observed instances:

- AR-Runner v0.2 audit P1.2: `GlassesService.update(...)` was unit-test-exercised in `StubGlassesTransportTests` but `WorkoutViewModel` only called `transport.connect()`. Glasses got the initial layout activation and silence for the rest of the workout.
- Generalises to any `(connect, write)` pair: WCSession's `sendMessage` after `activate()`, a websocket's `send` after `open()`, a metrics-publishing helper that "exists" but no one calls.

The smell from outside: "the helper has tests, the helper compiles, but on real hardware nothing reaches the peer."

## Detection

```bash
# Find every callsite of the helper's hot path:
rg -n "\.updateField\(|\.send\(|\.publish\(" --type=swift
# Compare to where the helper itself is constructed:
rg -n "\bGlassesService\(|\bSomeService\(" --type=swift
```

If the construction set is `{tests, factory}` and the hot-path callsite set is `{tests}` only, you have a dead wire.

## Pattern

Three pieces — wire it once, never regress:

### 1. Instantiate the service from the lifecycle owner, not the transport factory

The view-model / session-manager that already owns the metric stream **must own the helper**. Don't let the factory return only the raw transport — wrap it.

```swift
if let transportFactory {
    let transport = transportFactory()
    self.transport = transport
    let glasses = GlassesService(transport: transport)
    self.glasses = glasses                          // <— retained
    attachGlasses(transport: transport, service: glasses)
    Task.detached { try? await transport.connect() }
}
```

### 2. Activate downstream config at the `.connected` state edge, not at `start()`

`start()` runs before scan/connect completes. Any `selectLayout` / channel-subscribe / "I'm ready" call issued there will throw `.notConnected`. Wire it inside the connection-state stream:

```swift
for await state in stream {
    if state == .connected {
        try? await service.selectLayout(preset: .default)
    } else if state == .disconnected || state == .reconnecting || state == .failed {
        await service.resetThrottle()    // see (3)
    }
}
```

### 3. Per-key last-write-wins throttle + connected-state guard inside the write path

The hot path is fire-and-forget from the metric stream; the **helper** itself enforces the guards so the caller never races BLE state:

```swift
public struct PerKeyThrottle: Sendable {
    public let minimumInterval: TimeInterval
    private var lastSent: [Key: Date] = [:]
    public mutating func shouldSend(key: Key, now: Date) -> Bool {
        if let last = lastSent[key], now.timeIntervalSince(last) < minimumInterval { return false }
        lastSent[key] = now; return true
    }
    public mutating func reset() { lastSent.removeAll(keepingCapacity: true) }
}
```

And inside the service actor:

```swift
func apply(metric: WorkoutMetric) async {
    guard let activeLayout, let activeLayoutID else { return }
    guard let slot = activeLayout.slots.firstIndex(where: { $0 == metric.kind }) else { return }
    guard await transport.connectionState == .connected else { return }
    guard throttle.shouldSend(fieldIndex: UInt8(slot), now: now()) else { return }
    try? await transport.updateField(...)
}
```

Critical properties:

- **Strict `<` at the boundary** so the gate re-arms exactly at `last + interval`, not `last + interval + ε`.
- **Denied attempts must not advance the gate**, or a flapping emitter pushes the next-allowed-send arbitrarily far into the future.
- **Reset on every disconnect/reconnect** so the first post-reconnect tick lands immediately per key.
- **Per-key independence** — a burst across N distinct keys at the same instant must all pass on the first tick.

## Tests that pin it

Even if the wire itself is hard to unit-test (view-model lives in an app target with no XCTest target), the **throttle** and the **fan-out mapping** are pure value-type logic and belong in your Linux-buildable Core test target:

- `shouldSend` allows first call, denies second within window, allows boundary, denies-without-advancing, per-key independent, `reset()` releases all keys.
- Mapping resolves `MetricKind → fieldIndex` against the active layout's slot ordering.
- Disconnected transport rejects writes (`.notConnected`) as the wire-level safety net.

## Anti-patterns

- ❌ Construct the service inside the transport factory and return it as `any GlassesFrameTransport` — loses the typed surface the view-model needs.
- ❌ Wire metric fan-out by `await`-ing inside the view-model's `apply(metric:)` — back-pressures the UI thread on BLE. Use `Task { await ... }` (fire-and-forget) and put the guards inside the service.
- ❌ Put the throttle on the caller's side. Same caller flow lives in multiple places (picker, Mirror, tests); the helper has to enforce its own rate.
- ❌ Throw from the hot path on `.notConnected`. The metric stream is not the right place to surface BLE errors — drop silently and let the connection-state subscriber handle the UX side.

## Worked example

PR(s) in this repo:

- Commit `7dd784e` — `fix(glasses): wire WorkoutViewModel metrics → GlassesService.update`
- New file: `ARRunnerCore/Sources/ARRunnerCore/Glasses/HUDFieldThrottle.swift`
- New tests: `HUDFieldThrottleTests`, `WorkoutMetricFanoutTests`
- Audit reference: `.squad/audits/2026-05-16-weiss-ar-ble.md` P1.2.
