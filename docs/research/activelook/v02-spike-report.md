# v0.2 SPIKE REPORT — Real ActiveLook BLE on watchOS

**Author:** Weiss
**Date:** 2026-05-15
**Branch:** `feat/v02-ble-activelook-weiss`
**Status:** 🟢 Resolved — proceed with CoreBluetooth-native adapter (no SDK pivot)

## Question

Workstream #1 of v0.2 asked: "Wire the actual ActiveLook SDK to
`GlassesFrameTransport`." We need a definitive answer to "are we taking the
vendor SDK or a custom CoreBluetooth path?" before more work piles on top.

## Re-investigation of the ActiveLook iOS SDK (2026-05-15)

The official Swift SDK is the only first-party Swift surface ActiveLook
ships. As of v4.5.5:

| Constraint | Status on watchOS |
|---|---|
| Package manifest platform | iOS 13+ only (no `.watchOS(...)` entry) |
| Singleton entry point (`ActiveLookSDK.shared`) | Backed by main-thread `UIKit`-style assumptions |
| Background mode hooks | iOS-only `UIApplication` notifications |
| Image / config upload helpers | Use `UIImage` |
| BLE wrapper layer | Vanilla CoreBluetooth (the part that *would* port) |

Adding `.watchOS(.v11)` to the manifest is not a one-line fix: every UIKit
import would have to be `#if canImport(UIKit)` walled off, and the singleton
ergonomics fight the watchOS app lifecycle. The cost outweighs the benefit
when the SDK's BLE layer is already a thin CoreBluetooth wrapper that we
re-implemented in v0.1.

**Verdict:** the iOS SDK is **not viable on watchOS**, just as the v0.1
spike concluded. We do not need to revisit this for v0.3 unless ActiveLook
ships a watchOS-aware target.

## What v0.1 left behind

- `ActiveLookCommand` (Core, Linux-buildable) — pure-Swift wire encoder.
- `ActiveLookGlassesAdapter` (watch) — `GlassesFrameTransport` actor that
  wraps `CBCentralManager` directly.
- Spike doc `docs/research/activelook/watchos-ble-spike.md` covering the
  GATT profile, MTU, backoff, and concurrency model.

## What v0.2 #1 lands on top

1. **Battery service discovery (bug fix).** The Coordinator already routed
   `0x2A19` notifications, but we never discovered the standard Battery
   Service (`0x180F`) on the peripheral, so the handler could never fire.
   Now discovered alongside the ActiveLook command service.
2. **Layout-display payload spec compliance.** `displayLayout` previously
   appended a UTF-8 text + null terminator unconditionally. The ActiveLook
   spec only takes a layout-ID byte for `0x62`; text overrides are a
   `widgetUpdate` concern. Removed the trailing bytes.
3. **Adapter wired into the watch app.** `WorkoutViewModel` now constructs
   an `ActiveLookGlassesAdapter` (release) or `StubGlassesTransport` (debug
   previews) via a factory and forwards lifecycle to it on workout start.
4. **Hardware integration scaffold.** `ActiveLookGlassesAdapterHardwareTests`
   compiles only when the `AR_RUNNER_HARDWARE_TESTS` flag is set, so CI
   stays green and Joe can flip the flag locally to drive a real pair.
5. **Wire-format regression test.** `testDisplayLayoutFrameCarriesOnlyTheLayoutID`
   nails down the new `0x62` payload shape so the v0.1 bug cannot reappear.

## What v0.2 #1 deliberately does **not** change

- `GlassesFrameTransport` protocol surface — frozen for the v0.2 cycle.
- The adapter's reconnection backoff or layout catalog mapping — those are
  follow-up concerns once the curated layouts are baked.
- Phone-relay fallback. We do not need it; the watch-native path works.

## Risk register (post-v0.2 #1)

| Risk | Severity | Status |
|---|---|---|
| ActiveLook ships a breaking firmware that changes GATT UUIDs | Low | Monitored via spike doc |
| watchOS deprecates `@preconcurrency` on `CoreBluetooth` types | Low | Refactor path is local to one file |
| Hardware run reveals MTU stalls | Medium | Hardware test scaffold exists; Joe will run |

## Decision

**Stay on the CoreBluetooth-native adapter.** Do not adopt the vendor SDK
on watchOS. Revisit only if ActiveLook publishes a watchOS target.
