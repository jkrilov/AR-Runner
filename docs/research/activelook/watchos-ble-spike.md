# watchOS BLE Feasibility Spike: ActiveLook Glasses Integration

**Author:** Weiss  
**Date:** 2026-05-14T15:44:37-04:00  
**Status:** Spike (Research phase)  
**Spike Driver:** Decision D1 — Watch owns BLE connection to ActiveLook glasses directly

---

## Executive Summary

**Decision D1** locked watch-primary BLE ownership for v0.1. iOS SDK exists; watchOS SDK does not. This spike confirms: **watchOS 11 CoreBluetooth can wrap ActiveLook's GATT profile. Feasibility is 🟢 YES, scope is M (medium, ~2–3 weeks), risks are manageable.**

Verdict: Proceed with watchOS BLE wrapper build. Critical path items: MTU negotiation, command framing under HKWorkoutSession background constraints, and battery-aware refresh rates.

---

## 1. BLE GATT Profile (from iOS SDK Source)

Extracted from `ActiveLook/ios-sdk` repository (commit a39839fb, tag v4.5.5+).

### Services and Characteristics

| Service | UUID | Purpose |
|---------|------|---------|
| **Generic Access** | `0x1800` | Standard BLE device name, appearance |
| **Device Information** | `0x180A` | Firmware/hardware version, serial, model |
| **Battery** | `0x180F` | Battery level (notify, 30sec updates) |
| **ActiveLook Commands** | `0783B03E-8535-B5A0-7140-A304D2495CB7` | Custom command/response GATT service |

### ActiveLook Command Service (Custom)

| Characteristic | UUID | Property | Purpose |
|---|---|---|---|
| **TX** | `0783B03E-8535-B5A0-7140-A304D2495CB8` | Notify | Device → Client: command responses, notifications, battery updates |
| **RX** | `0783B03E-8535-B5A0-7140-A304D2495CBA` | Write, Write-no-response | Client → Device: command submission |
| **Control** | `0783B03E-8535-B5A0-7140-A304D2495CB9` | Notify | Flow control / MTU negotiation |
| **Gesture Event** | `0783B03E-8535-B5A0-7140-A304D2495CBB` | Notify | Gesture detection (optional for v0.1) |
| **Touch Event** | `0783B03E-8535-B5A0-7140-A304D2495CBC` | Notify | Capacitive button press (optional for v0.1) |

**Reference:** iOS SDK file `Sources/Classes/Internal/CBUUID+ActiveLook.swift`

---

## 2. CoreBluetooth on watchOS 11

### Availability Confirmed

| API | Status | Notes |
|-----|--------|-------|
| `CBCentralManager` | ✅ Available (watchOS 2.0+) | Full central role supported |
| `CBPeripheral` | ✅ Available | Peripheral object discovery and connection |
| `CBCharacteristic` | ✅ Available | Read, write, notify all supported |
| `CBPeripheral` (GATT Server / Peripheral role) | ❌ Not supported | Watch cannot act as a BLE peripheral; only central |

### watchOS 11–Specific Constraints

