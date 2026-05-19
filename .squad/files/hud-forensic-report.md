I have all the evidence. I cannot write files with my available tools — I'll produce the complete report content below for the main agent to write to `.squad/files/hud-forensic-report.md`.

---

## FULL REPORT CONTENT (write to `.squad/files/hud-forensic-report.md`)

```markdown
# ActiveLook HUD: Forensic Comparison
_Generated: 2026-05-18 by forensic research subagent_
_Sources: ActiveLook/ios-sdk @ a39839f, ActiveLook/demo-app @ da0ddda, AR-Runner HEAD_

---

## TL;DR

**Most likely root cause (HIGH confidence): Every command frame we send is missing the 1-byte queryID that the Engo 2 firmware's parser expects, causing it to misinterpret `power(on:true)`'s payload byte as a queryID and leave the data region empty — likely sending a power-off instead of power-on. Secondary root cause (MEDIUM confidence): we never read the flow-control characteristic's actual ON/OFF value, so if the glasses signal "off" during their post-connect init, all our writes land in a black hole at the application layer while CoreBluetooth still ACKs them at the GATT layer.**

Three additional structural bugs exist that are confirmed (wrong rotation, missing cfgSet for layout path, malformed layoutDisplay command) but these affect display quality or the abandoned layout path — they are not the cause of the current "all-black" result.

---

## Official SDK Trace
_Source: `ActiveLook/ios-sdk`, commit a39839f_

### Step 1 — SDK initialisation
`ActiveLookSDK.shared(onUpdate* callbacks)` → stores update parameters.
_File: `Sources/Classes/Public/ActiveLookSDK.swift`_

### Step 2 — Scan
`activeLook.startScanning(onGlassesDiscovered:onScanError:)`  
Scans for ALL peripherals (no service-UUID filter). Manufacturer-data check done inside the SDK.  
_File: `ActiveLookSDK.swift`_

### Step 3 — Connect
`discoveredGlasses.connect(onGlassesConnected:onGlassesDisconnected:onConnectionError:)`  
Creates a `Glasses` object wrapping the peripheral.  
Then calls `GlassesInitializer.initialize(glasses:onSuccess:onError:)`.  
_File: `Sources/Classes/Public/DiscoveredGlasses.swift`, `Sources/Classes/Internal/GlassesInitializer.swift`_

### Step 4 — GlassesInitializer: service discovery
`peripheral.discoverServices([DeviceInformationService, BatteryService, ActiveLookCommandsInterfaceService])`  
Three services discovered.  
_File: `GlassesInitializer.swift` lines ~75-120_

### Step 5 — GlassesInitializer: characteristic discovery per service
**DeviceInformationService**: reads all DIS chars (manufacturerName, modelNumber, serialNumber, hardwareVersion, firmwareVersion, softwareVersion).  
**BatteryService**: reads `BatteryLevelCharacteristic`, subscribes to notifications.  
**ActiveLookCommandsInterfaceService** (`0783b03e-…-cb7`): discovers and acts on:
- `0783b03e-…-cb8` (TX) → `setNotifyValue(true, for:)`  
- `0783b03e-…-cba` (RX) → stored, no notify  
- `0783b03e-…-cbc` (UI/gesture) → stored  
- `0783b03e-…-cb9` (FlowControl) → `setNotifyValue(true, for:)`  
- `0783b03e-…-cbb` (SensorInterface) → stored  
_File: `GlassesInitializer.swift` lines ~135-185_

### Step 6 — GlassesInitializer: polling loop
`initPollTimer` fires at 0.2 s intervals, calling `isReady()`.  
`isReady()` checks ALL of: rxChar ≠ nil, txChar ≠ nil, batteryChar ≠ nil, flowCtrlChar ≠ nil, sensorInterfaceChar ≠ nil, ALL DIS fields non-nil, `txCharacteristic.isNotifying == true`, `flowControlCharacteristic.isNotifying == true`, `batteryLevelCharacteristic.isNotifying == true`.  
**Only when ALL are true does the poll declare the glasses ready.**  
_File: `GlassesInitializer.swift` lines ~52-80_

### Step 7 — onGlassesConnected callback fires
`initSuccessClosure()` → SDK calls back the app with a `Glasses` instance.  
The demo app (`GlassesTableViewController`) checks `glasses.isFirmwareAtLeast(version: "4.0")` and pushes the command view if met.  
_File: `GlassesTableViewController.swift` lines ~64-82_

### Step 8 — First display command (layout path, demo app)
Every layout command in the demo is preceded by `glasses.cfgSet(name: "ALooK")`:  
```swift
glasses.cfgSet(name: "ALooK")          // cmd 0xD2 — selects configuration
glasses.layoutDisplay(id: 10, text: "15:36")  // cmd 0x62 — ID + null-terminated text
```
_File: `LayoutCommandsViewController.swift` lines ~51-56_

### Step 9 — First display command (raw-txt path, font demo)
```swift
glasses.cfgSet(name: "DemoApp")        // cmd 0xD2 — selects configuration (needed for custom font)
glasses.fontSelect(id: 4)             // cmd 0x52 — select font (redundant when using inline font)
glasses.txt(x:100, y:100, rotation:.leftTB, font:0x04, color:0x0F, string:"01")  // cmd 0x37
```
_File: `FontCommandsViewController.swift` lines ~100-104_

### Step 10 — Frame wire format (ALL application commands)
`Glasses.sendCommand(id:withData:callback:withoutQueryId:)` with **`withoutQueryId: Bool = false`** (the default):
```
0xFF | cmdID | format=0x01 | length | queryID(1 byte) | data... | 0xAA
```
- `format` nibble = `0x01` (one queryID byte follows the length field)
- `length` = total frame size including all bytes above
- `queryID` is auto-incremented per send (1–254, wraps)  
_File: `Sources/Classes/Public/Glasses.swift` lines ~200-245 (`sendCommand` private method)_

`withoutQueryId: true` is used for ONLY THREE commands: `qspiErase`, `qspiWrite`, `reset` — all hardware/DFU-level ops.  
_File: `Glasses.swift` lines ~540, ~550, ~845_

### Step 11 — Flow-control gating (write-side)
```swift
private func sendBytes() {
    if flowControlState != FlowControlState.on { return }   // gate 1
    if rxCharacteristicState == .busy { return }             // gate 2
    peripheral.writeValue(value, for: rxCharacteristic!, type: .withResponse)
    rxCharacteristicState = .busy
}
```
`flowControlState` is updated from the flow-control characteristic notifications:
- value 1 (`on`) → `flowControlState = .on` → `sendBytes()` triggered
- value 2 (`off`) → `flowControlState = .off` → `sendBytes()` returns immediately
- values 3-6 (error/overflow/unexpectedDataType/missingConfiguration) → forwarded to app callback  
_File: `Glasses.swift` lines ~118-135 (flowControlState setter), ~260-290 (sendBytes), `PeripheralDelegate.didUpdateValueFor` for FlowControl char_

Write type: `.withResponse`. After GATT ACK, `rxCharacteristicState = .available` → `sendBytes()` called again for next queued command.  
_File: `Glasses.swift` `PeripheralDelegate.didWriteValueFor` ~lines 740-760_

---

## Our Adapter Trace
_Source: `ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift` + `ARRunnerCore/Sources/ARRunnerCore/Glasses/`_

### Step 1 — Connect
`transport.connect()` → `beginConnect()` → creates `Coordinator`, `CBCentralManager`, transitions to `.scanning`.  
Awaits `withCheckedThrowingContinuation` for BLE power-on event.  
_File: `ActiveLookGlassesAdapter.swift:158-254`_

### Step 2 — Scan
After `centralManagerDidUpdateState(.poweredOn)`:  
Attempts fast-reconnect from `GlassesPairingPreferences` first.  
If not found, scans for ALL peripherals (no service filter — correctly mirrors SDK behavior).  
Manufacturer-data filter `0xFA 0xDA` applied in `handleDiscovered`.  
_File: `ActiveLookGlassesAdapter.swift:281-363`_

### Step 3 — Connect to peripheral
`central.connect(peripheral, options: nil)`  
On `didConnect` → `handleConnected` → `peripheral.discoverServices([commandService, batteryService])`.  
**DELTA: does NOT discover DeviceInformationService.**  
_File: `ActiveLookGlassesAdapter.swift:365-374`_

### Step 4 — Service/characteristic discovery
**commandService** (`0783b03e-…-cb7`):
- `rxCharacteristic` (`…-cba`) → stored  
- `txCharacteristic` (`…-cb8`) → `setNotifyValue(true, for:)`  
- `controlChar` (`…-cb9`) → `setNotifyValue(true, for:)`  
**DELTA: does NOT discover sensorInterfaceCharacteristic (`…-cbb`) or gestureChar (`…-cbb`)**

**batteryService** (`180F`):
- `batteryLevelChar` (`2A19`) → `setNotifyValue(true, for:)` + `readValue(for:)`  
_File: `ActiveLookGlassesAdapter.swift:376-460`_

### Step 5 — Ready gate
`completeConnectionIfReady()` — gates on ONLY TWO conditions:
1. `rxCharacteristic != nil`
2. `flowControlNotifyConfirmed == true`  
If both met → immediately `transition(to: .connected)`.  
A 2s safety timeout forces `flowControlNotifyConfirmed = true` if the subscription never confirms.  
**DELTA: does NOT wait for DIS, does NOT wait for battery notify, does NOT wait for sensorInterface.**  
_File: `ActiveLookGlassesAdapter.swift:481-512`_

### Step 6 — `connectFrames` pushed immediately on `.connected`
`WorkoutViewModel.attachGlasses` observes the state stream.  
When `.connected` arrives → `pushHUDConnectScreenIfConnected(transport:)` is called.  
This calls `transport.sendCommands(RunningHUDFrame.connectFrames())`:
```
[power(on:true), clear(), txt(x:20,y:40,…,"AR-Runner Ready"), txt(x:20,y:120,…,"Start a run")]
```
_File: `WorkoutViewModel.swift:399-415`, `RunningHUDFrame.swift:141-156`_

### Step 7 — Each frame written serially
`write(_ bytes: [UInt8])` → `peripheral.writeValue(data, for: rxCharacteristic, type: .withResponse)` → awaits `CheckedContinuation` resolved by `didWriteValueFor`.  
_File: `ActiveLookGlassesAdapter.swift:590-624`_

### Step 8 — Flow control handling
`didUpdateValueFor` in Coordinator:
```swift
guard characteristic.uuid == CBUUID(string: ActiveLookGATT.batteryLevelChar),
      let data = characteristic.value, let firstByte = data.first
