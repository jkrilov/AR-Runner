# ActiveLook iOS SDK

## Purpose
Official Swift library providing high-level API for scanning, connecting, and commanding ActiveLook AR glasses over BLE; abstracts GATT protocol details.

## Platform & License
- **Language/Platform:** Swift (iOS 13+); supports both CocoaPods and Swift Package Manager
- **License:** Apache 2.0
- **Last Activity:** Main branch; stable; v4.5.5 latest tagged release

## Activity Signal
**Active** — Maintained SDK. Swift Package support added to enable dependency management without CocoaPods. Regular updates tie to firmware/glasses releases.

## Key Folders/Files
- `Sources/` — Swift source:
  - `ActiveLookSDK.swift` — Singleton API entry point
  - `Glasses.swift` — Connected device interface (commands, notifications)
  - `DiscoveredGlasses.swift` — BLE discovery result
  - BLE/GATT infrastructure (characteristics, UUID definitions)
- `LICENSE` — Apache 2.0
- `README.md` — Installation (CocoaPods, SPM), example usage

## What We'd Lift/Reference/Learn
- **API design** — Singleton pattern (`ActiveLookSDK.shared`); callback-driven (closures for discovery, connection, commands)
- **Scanning & discovery** — `startScanning(onGlassesDiscovered:onScanError:)` with closure-based discovery notifications
- **Connection lifecycle** — `connect(onGlassesConnected:onGlassesDisconnected:onConnectionError:)` captures all state transitions
- **Command interface** — Methods like `power(on:)`, `luma(level:)`, `circ(x:y:radius:)`, `battery(callback:)` map 1:1 to protocol; async callbacks for responses
- **Notifications** — Battery updates (30sec interval), flow control, gesture events available as subscriptions
- **Error handling** — Closures for all failure modes (scan, connect, command timeouts)

## Constraints & Architecture Notes
- **Ownership model**: SDK assumes single app owns the connection; no multi-client/remote device pairing
- **Thread safety**: Callbacks on main thread; caller must manage dispatch if needed
- **Device info** — Post-connection: `getDeviceInformation()` yields firmware version, model, serial (useful for version gating features)
- **Info.plist requirements**:
  - `NSBluetoothAlwaysUsageDescription` (iOS 13+)
  - `App Transport Security Settings` with `Allow Arbitrary Loads` = YES
- **Native BLE dependency** — Uses iOS Core Bluetooth; no custom BLE stack
- **Heatshrink compression** acknowledgment in code: SDK may pre-process images for compression

## Integration Path Recommendations
- **For watchOS**: SDK is iOS-only; Watch would need:
  - *(Option A)* iPhone acts as BLE proxy (Watch → iPhone → Glasses via WatchConnectivity)
  - *(Option B)* Swift Package extracted and recompiled for watchOS if source available
  - *(Option C)* Native watchOS BLE wrapper mirroring SDK callbacks (most portable, most work)

## Open Questions for AR-Runner
- Is watchOS BLE allowed on-device, or must iPhone mediate?
- How does battery life scale with high-frequency metric updates (HKQuantitySample polling → BLE write cycles)?