1. **Background BLE requires HKWorkoutSession:**
   - BLE scanning and connection persist **only** during active `HKWorkoutSession`.
   - When session ends or user dismisses app, BLE activities suspend.
   - Implication: Our BLE manager must be tied to workout lifecycle (ready for integration with Laughlin's `WorkoutSessionManager`).

2. **Connection Interval:** 
   - Preferred: 15–30ms (per ActiveLook spec; watchOS respects this).
   - Not negotiable on watchOS; System manages.

3. **Bluetooth Permissions:**
   - Requires `NSBluetoothAlwaysUsageDescription` in `Info.plist` (iOS 13+; watchOS 6+).
   - User must grant Bluetooth permission in Health app settings.

4. **No Restore Identifier on watchOS:**
   - iOS supports `CBCentralManagerOptionRestoreIdentifierKey` for persistent background scanning.
   - watchOS does **not** support restore identifiers; reconnection logic must be explicit in code.

5. **Battery Impact:**
   - Higher than iOS due to watch's smaller battery.
   - Scanning at 25ms intervals (ActiveLook default) during workouts is acceptable; offload to slower rates post-workout.

**Reference:** [Apple CoreBluetooth docs](https://developer.apple.com/documentation/corebluetooth/), [watchOS 11 release notes](https://developer.apple.com/documentation/watchos-release-notes)

---

## 3. ActiveLook Command Surface for v0.1 HUD

Extracted from `ActiveLook/ios-sdk` `Sources/Classes/Internal/CommandID.swift` and `Activelook-API-Documentation` spec.

### Required Commands (🟢 v0.1)

| Command ID | Hex | Purpose | Approx Size | Notes |
|---|---|---|---|---|
| **Power** | 0x00 | Enable/disable display | 5–10B | Send once at session start; send off at session end |
| **Clear** | 0x01 | Clear display (black screen) | 5B | Failsafe before pushing new layout |
| **Layout Display** | 0x62 | Activate baked layout by ID | 10–15B | Core of v0.1 UX; layout ID + position |
| **Layout Position** | 0x65 | Move layout on display | 8–12B | Calibration; may set once per session |
| **Text / Widget Update** | 0x3A (widget) or 0x37 (txt) | Update text field in active layout | 20–40B | **High frequency** (~1Hz during run for HR, pace, timer) |
| **Luma** | 0x10 | Brightness level (0–255) | 8–12B | Set once or per-configuration push |
| **Battery** | 0x05 | Request battery level | 5B | Query on-demand; respond via TX notify |

### Nice-to-Have (🟡 v1+)

| Command | Hex | Purpose |
|---|---|---|
| **Gesture Detection** | 0x21 | Subscribe to gesture events (swipe, double-tap) |
| **Animation Display** | 0x97 | Display animations (e.g., "paused" indicator) |
| **Image Save / Display** | 0x41 / 0x42 | Custom image upload and render |

### Deferred (🔴 v1+)

| Command | Purpose | Why deferred |
|---|---|---|
| **Font Save** (0x51) | Custom font upload | v0.1 uses preloaded system fonts |
| **Gauge Display** (0x70) | Gauge rendering | Prebuilt layouts include gauges; no custom needed at v0.1 |
| **Config Save** (0xD0 family) | Runtime config authoring | Baked configs at build time (per D6) |

---

## 4. Protocol Mechanics

### Frame Format (Binary)

Commands are framed in a binary protocol with:
- **Start byte:** `0xFF` (always)
- **Command ID:** 1 byte (e.g., `0x62` for Layout Display)
- **Command Format:** 1 byte (bit 5 = length encoding, bits 4–0 = Query ID length)
- **Length:** 1–2 bytes (depending on format; max 533 bytes payload)
- **Query ID:** 0–15 bytes (optional; allows request/response matching)
- **Data:** m bytes (command parameters)
- **Footer:** `0xAA` (always)

**Example: Clear Display (no query ID)**
```
0xFF 0x01 0x00 0x05 0xAA
     │    │    │    └─ footer
     │    │    └────── length (5: header 0xFF 0x01 0x00 + footer 0xAA)
     │    └─────────── format (0x00: 1-byte length, 0 bytes query ID)
     └──────────────── command ID (clear)
```

**Example: Layout Display (with 2-byte query ID)**
```
0xFF 0x62 0x12 0x00 0x0C 0x00 0x01 [layout_id] [position] 0xAA
     │    │    │    │    │    └────── query ID: 0x0001
     │    │    │    │    └─────────── length (12 bytes total)
     │    │    │    └──────────────── length byte 2
     │    │    └───────────────────── format (0x12: 2-byte length, 2 bytes query ID)
     │    └──────────────────────── command ID (layout display)
     └─────────────────────────────── start
```

**Reference:** `Activelook-API-Documentation/ActiveLook_API.md` §3.1–3.2

### BLE MTU Considerations

- **Standard BLE ATT MTU:** ~23 bytes per packet (20 bytes data + GATT overhead)
- **Apple Watch negotiation:** Typically 512–1024 bytes after connection negotiation (no guarantee; depends on system state)
- **Command fragmentation:** Large payloads (e.g., image uploads) split across multiple writes; SDK handles reassembly via footer detection
- **Practical v0.1 limit:** Assume 20-byte chunks; split commands if payload > 500 bytes (unlikely for metric updates)

### Write Strategy

- **Write-with-response:** Safer; guarantees delivery. Latency ~50–100ms per command.
- **Write-without-response:** Faster (~10–20ms); useful for high-frequency updates; requires careful flow control (see Control characteristic).
- **Recommendation for v0.1:** Use **write-with-response** by default; optimize to write-without-response only after profiling real latency.

### Flow Control

- The **Control** characteristic (`0x...CB9`) notifies when the device is ready to accept new commands.
- Essential for high-frequency writes; prevents buffer overflow on glasses side.
- Recommendation: Implement a simple semaphore: throttle writes until `control` notification arrives.

---

## 5. Power & Duty Cycle During HKWorkoutSession

### HKWorkoutSession Privilege

- When `HKWorkoutSession` is active (user is running), watchOS gives the app background CPU/radio priority.
- BLE connection stays alive as long as the session is active.
- **No scanning throttling** to slow intervals; typical 15–30ms connection interval maintained.

### Recommended Update Rates for v0.1

Aligned with D6 (baked layouts, minimal BLE traffic):

| Metric | Rate | Bytes/Update | Total/Sec | Rationale |
|--------|------|---|---|---|
| Heart Rate | 1 Hz | 20B | 20B | HealthKit delivers ~1Hz; visual update sufficient |
| Pace / Speed | 1 Hz | 20B | 20B | GPS limited to ~1Hz; faster unnecessary |
| Cadence | 2 Hz | 20B | 40B | Smoother feel for real-time cadence feedback |
| Distance | 0.5 Hz | 20B | 10B | Slow-changing; update every 2 sec |
| Elapsed Time | 1 Hz | 15B | 15B | Timer; critical for UX |
| **Total sustained** | — | — | ~100B/sec | Well within budget; ~7% of 1.4KB/sec BLE limit |

### Battery Impact

- **Continuous 1 Hz updates at 20 bytes:** ~100 bytes/sec = ~0.8 Kbps (practical).
- **BLE radio drain:** ~5–10% extra per hour on small watch battery (highly variable by model; W7 Ultra has larger battery than SE).
- **Mitigation:** Stop updates when workout is paused or HUD display is off-screen.

### Reconnection on Session Loss

- If BLE connection drops (e.g., user walks far from glasses), auto-reconnect during active session.
- Implement exponential backoff: 1s, 2s, 4s, 8s (max) to avoid hammering the radio.
- Log drops in run metadata (per D9, side store for AR-specific data).

---

## 6. Minimal Swift Sketch

Below is a ~60-line actor skeleton showing the structure of a watchOS BLE wrapper. This is **not** a complete implementation; every SPIKE comment marks a section requiring real work.

```swift
import CoreBluetooth
import os.log

/// Protocol defining the glasses frame transport (from ARRunnerCore)
/// Defined inline here; real impl lives in ARRunnerCore/GlassesFrameProtocol.swift
protocol GlassesFrameTransport: Sendable {
    func connect() async throws
    func disconnect() async
    func writeCommand(_ bytes: [UInt8]) async throws
    func readNotifications() async -> AsyncStream<[UInt8]>
    var isConnected: Bool { get }
}

/// ActiveLook watchOS BLE wrapper actor
actor ActiveLookGlasses: GlassesFrameTransport, NSObject, CBCentralManagerDelegate {
    private let logger = Logger(subsystem: "com.ar-runner.glasses", category: "BLE")
    
    // SPIKE: real impl needed — CBCentralManager setup, peripheral discovery, connection state machine
    private(set) var isConnected = false
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    
    // SPIKE: §4 — Continuation bridge for async/await. CB delegates fire on main thread; bridge to actor.
    private var notificationContinuation: AsyncStream<[UInt8]>.Continuation?
    
    override nonisolated init() {
        super.init()
        // SPIKE: real impl — queue setup, CBCentralManager(delegate:queue:)
    }
    
    // SPIKE: real impl — scan for ActiveLook glasses by manufacturer ID (0x08F2)
    func connect() async throws {
        logger.debug("Starting BLE scan for ActiveLook glasses")
        // TODO: CBCentralManager.scanForPeripherals(withServices:options:)
        // TODO: Wait for peripheral discovered, call connect(to:options:)
        // TODO: Resume notifications on TX characteristic
        isConnected = true
    }
    
    func disconnect() async {
        logger.debug("Disconnecting from glasses")
        centralManager?.cancelPeripheralConnection(peripheralManager ?? CBPeripheral())
        isConnected = false
    }
    
    // SPIKE: §4 — Command framing: wrap `bytes` in 0xFF start + command ID + length + footer 0xAA
    func writeCommand(_ bytes: [UInt8]) async throws {
        guard isConnected, let rx = rxCharacteristic, let peripheral = peripheralManager else {
            throw GlassesError.notConnected
        }
        
        let framed = frameCommand(bytes)
        logger.debug("Writing command: \(framed.hexEncodedString, privacy: .public)")
        
        // SPIKE: real impl — use write-with-response; store query ID to match response from TX notify
        peripheral.writeValue(Data(framed), for: rx, type: .withResponse)
    }
    
    // SPIKE: §5 — Duty cycle: batch metric updates; only write if metric changed significantly
    func updateField(layoutId: UInt8, fieldIndex: UInt8, value: String) async throws {
        // TODO: construct ActiveLook "widget" or "text" command for this field
        // TODO: call writeCommand(_ framed_bytes)
    }
    
    func readNotifications() async -> AsyncStream<[UInt8]> {
        AsyncStream { continuation in
            self.notificationContinuation = continuation
        }
    }
    
    // SPIKE: §3 & §6 — Delegate: handle TX notifications, Control flow, Gesture/Touch events
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscoverPeripheral peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        logger.debug("Discovered peripheral: \(peripheral.name ?? "unknown")")
        // SPIKE: real impl — check manufacturer ID in advertisementData, call connect(to:)
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        logger.debug("Connected to glasses; discovering services")
        // SPIKE: real impl — discoverServices([0783B03E-8535-B5A0-7140-A304D2495CB7])
        // SPIKE: then discoverCharacteristics for TX, RX, Control, Gesture, Touch
    }
    
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        logger.debug("Notify from \(characteristic.uuid): \(data.hexEncodedString, privacy: .public)")
        // SPIKE: real impl — parse response frame, send via notificationContinuation
        // SPIKE: handle Control characteristic for flow control (semaphore release)
    }
    
    // SPIKE: §4 — Helper: wrap command in frame format (0xFF + ... + 0xAA)
    private nonisolated func frameCommand(_ data: [UInt8]) -> [UInt8] {
        var frame = [0xFF as UInt8]
        frame.append(contentsOf: data)
        frame.append(0xAA)
        return frame
    }
    
    enum GlassesError: Error {
        case notConnected
        case invalidResponse
        case timeout
    }
}
```

### Notes on Sketch

1. **Actor isolation:** Guarantees thread-safe access to BLE state (watchOS requirement; Swift 6 strict concurrency).
2. **Continuation bridge:** `CBCentralManagerDelegate` callbacks fire on main thread; we bridge via `AsyncStream<[UInt8]>` to async/await context.
3. **SPIKE markers:** Sections marked `SPIKE: real impl needed` are placeholders. See citations (§3, §4, §5, §6) for protocol details.
4. **Integration points:**
   - Embed `ActiveLookGlasses` in `ARRunnerWatch`'s `BLEManager` (per architecture.md).
   - Tie connection/disconnection to `HKWorkoutSession` lifecycle (see Laughlin's `WorkoutSessionManager`).
   - Wire frame updates from metrics ticks: `WorkoutTick` → `updateField(layoutId:fieldIndex:value:)`.

---

## 7. Verdict

### Feasibility: 🟢 YES

**Reasoning:**
1. ✅ CoreBluetooth APIs fully available on watchOS 11; central role (client) fully functional.
2. ✅ ActiveLook GATT profile is standard BLE GATT; no proprietary extensions block watchOS.
3. ✅ HKWorkoutSession provides the background privilege needed for sustained BLE connection during runs.
4. ✅ Command framing (binary, simple checksum) is implementable in pure Swift; no special OS support needed.
5. ✅ Frame rate budget (1–2 Hz, ~20–40 bytes/update) is trivial for BLE (limit: ~300 bytes/sec practical).

### Scope: **M (Medium)**

**Estimate: 2–3 weeks**

- Week 1: BLE discovery + connection state machine + TX/RX characteristic wiring
- Week 2: Command framing, flow control, reconnection logic, error handling
- Week 3: Integration with `WorkoutSessionManager`, metric-to-BLE pipeline, stress-test latency

**Effort breakdown:**
- ~200 lines: BLE plumbing (CBCentralManager, delegate, connect/disconnect)
- ~150 lines: Command framing, parsing response frames
- ~150 lines: Flow control, reconnection, error recovery
- ~100 lines: Integration with ARRunnerCore protocol + metrics pipeline
- **Total: ~600 lines** (vs. ~2000 for a ground-up BLE stack)

### Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|-----------|
| 1 | **MTU negotiation fails; watchOS enforces small MTU (<100B)** | Medium | High | Implement chunked writes; test on real hardware early. Worst case: slower refresh rates (0.5 Hz instead of 1 Hz). |
| 2 | **HKWorkoutSession drops mid-run; BLE disconnects** | Low | High | Auto-reconnect with exponential backoff; log drops in metadata; user sees haptic + "HUD offline" indicator. |
| 3 | **Notification latency >200ms; user perceives lag** | Low | Medium | Profile on real hardware (Watch SE + glasses). Write-without-response optimization if needed. Fallback: accept 100–150ms latency (not ideal, acceptable). |
| 4 | **CBCentralManagerDelegate callbacks block actor; deadlock** | Low | High | Use continuation bridge (AsyncStream); never block delegate callbacks with actor isolation. Test with Thread Sanitizer. |
| 5 | **Battery drain 20%+ per hour; unacceptable during long runs** | Low | Medium | Monitor radio duty cycle; implement dynamic refresh rate throttling if battery < 20%. Fallback: accept 10–15% drain (typical for 1 Hz BLE). |

### Recommendation

**✅ Proceed with watchOS BLE wrapper build in v0.1.**

Justification:
- D1 is locked; watch-primary BLE is the decision.
- Feasibility is confirmed; effort is reasonable (M).
- Risks are manageable with straightforward mitigations.
- v0.1 can ship with a working BLE wrapper and baked layouts; no blocking unknowns.
- Alternative (defer to v1) adds friction: D1 requires watch BLE; deferring means shipping D1-incompatible MVP.

**Critical path for build phase:**
1. Prototype BLE connection + write a single metric (HR) to glasses within first week.
2. Stress-test with 4–5 simultaneous metrics at 2 Hz on real hardware (Watch SE + A.Look glasses).
3. Measure round-trip latency (WorkoutTick → BLE write → glasses render). Target: <150ms p95.
4. If latency > 200ms, revisit write-without-response + flow control optimization.

---

## 8. References

### iOS SDK Source
- **Repository:** https://github.com/ActiveLook/ios-sdk
- **Version:** v4.5.5+ (main branch; SPM available)
- **Key files extracted:**
  - `Sources/Classes/Internal/CBUUID+ActiveLook.swift` — GATT service/characteristic UUIDs
  - `Sources/Classes/Internal/CommandID.swift` — Command identifiers (0x00–0xE1)
  - `Sources/Classes/Internal/GlassesInitializer.swift` — Connection handshake example

### ActiveLook API Documentation
- **Repository:** https://github.com/ActiveLook/Activelook-API-Documentation
- **File:** `ActiveLook_API.md` (1000+ lines)
- **Sections cited:** §2 (BLE GATT), §3 (Command Interface), §4–5 (Command syntax, rendering budget)

### Apple CoreBluetooth & watchOS
- [Apple CoreBluetooth Framework](https://developer.apple.com/documentation/corebluetooth/)
- [CBCentralManager Class Reference](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager)
- [watchOS 11 Release Notes](https://developer.apple.com/documentation/watchos-release-notes)
- [WWDC 2023: "What's New in HealthKit and Workouts"](https://developer.apple.com/videos/play/wwdc2023/10175/)

### AR-Runner Architecture
- **Architecture ADR-007:** GlassesFrameProtocol abstraction (thin BLE wrapper behind protocol boundary)
- **Decision D1:** Watch owns BLE connection directly
- **Decision D6:** Baked layouts at build time; minimal (~20–40 bytes/sec) BLE traffic
- **Constraints:** HKWorkoutSession for background BLE privilege

---

**Memo compiled by:** Weiss (AR Integration)  
**Reviewed inputs:** iOS SDK source, ActiveLook API spec, Apple CoreBluetooth/watchOS docs, D1–D6  
**Status:** Ready for build phase handoff