else { return }   // ← ALL other characteristics silently dropped
```
**CRITICAL DELTA: Flow-control characteristic value (`…-cb9`) notifications are completely ignored. The FlowControl.on/off/error/missingConfiguration state is never read.**  
_File: `ActiveLookGlassesAdapter.swift:756-765`_

### Step 9 — Wire format for all commands
`ActiveLookCommand.encode(id:payload:queryID:)` with `queryID = nil` (the default):
```
0xFF | cmdID | format=0x00 | length | data... | 0xAA
```
- `format` nibble = `0x00` (zero queryID bytes)
- `length` = total frame size
- **No queryID byte anywhere in frame**  
_File: `ARRunnerCore/Sources/ARRunnerCore/Glasses/ActiveLookCommand.swift:122-150`_

**Concrete byte trace for `power(on:true)` — Our frame:**
```
FF 00 00 06 01 AA   (6 bytes)
│  │  │  │  │  └─ footer
│  │  │  │  └──── payload: on=0x01
│  │  │  └─────── length=6
│  │  └────────── format=0x00 (no queryID nibble)
│  └───────────── cmdID=0x00 (power)
└──────────────── header
```
**SDK's frame for `power(on:true)` (queryId=0x01 illustrative):**
```
FF 00 01 07 01 01 AA   (7 bytes)
│  │  │  │  │  │  └─ footer
│  │  │  │  │  └──── payload: on=0x01
│  │  │  │  └─────── queryID=0x01
│  │  │  └────────── length=7
│  │  └───────────── format=0x01 (queryID nibble=1)
│  └────────────────  cmdID=0x00 (power)
└───────────────────  header
```

If the Engo 2 firmware parser requires `format nibble = 1` for all application commands:
- It reads our `0x01` (on=true) as the **queryID byte**, consuming it.
- Data region is then empty (no payload bytes remain before footer).
- Power command with empty data → **firmware defaults to OFF or ignores** → display goes black.

**Concrete byte trace for `txt(x=20, y=40, rot=4, font=3, color=15, "0:00")` — Our frame:**
```
FF 37 00 11 00 14 00 28 04 03 0F 30 3A 30 30 00 AA   (17 bytes)
            ↑                                          
            if firmware expects queryID here, it reads
            0x00 as queryID, then x_hi=0x14=20 → x = 0x1400 = 5120 (off-screen!)
