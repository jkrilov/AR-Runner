# Skill: ActiveLook Bluetooth Pairing (pre-run UX pattern)

> **Owner:** Weiss
> **Born:** 2026-05-18 (PR #42 — pre-run glasses connect screen)
> **Applies to:** any BLE peripheral the user needs to opt-in pair to
> before starting an activity, not just ActiveLook / Engo 2.

## Why this skill exists

The first device-test feedback on AR-Runner v0.2.0 was "I can't find a
way to connect my glasses before starting a run." The shape of the fix
turns out to be a reusable pattern any time an app integrates an
optional BLE peripheral whose absence shouldn't block the primary
workflow.

## The pattern

### 1. Separate the pre-run and in-run surfaces

The status chip / pairing affordance lives **only** on the idle (and
terminal) UI states. During the activity itself, the existing
HUD-offline indicator takes over. Two different visual languages for
two different user intents:

| State              | Pre-run                          | In-run                                       |
| ------------------ | -------------------------------- | -------------------------------------------- |
| Disconnected       | Tappable chip, primary action    | Subtle banner, non-interactive               |
| Scanning/Connecting| ProgressView in the sheet        | (Hidden — no user agency mid-run)            |
| Connected (name)   | Chip shows device name           | (Implicit via no banner)                     |
| Failed             | Retry button + error text        | Banner only; rely on adapter auto-reconnect  |

### 2. Lazy-build, never-rebuild

A `prepareGlassesIfNeeded()` view-model method that builds the
transport + attaches streams **without scanning** is a much better
abstraction than baking the transport build into `start()`. The "Start"
action then **reuses** whatever transport instance is already in hand
rather than calling the factory again — otherwise a user who
pre-paired sees the link torn down and re-scanned the instant they tap
Start.

```swift
if let existing = self.transport, let existingService = self.glasses {
    transport = existing
    glasses = existingService
} else {
    transport = transportFactory()
    /* ...build + attach... */
}
```

### 3. Opportunistic auto-reconnect, but only after a known-good pair

Don't scan on cold start on a fresh install — it just surfaces a
confusing "No glasses found" error and burns battery. Gate auto-
reconnect on a UserDefaults `hasPaired` flag that's only set after the
first successful `transport.connect()`. A `clear()` escape hatch keeps
the "Forget Glasses" affordance trivially addable later.

### 4. Typed errors → user-friendly strings at the view-model boundary

Map `GlassesTransportError` cases to short, action-oriented messages
once, in the view model, not in the view. The view just renders
`viewModel.glassesPairingError`. Bluetooth-unavailable, scan-timeout,
and write-failure all deserve distinct copy.

### 5. Protocol extension default for new optional capabilities

When adding a new capability to a transport protocol (here:
`var connectedDeviceName: String? { get async }`), put a default-nil
impl in a protocol extension. Linux test stubs and existing callsites
don't need source changes; only the platform-specific adapter
overrides:

```swift
public protocol GlassesFrameTransport: Sendable {
    /* existing ... */
    var connectedDeviceName: String? { get async }
}
extension GlassesFrameTransport {
    public var connectedDeviceName: String? { get async { nil } }
}
```

## Anti-patterns to avoid

- **Don't show the pairing chip during an active workout.** It competes
  with the live metrics for screen real estate. The HUD-offline banner
  already covers the in-run case.
- **Don't block Start on pairing succeeding.** D4 invariant —
  AR-Runner is a HealthKit recorder first and an AR HUD second.
- **Don't auto-scan on first cold launch.** Wait for the user to opt
  in by tapping the chip the first time. Scan automatically only after
  they've successfully paired at least once.
- **Don't rebuild the transport on Start when the user just pre-paired.**
  See "Lazy-build, never-rebuild" above.
- **Don't expose CoreBluetooth types to the view layer.** The view
  knows only `GlassesConnectionState` + a `String?` device name; the
  CB peripheral handle stays inside the actor.

## When NOT to use this pattern

- **Mandatory devices** (where the activity literally can't proceed
  without the peripheral). Use a hard gate at the start of the flow
  instead.
- **Multi-device pickers**. Once you need a list of discovered devices
  with per-device RSSI and connect-by-identifier, the chip + sheet
  pattern doesn't scale — graduate to a full device-list view with
  per-row connect buttons.

## Test discipline

`StubGlassesTransport`-style stubs in Core should model the new
capability (here: a configurable `simulatedDeviceName` defaulting to
something sensible like `"Simulated Glasses"`) so SwiftUI previews and
unit tests don't have to special-case nil names. Add tests for the
three obvious states: nil-when-disconnected, exposed-when-connected,
clears-after-disconnect.

## CoreBluetooth scan filter — the trap that broke PR #42

**Added 2026-05-18 after the PR #42 → PR #45 fix campaign.**

`CBCentralManager.scanForPeripherals(withServices:)` matches the
service-UUID list against the peripheral's **advertising packet**, not
its GATT table. ActiveLook / Engo 2 (and many opaque vendor peripherals)
do NOT advertise their 128-bit private service UUID — it's only exposed
on the GATT table after connection. Filtering by that UUID at scan time
means `didDiscover` is never invoked and the connect screen hangs until
the scan timeout fires.

### Do this instead

```swift
// 1. Scan with nil services.
central.scanForPeripherals(
    withServices: nil,
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
)

// 2. Filter in didDiscover by manufacturer data company-ID prefix.
//    For ActiveLook / Microoled: 0xFA 0xDA (little-endian SIG ID 0xDAFA).
guard
    let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
    manufacturerData.count >= 2,
    manufacturerData[manufacturerData.startIndex]     == 0xFA,
    manufacturerData[manufacturerData.startIndex + 1] == 0xDA
else { return }
```

Mirrors ActiveLook's own iOS SDK
(`Sources/Classes/Public/ActiveLookSDK.swift:192`), which carries a
literal `// Scanning with services list not working` comment next to
their scan call.

**Extract the byte-prefix check as a pure helper** in Core (e.g.
`GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData:)`)
so it's exercised on the Linux CI runner without needing CoreBluetooth.
Test the negative cases too: byte-swapped prefix, too-short payload,
nil/empty data, and `Data` slices with a non-zero `startIndex` (the
naive `data[0]` indexing silently misbehaves on slices — index from
`data.startIndex` always).

### Background-scan caveat

Apple still requires a service-UUID filter for **background** scans.
Our pairing flow is foreground only and the runtime reconnect path uses
`retrievePeripherals(withIdentifiers:)` (no scan), so we don't hit this
limit. If a future flow ever needs unattended background pair of a new
device from the watch, expect to design around this separately.

## Fast reconnect — never scan twice for the same glasses

After the first successful connect, persist `peripheral.identifier`
(`UUID`) to UserDefaults. On every subsequent app launch / connect-
screen open, BEFORE starting a scan:

```swift
let known = central.retrievePeripherals(withIdentifiers: [savedUUID])
if let peripheral = known.first {
    central.connect(peripheral, options: nil) // No scan needed.
}
```

This mirrors ActiveLook SDK's `connect(_:onDisconnect:onConnectionError:)`
(`ActiveLookSDK.swift:368` and helpers at `240–298`). It's faster than
scanning, more battery-friendly, and works when the peripheral isn't
advertising loudly enough for a scan to pick it up in time.

**Always pair this with a fallback safety timeout** (5–10 s). If
`retrievePeripherals` returns `[]` because the system has evicted the
peripheral from its cache (post-reboot, long idle), OR if `connect`
never produces a `didConnect`/`didFailToConnect` callback (glasses
powered off / out of range), tear it down and fall back to the
manufacturer-data scan path. Don't surface the eviction as an error —
it's normal.

## Anti-pattern lesson — validate "platform limitation" claims first

When you find yourself reaching for "the platform doesn't support this"
as a diagnosis, **check whether a shipping app does support it.** The
official ActiveLook watch app pairs glasses directly from watchOS;
that's prima facie evidence the platform handles the use case. A 30-
second `grep scanForPeripherals` on the vendor's iOS SDK source can
flip a bad architectural pivot in two minutes. (See the v1 → v2
retraction trail in `.squad/files/glasses-pairing-diagnosis.md` for the
worked example. The watchOS-CB-third-party-restriction "skill" the v1
diagnosis was going to spawn does not exist — it was a fabrication of
the prior misreading.)