```
Off-screen coordinate → text renders outside 304×256 display area → **blank screen**.

---

## Diff Table

| Step | Official SDK | Our Adapter | Delta | Severity |
|------|-------------|-------------|-------|----------|
| 1. Services discovered | CommandService + BatteryService + **DeviceInformationService** | CommandService + BatteryService only | Missing DIS | LOW |
| 2. Characteristics discovered | RX, TX, FlowCtrl, SensorInterface, UI, BatteryLevel, all DIS chars | RX, TX, FlowCtrl, BatteryLevel only | Missing SensorInterface | LOW |
| 3. DIS values read | All 6 DIS strings read before ready | Never read | Firmware version unknown | LOW |
| 4. Ready gate | `isReady()` polls: rxChar + txNotifying + flowCtrlNotifying + **batteryNotifying** + sensorInterfaceChar + all DIS fields | Only: rxChar + flowCtrlNotifyConfirmed | Too eager; no DIS wait | MEDIUM |
| 5. Connect → first-write latency | ~0.4–1.0 s (DIS reads + poll cycles) | ~50 ms (next event loop tick) | **Writes land before glasses finish init** | HIGH |
| 6. Flow-control ON/OFF value | Read from `…-cb9` notify; gates `sendBytes()` on `FlowControlState.on` | Subscription confirmed, but **value never read**; no write gate | Writes proceed even if glasses signal `off` or `missingConfiguration` | **CRITICAL** |
| 7. Frame format (queryID) | `format=0x01`, 1-byte queryID in ALL app commands | `format=0x00`, no queryID ever | Firmware may misparse payload | **CRITICAL** |
| 8. `layoutDisplay` payload | `[layoutID, text_bytes..., 0x00]` — text inline | `[layoutID]` only — no text | layout path renders nothing (no text to show) | HIGH (PR#49 only) |
| 9. `cfgSet` before layout cmds | `cfgSet(name:"ALooK")` before every layout cmd | Never called | Layout path: wrong/no config active | HIGH (PR#49 only) |
| 10. `cfgSet` before txt cmds | `cfgSet(name:"DemoApp")` before custom-font txt | Never called | Uncertain effect on stock-font txt | UNKNOWN |
| 11. Rotation value | Uses `TextRotation` enum; demo custom layout uses `.bottomRL`=0x00 | Hardcodes `rotation=4` (`topLR` in SDK enum) | Code comment says "bottomRL" but SDK enum says value 4 = **topLR** | MEDIUM (display orientation) |
| 12. Font index | Font passed inline in `txt`; `fontSelect` called separately for non-stock fonts | Font=3 passed inline; no `fontSelect` | Stock font 3 is built-in; should be fine | LOW |
| 13. Write type | `.withResponse` | `.withResponse` | ✅ Identical | — |
| 14. RX characteristic UUID | `0783b03e-…-cba` | `0783b03e-…-cba` | ✅ Identical | — |
| 15. Command IDs (power/clear/txt) | 0x00/0x01/0x37 | 0x00/0x01/0x37 | ✅ Identical | — |
| 16. FlowControl char UUID | `0783b03e-…-cb9` | `0783b03e-…-cb9` | ✅ Identical | — |

---

## Top Suspects

### 1. Missing queryID in every command frame (CRITICAL — explains all three PRs)
**Evidence:**
- The official SDK's `sendCommand` always includes a 1-byte queryID and sets `format nibble = 0x01` for ALL application commands (`power`, `clear`, `txt`, `layoutDisplay`, every graphic primitive).
- `withoutQueryId: true` is passed for ONLY three commands: `qspiErase`, `qspiWrite`, `reset` — all DFU/hardware ops.
- Our `ActiveLookCommand.encode` always produces `format=0x00` with no queryID byte.
- The 6-byte power-on frame `FF 00 00 06 01 AA` vs the 7-byte SDK frame `FF 00 01 07 qid 01 AA` is the specific delta.

**Failure mechanism:**  
If the Engo 2 firmware parser assumes `format nibble = 1` for all application commands (which the SDK invariant strongly implies), it reads our payload byte `0x01` as the queryID byte and sees an empty data region. `power` with empty data → power-off or no-op. Then `clear()` runs (it has no payload, so empty data is correct), wiping the screen to black. Then `txt` commands execute with all coordinate bytes shifted by 1, landing way off-screen (x=0x1400=5120 on a 304px display).

**This precisely maps to the symptom progression:**
- PR #49 (no power cmd, only clear+txt): firmware's clear misparse → "Connection Successful" remains. Alternatively, clear worked but txt drew off-screen → stuck splash.
- PR #53 (added power-on): power misparse → effectively power-OFF → display goes dark → blank screen. clear executed (clearing the now-dark display), txt draws off-screen → nothing.
- PR #55 (added flow-control gate): same frames, same misparse.

**Confidence: HIGH (structural, matches all three PR outcomes)**

---

### 2. Flow-control characteristic value never read (CRITICAL — silent write discard)
**Evidence:**
- SDK: `Glasses.PeripheralDelegate.didUpdateValueFor` reads `ActiveLookFlowControlCharacteristic` value and updates `parent.flowControlState`. ALL writes in `sendBytes()` are gated on `flowControlState == .on`.
- Our `Coordinator.peripheral(_:didUpdateValueFor:)` starts with `guard characteristic.uuid == batteryLevelChar else { return }` — flow-control notifications are silently dropped.
- `FlowControlState` enum includes `missingConfiguration = 6` — the glasses signal this on the flow-control char if a required configuration is absent.
- `FlowControlState.off = 2` — glasses can pause the write stream at any time.

**Failure mechanism:**  
If Engo 2 sends `FlowControl.off` (value 2) during its own post-connect initialisation (before it's fully ready to process display commands), the SDK would pause and wait. Our adapter writes immediately (~50 ms after connection), lands during the `off` window, the glasses accept the GATT write (CoreBluetooth ACKs it at transport layer) but discard it at the application layer. `didWriteValueFor` fires with no error, our continuation resumes, the next frame is written — all succeeding silently. Screen stays blank.  

If Engo 2 sends `FlowControl.missingConfiguration` (value 6) because it requires `cfgSet` even for `txt`, we'd see the same pattern.

**Confidence: MEDIUM-HIGH (mechanism clear; unknown whether Engo 2 actually sends `off` post-connect)**

---

### 3. Wrong rotation value on `txt` commands (CONFIRMED BUG — not blank-screen cause)
**Evidence:**
- `ActiveLookTypes.swift` (SDK): `TextRotation.bottomRL = 0x00`, `TextRotation.topLR = 0x04`.
- Our `RunningHUDFrame.Layout.rotation = 4` with comment `"4 = bottom-RL"` — **the comment is wrong**. Value 4 is `topLR` in the SDK enum.
- The demo app's saved custom layout uses `.bottomRL` (value 0) as the natural reading orientation.

**Failure mechanism:**  
Text rendered at `rotation=4` (topLR — standard horizontal left-to-right) may appear upside-down or sideways in the Engo 2's optical projection path, which might require `bottomRL` (value 0) for naturally-readable text. This would NOT cause blank screen — it would show gibberish/upside-down text. Once the blank-screen bug is fixed, this will need a separate calibration pass.

**Confidence: HIGH that rotation value comment is wrong; MEDIUM that it affects visual output; LOW as blank-screen cause**

---

### 4. `cfgSet` and `layoutDisplay` bugs (CONFIRMED — explains PR #49 fully)
**Evidence (cfgSet):**  
Every single layout display in `LayoutCommandsViewController.swift` is preceded by `glasses.cfgSet(name: "ALooK")` (lines 51, 56, 64, 68, etc.). Our adapter never calls cfgSet. Without this, the glasses either use the wrong configuration or no configuration.

**Evidence (layoutDisplay text):**  
SDK: `layoutDisplay(id: UInt8, text: String)` sends `[layoutID, text_bytes, 0x00]` as payload.  
Our: `displayLayout(id: UInt8)` sends `[layoutID]` only — the text to display is missing from the command entirely.

**Additionally**, our `CuratedLayoutCatalog` placeholder device IDs (0x01–0x03) have no corresponding baked layouts on the device — the comment in `ActiveLookGlassesAdapter.swift:79-91` correctly documents this.

**These are confirmed root causes for the PR #49 regression. The current PR #55 uses the `txt` path and does not trigger these code paths.**

---

## Recommended Next Action

**Do not write another speculative code patch.** The three highest-value actions in priority order:

### Action A — Collect flow-control telemetry on device (30 min, needed regardless)
Before any code change: attach an iOS device with Instruments or add temporary logging, connect to Engo 2, and log what value the flow-control characteristic (`…-cb9`) emits immediately after `setNotifyValue(true, for:)` is confirmed. This answers Suspect #2 definitively and is a prerequisite for any fix.

### Action B — Verify queryID requirement with a one-line BLE sniffer test (requires Wireshark/PacketLogger or second device running the SDK demo)
Connect to Engo 2 using the official iOS SDK demo app and capture the BLE packet for a `txt` command. Compare the wire bytes to our frame. This will show whether `format=0x01` + queryID byte is on the wire. If it is, Suspect #1 is confirmed.

### Action C — Add queryID to `ActiveLookCommand.encode` (highest-confidence code change, only after A/B)
Change `ActiveLookCommand.encode` default to include a 1-byte auto-incrementing queryID (`format nibble = 0x01`). This is a ~10-line change to `ActiveLookCommand.swift` and a corresponding update to `ActiveLookGlassesAdapter` to maintain a `queryID: UInt8` counter. Tests need updating to expect the new frame format.

**If A reveals flow-control `off` is being sent:** also add flow-control value handling to `Coordinator.peripheral(_:didUpdateValueFor:)` before any display commands.

**These two fixes together address Suspects #1 and #2. Do not ship either individually as a speculative patch — do A and B first.**

---

## Open Questions

1. **Does the Engo 2 firmware silently accept `format=0x00` (no queryID) for application commands like `txt`, `power`, `clear`?**  
   Cannot determine from source alone. Requires either (a) official firmware documentation from Microoled/ActiveLook, (b) BLE packet capture comparing SDK vs our traffic on device, or (c) direct testing with a minimal `format=0x00` frame on a test harness.

2. **Does Engo 2 emit `FlowControl.off` (value 2) immediately after BLE connect, before its display subsystem is ready?**  
   Cannot determine from source. Requires Instruments logging on device. The SDK's 0.4–1.0 s DIS-discovery delay may exist precisely to avoid this window.

3. **Does `cfgSet` affect raw `txt` commands (i.e., is a configuration context required even for primitive graphics commands)?**  
   The `FlowControlState.missingConfiguration = 6` enum value suggests the device can signal this error. The demo app's `txt` examples only appear after `cfgSet` in tests using custom fonts. For stock font IDs (1–3), the answer is likely "no" but is unverified on Engo 2.

4. **What is the correct rotation value for readable text on Engo 2?**  
   Our code uses rotation=4 (`topLR`) with a comment incorrectly calling it "bottomRL". The demo app's custom layout uses `bottomRL` (=0). The correct value for the AR projection optics of the specific Engo 2 wearer configuration must be determined by visual inspection once the blank-screen bug is resolved.

5. **What firmware version is on Joe's Engo 2?**  
   The demo app checks `isFirmwareAtLeast(version: "4.0")` and refuses to show commands for older firmware. We skip this check entirely. If the glasses are running pre-4.0 firmware, some command IDs may differ (notably `demo`/`test` command 0x03/0x04 changed at 4.0, but the commands we use — 0x00, 0x01, 0x37 — appear stable across versions in the SDK's `CommandID.swift`).

---

## Appendix: Wire Format Reference

### Official SDK frame for `glasses.power(on: true)` (queryId=0x05 example):
```
FF 00 01 07 05 01 AA
```
- 0xFF = header
- 0x00 = cmdID (power)
- 0x01 = format nibble (1 queryID byte follows length)
- 0x07 = total length (7 bytes)
- 0x05 = queryID
- 0x01 = data (on=true)
- 0xAA = footer

### Our frame for `ActiveLookCommand.power(on: true)`:
```
FF 00 00 06 01 AA
```
- 0xFF = header
- 0x00 = cmdID (power)
- 0x00 = format nibble (0 queryID bytes)
- 0x06 = total length (6 bytes)
- 0x01 = data (on=true)
- 0xAA = footer

### Official SDK frame for `glasses.txt(x:20, y:40, rotation:.topLR, font:3, color:15, string:"0:00")` (queryId=0x06):
```
FF 37 01 12 06 00 14 00 28 04 03 0F 30 3A 30 30 00 AA
```
- format=0x01 (queryID present), length=18
- queryID=0x06
- x=0x0014=20, y=0x0028=40, rotation=0x04, font=0x03, color=0x0F
- "0:00\0" = 30 3A 30 30 00

### Our frame for `ActiveLookCommand.text(x:20, y:40, rotation:4, fontSize:3, color:15, string:"0:00")`:
```
FF 37 00 11 00 14 00 28 04 03 0F 30 3A 30 30 00 AA
```
- format=0x00 (no queryID), length=17
- x=0x0014=20, y=0x0028=40, rotation=0x04, font=0x03, color=0x0F
- "0:00\0" = 30 3A 30 30 00
- **1 byte shorter; if firmware reads a queryID byte from this frame, it reads 0x00, then x_hi=0x14=20, x_lo=0x00 → x=0x1400=5120 → off-screen**

### SDK's `FlowControlState` values (from `ActiveLookTypes.swift`):
```
on = 1, off = 2, error = 3, overflow = 4, unexpectedDataType = 5, missingConfiguration = 6
```
Our `didUpdateValueFor` returns immediately for any non-battery characteristic, so values 1–6 are never processed.
```

---

**⚠️ I do not have a file-writing tool.** The main agent must write the above content to `/Users/joekrilov/Repos/AR-Runner/.squad/files/hud-forensic-report.md`. The content above is the complete verbatim file.

---

## TL;DR for Joe

**Two critical bugs, both present in all three PRs and never touched by any fix attempt:**

1. **Every command frame is missing the 1-byte queryID the Engo 2 firmware expects** (`format=0x00` vs. SDK's `format=0x01`). When `power(on:true)` is sent, the firmware reads our `0x01` (on-byte) as the queryID instead of data, sees an empty payload, and likely powers the display OFF — explaining the transition from "stuck on Connection Successful" (PR #49) to "blank screen" (PR #53/55). When `txt` is then sent, the firmware reads our first coordinate byte as the queryID and parses x as `0x1400 = 5120` — way off the 304-pixel display. Text renders off-screen, invisibly.

2. **The flow-control characteristic value is never read.** Our `didUpdateValueFor` drops all non-battery notifications. If the glasses signal `FlowControl.off` or `FlowControl.missingConfiguration` after connect, we write anyway; the glasses silently discard at the application layer while CoreBluetooth still ACKs at the GATT layer — producing the exact "writes succeed, nothing shows" symptom.

**Before writing any more code:** (a) log the flow-control characteristic value on-device immediately after connect, and (b) BLE-sniff one SDK `txt` frame to confirm the queryID is on the wire. Path to the full report: `/Users/joekrilov/Repos/AR-Runner/.squad/files/hud-forensic-report.md` (main agent must write it — this subagent has no file-write tool).
