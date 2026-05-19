I have all the evidence I need. The sibling report does not exist yet. Here is the complete forensic analysis:

---

# ActiveLook Protocol Spec — HUD Forensic Analysis

**(Report for `.squad/files/hud-api-spec-report.md` — delivered inline per constraints; coordinator should write to that path)**

---

## TL;DR

The spec confirms `txt` (0x37) is **not misuse** — it is a legitimate live-draw primitive and the current `clear` + 3×`txt` frame sequence is correctly encoded. The protocol-level root causes of the three failed attempts were (1) missing `power(on:true)` before any `txt` on each connect — fixed in PR #53; (2) commands blasted without waiting for `didWriteValueFor` — fixed in PR #55; and (3) `sendCommands` called before flow-control subscription confirmed — also fixed in PR #55. **One critical remaining gap:** the adapter's `didUpdateValueFor` handler routes **only battery-level notifications**, silently ignoring every Control-characteristic error value (0x03 "corrupt command", 0x06 "missing cfgWrite") and every TX-characteristic 0xE2 error response from the glasses — meaning if any command is rejected, the team is flying blind.

---

## Q1: Frame Format

**Source:** `ActiveLook/Activelook-API-Documentation:ActiveLook_API.md` §3.1

```
0xFF | cmdID(1B) | format(1B) | length(1–2B) | queryID(0–15B) | data(mB) | 0xAA
```

| Field | Value | Notes |
|---|---|---|
| Start | `0xFF` | Always 1 byte |
| Command ID | 1 byte | e.g. `0x37` for `txt`, `0x00` for `displayPower` |
| Command Format | 1 byte | Bit 4 (`0x10`) = 1 → length is 2 bytes; bits 0–3 = query ID byte count (0–15) |
| Length | 1 or 2 bytes (big-endian) | **Total frame size** — includes start byte, all header bytes, data, AND footer |
| Query ID | 0–15 bytes (optional) | User-defined correlation ID; echoed in response |
| Data | variable | Command parameters |
| Footer | `0xAA` | Always 1 byte |

**Key constraints:**
- Big-endian throughout (MSB first)
- **No checksum byte.** None in any frame format table.
- Maximum frame size: 533 bytes (512 data + 15 queryID + 6 overhead)
- Commands may span multiple BLE chunks; glasses reassemble using length + footer detection
- MTU must be negotiated at connection time

**Verified against code:** `ARRunnerCore/Sources/ARRunnerCore/Glasses/ActiveLookCommand.swift:122–150` — the `encode(id:payload:queryID:)` method matches this exactly. `clear` encodes as `[0xFF, 0x01, 0x00, 0x05, 0xAA]` (total=5, no data); spec example confirms this (§3.1 clear example table).

---

## Q2: `txt` (0x37) vs Layouts

**Source:** `ActiveLook_API.md` §4.6 (Graphics commands table), §5.7 (Text guide), §6.8 (Layouts and Pages)

**Spec definition of `txt` (0x37):**

> `txt | s16 x | s16 y | u8 r | u8 f | u8 c | str string[255]`  
> "Write text `string` at coordinates (x,y) with rotation, font size, and color"  
> Data length: ≥ 8 bytes

`txt` is a **general-purpose, per-invocation text draw command**. It is not scoped to "one-off" use — the spec offers no such restriction. Every call draws text at the specified absolute coordinate. It does NOT erase previous content at that location; the caller must issue `clear` or an overlapping `rectf(color=0)` first.

**Is using `txt` for live HUD updates misuse?** **No.** The spec explicitly demonstrates live use:
> "display text `hello 4` at (152;128) (center of the screen)" — §5.7

Section §6.1 recommends the layout system for efficiency: *"If a subset of your display can be defined by '1 fixed image' + '1 changing text string', then using the 'Layout' feature will simplify its management"* — but this is optimization advice, not a prohibition on `txt`.

**Verdict on our code:** Using `clear` + 3×`txt` per tick is spec-compliant. The `clear` before each frame is required because the display is memory-based and retains previous content (§6.2: "Think 'erasing'"). The current `RunningHUDFrame.frames(for:)` implementation is correct.

**Why the official app uses layouts:** `layoutClearAndDisplay` (0x69) is a single atomic operation (clear area + draw new text) that avoids the visible flicker of a separate `clear` + `txt` sequence and reduces BLE write count. It is more efficient but not the only valid path.

---

## Q3: Layouts for Live Data

**Source:** `ActiveLook_API.md` §4.9 (Layout commands), §5.10 (Layout guide), §5.10.2 (Default configuration)

### How a layout is defined (once, during setup)

`layoutSave` (0x60) — parameters ≥ 17 bytes:

| Offset | Type | Parameter |
|---|---|---|
| 0 | u8 | Layout ID (0–255) |
| 1 | u8 | Size of additional commands in bytes |
| 2–3 | u16 | Clipping region X (top-left corner) |
| 4 | u8 | Clipping region Y |
| 5–6 | u16 | Clipping region width |
| 7 | u8 | Clipping region height |
| 8 | u8 | ForeColor (0–15) |
| 9 | u8 | BackColor (0–15) |
| 10 | u8 | Font index |
| 11 | bool | TextValid (1 = show text argument) |
| 12–13 | u16 | Text anchor X (within clipping region) |
| 14 | u8 | Text anchor Y |
| 15 | u8 | Text rotation |
| 16 | bool | Text opacity |
| 17–125 | u8[size] | Additional graphic sub-commands |

**Requires `cfgWrite` before upload.** Additional sub-commands use an internal type table (image=0, circ=1, color=3, gauge=10, text=9, etc.)

**Example from spec:** `0xFF6000160A00000000012FFF0F00010100EE1E0401AA` — saves layout #10, full-screen clipping (0,0)/(303,255), font=1, forecolor=15, text at (238,30), rotation=4, opacity=on.

### How a layout is invoked with live data (per-tick)

**`layoutDisplay` (0x62):** `[id: u8, text: str (NUL-terminated)]`  
⚠️ **SPEC SAYS TEXT IS PASSED WITH DISPLAY COMMAND** — see note below.

**`layoutClearAndDisplay` (0x69):** `[id: u8, text: str (NUL-terminated)]`  
This is the canonical per-tick primitive for live data: it atomically clears the clipping region and redraws. **This is what the official app uses.**

Example from spec §5.11: `0xFF62000914383500AA` — display layout #20 with text "85\0".  
(Frame: start=FF, cmd=62, fmt=00, len=09, data=[14(id=20), 38, 35, 00("85\0")], footer=AA)

### Command ID table for layouts

| ID | Command | Purpose |
|---|---|---|
| 0x60 | `layoutSave` | Define + store layout (once per config) |
| 0x61 | `layoutDelete` | Remove layout (0xFF = all) |
| 0x62 | `layoutDisplay` | Per-tick live update: show text in layout |
| 0x63 | `layoutClear` | Erase layout clipping region |
| 0x64 | `layoutList` | Enumerate stored layouts |
| 0x65 | `layoutPosition` | Reposition layout (saved persistently) |
| 0x66 | `layoutDisplayExtended` | Per-tick with override position |
| 0x69 | `layoutClearAndDisplay` | **Atomic erase+draw — use for live HUD** |
| 0x6A | `layoutClearAndDisplayExtended` | Atomic with override position |

### Do layouts persist across power cycles?

**Yes.** Layouts are stored in flash (3MB shared configuration pool). They survive power-off, BLE disconnect, and reboot. They must be re-uploaded only if the configuration is deleted, the device is factory-reset, or the memory pool is exhausted. The spec documents a `usgCnt` (usage counter) and `installCnt` to manage the pool. The official app uploads layouts during initial pairing (`cfgWrite` + `layoutSave`), then uses only `layoutDisplay`/`layoutClearAndDisplay` per-tick. **The glasses therefore need `cfgSet` on each connect to select the correct configuration** — but no re-upload of layout data.

---

## Q4: Required Init Sequence

**Source:** `ActiveLook_API.md` §3.5 (Control server), §4.3 (General commands), §5.4 (Configurations)

**Mandatory before any display command will render:**

1. **Subscribe to Control characteristic notifications** (`0x…CB9`)  
   Without this, the glasses' flow control signals are not received and the firmware may drop commands when the buffer fills. The spec explicitly states this as a prerequisite.

2. **Subscribe to TX characteristic notifications** (`0x…CB8`)  
   Required to receive command responses (battery, vers, cfgRead replies) and error notifications (0xE2).

3. **`displayPower(on: true)` — cmdID `0x00`, payload `[0x01]`**  
   Engo 2 boots with the display in a low-power state after every BLE link-up. The firmware splash ("Connection Successful") is painted by firmware and bypasses the power gate — but every host-driven draw command (including `txt`, `clear`) is silently dropped until `displayPower` is sent. This was the rc4 root cause.  
   → **`AR-Runner/ARRunnerCore/Glasses/RunningHUDFrame.swift:141–156`** — `connectFrames()` correctly prepends `power(on:true)`.

4. **`cfgSet` (0xD2) if using layouts/images** — selects the named configuration whose layouts/images should be active. The official app calls this on every connect to make its named run-HUD configuration active before issuing `layoutDisplay` calls.

5. **Flow control GATE: wait for `didUpdateNotificationStateFor` confirming `isNotifying == true`** on the control characteristic before sending any commands.  
   → Implemented: `ActiveLookGlassesAdapter.swift:471–475`

**For the raw-`txt` HUD path (current v0.3)**, the sequence after connect should be:
```
[subscribe Control notify] → [subscribe TX notify]
→ [wait for flowControlNotifyConfirmed]
→ power(on:true)
→ clear
→ txt(time), txt(distance), txt(pace)
```
The adapter and `RunningHUDFrame.connectFrames()` implement this correctly after PRs #53 and #55.

---

## Q5: Notification / Response Channel

**Source:** `ActiveLook_API.md` §3.2 (Tx server), §3.3 (User data server), §3.4 (Sensor server), §3.5 (Control server), §4.15 Device commands (0xE2 error)

### Characteristic UUID mapping

| UUID suffix | Name | Direction | Purpose |
|---|---|---|---|
| `…CB8` | TX ActiveLook | Glasses → Master | Command responses, 0xE2 errors |
| `…CB9` | Control | Glasses → Master | Flow control + error codes |
| `…CBB` | Gesture Event | Glasses → Master | Hand-gesture detection |
| `…CBC` | Touch Event | Glasses → Master | Capacitive button tap |

### Control characteristic (0xCB9) values — **parsed as single byte**

| Value | Type | Meaning |
|---|---|---|
| `0x01` | Flow Ctrl | Buffer OK — client may send |
| `0x02` | Flow Ctrl | Buffer 75% full — **client MUST stop** |
| `0x03` | Error | Incomplete or corrupt command (ignored) |
| `0x04` | Error | Receive queue overflow |
| `0x05` | Error | Reserved |
| `0x06` | Error | **Missing `cfgWrite` before config modification** |

On error, the value persists until a new command arrives.

### TX characteristic (0xCB8) — error notification frame (cmdID 0xE2)

```
0xFF | 0xE2 | format | length | [cmdId: u8] [error: u8] [subError: u8] | 0xAA
```

Error codes:
- 1: generic error
- 2: missing `cfgWrite` before config modification
- 3: memory read/write error
- 4: **protocol decoding error** (malformed frame / unknown command ID)

`cmdId` = the command that triggered the error.

### 🚨 CRITICAL GAP IN CURRENT CODE

`ActiveLookGlassesAdapter.swift:757–764`:
```swift
// Battery level (Standard Battery Service 0x2A19) is the only TX
// notification we route in v0.1. Other notifications (gesture,
// touch, control flow) are spec'd but deferred to v1.
guard
    characteristic.uuid == CBUUID(string: ActiveLookGATT.batteryLevelChar),
    ...
else { return }
```

**The `didUpdateValueFor` delegate early-returns for ALL characteristics except battery level.** This means:
- Control char error codes (0x03, 0x06) are silently swallowed
- TX char 0xE2 error responses are silently swallowed
- **Flow control value changes (0x01 OK / 0x02 stop) are not obeyed** — the adapter only gates on subscription confirmation, never on the 0x02 "buffer full" value
- If any command is malformed or rejected (error 4), the team sees nothing

**This is the most important remaining debugging gap.** If any of the three `txt` commands are being rejected, there is currently no way to know.

---

## Q6: BLE UUIDs

**Source:** `ActiveLook_API.md` §2.3 (Services and characteristics)

**ActiveLook Command Interface Service:**
```
0783B03E-8535-B5A0-7140-A304D2495CB7
```

| Characteristic | UUID | Direction | Property |
|---|---|---|---|
| TX (glasses → watch, responses) | `0783B03E-8535-B5A0-7140-A304D2495CB8` | IN | Notify |
| **RX (watch → glasses, commands)** | `0783B03E-8535-B5A0-7140-A304D2495CBA` | OUT | Write, Write no response |
| Control (flow + errors) | `0783B03E-8535-B5A0-7140-A304D2495CB9` | IN | Notify |
| Gesture Event | `0783B03E-8535-B5A0-7140-A304D2495CBB` | IN | Notify |
| Touch Event | `0783B03E-8535-B5A0-7140-A304D2495CBC` | IN | Notify |

**Standard Battery Service:** `0x180F` / Battery Level char `0x2A19` (Read + Notify)

**WRITE TARGET:** `…CBA` (RX). Spec recommends **Write with Response** (`type: .withResponse`) — this is what the adapter correctly uses (`peripheral.writeValue(data, for: rxCharacteristic, type: .withResponse)`, `ActiveLookGlassesAdapter.swift:603`).

**Verified against code:** All UUIDs match `ActiveLookCommand.swift:159–168`.

---

## Q7: Smallest Fix

Based on the spec evidence and code audit, in priority order:

### Fix 1 — Parse error notifications (highest impact, ~20 lines)

**Add to `didUpdateValueFor` in `ActiveLookGlassesAdapter.swift:751`:**

```swift
// Control characteristic — flow control values AND error codes
if characteristic.uuid == CBUUID(string: ActiveLookGATT.controlChar),
   let data = characteristic.value, let byte = data.first {
    Task { [weak adapter] in await adapter?.handleControlValue(byte) }
    return
}
// TX characteristic — command responses including 0xE2 error notifications
if characteristic.uuid == CBUUID(string: ActiveLookGATT.txCharacteristic),
   let data = characteristic.value {
    Task { [weak adapter] in await adapter?.handleTXNotification(data) }
    return
}
```

Where `handleControlValue` logs (and eventually gates writes on) 0x02, and `handleTXNotification` parses the 0xE2 frame to emit a `GlassesStatusEvent.commandError(cmdID:error:subError:)`. **This alone will reveal whether the glasses are rejecting the `txt` commands and why.** This is pure debugging infrastructure — it adds observability without changing behavior.

### Fix 2 — Obey flow control 0x02 value (required for reliability, ~15 lines)

Currently the adapter halts on flow-control subscription confirmation but never checks the actual 0x01/0x02 runtime values. During a multi-command `sendCommands` call (4 frames: power, clear, 3×txt), if the buffer reaches 75%, the glasses send 0x02 but the adapter keeps writing. The spec says the client MUST stop. Add a `flowControlAllowsWrite: Bool` flag that gates the `write()` method.

### Fix 3 — Send `holdFlush` around the per-tick frame sequence (optional, removes flicker)

Wrap `clear` + 3×`txt` in hold/flush to prevent intermediate visible states:
```
holdFlush(action:0)  →  clear  →  txt(time)  →  txt(distance)  →  txt(pace)  →  holdFlush(action:1)
```
This sends one extra frame but eliminates the brief blank between `clear` and the first `txt`. Per the spec, `holdFlush(action:0xFF)` also resets any stuck hold state — sending this on connect before the power-on sequence is belt-and-braces.

### Fix 4 — Remove the phantom 0x3A command (bug in curated path)

`ActiveLookCommand.ID.widgetUpdate = 0x3A` and `updateWidget()` in `ActiveLookCommand.swift:31,71–76` refer to a command that **does not exist in the official ActiveLook spec.** The command table goes `0x38 polyline → 0x39 holdFlush → (gap) → 0x3C arc`. Any call to `updateField()` (the curated layout path) sends a 0x3A byte that will trigger Control char error 0x03 or TX char error 0xE2 with code 4 (protocol decoding error). This code path is dormant in v0.3 (the `updateField` / `displayLayout` curated path is disabled), but should be corrected to use `layoutDisplay` (0x62) with `[id, text_string, 0x00]` when the curated path ships.

### Fix 5 — Correct `displayLayout` encoding (bug in curated path)

`ActiveLookCommand.displayLayout(id:)` currently sends only `[id]`. The spec says `layoutDisplay` (0x62) takes `u8 id` + `str text[255]` — the text string is part of this command, not a separate widgetUpdate. The frame that renders "12.5" km/h via layout #13 is: `0xFF62000B0D31322E35AA` (id=0x0D, text="12.5\0"). The curated path needs to be rewritten entirely when it ships.

---

## Cross-references to iOS SDK report

The sibling report (`/Users/joekrilov/Repos/AR-Runner/.squad/files/hud-forensic-report.md`) **does not exist yet** at time of writing. No reconciliation possible.

**Existing local evidence from `activelook-hud-rendering/SKILL.md`** (which captures prior SDK research):
- Agrees: `power(on:true)` before first draw is critical (§7a) ✅ confirmed by spec §4.3
- Agrees: Write serialization + flow control gate are required ✅ confirmed by spec §3.5
- States `0x3A widgetUpdate` is the correct per-tick update ❌ **CONTRADICTED BY SPEC** — no such command exists in `ActiveLook_API.md`. Spec §4.9 shows `layoutDisplay` (0x62) as the only per-tick layout update command, and it carries the text payload directly.
- States `displayLayout` (0x62) sends `[id]` only ❌ **CONTRADICTED BY SPEC** — §4.9 and the example at §5.11 both show `[id, text_string]`.

**Inference:** The `0x3A` phantom command was introduced from an unofficial source or an SDK version not reflected in the current `ActiveLook_API.md` (firmware 4.12.0). The v0.3 raw-`txt` HUD is unaffected because it bypasses the curated layout path entirely — but the curated path will silently fail on real hardware until 0x3A is replaced with the correct 0x62 + text payload pattern.

---

## Appendix — Wire Frame Verification

**`clear` (cmdID 0x01):**  
Spec example: `FF 01 00 05 AA` (length=5)  
Code output: `encode(id:.clear, payload:[])` → `[0xFF, 0x01, 0x00, 0x05, 0xAA]` ✅

**`displayPower(on:true)` (cmdID 0x00):**  
Expected: `FF 00 00 06 01 AA` (length=6)  
Code output: `encode(id:.power, payload:[0x01])` → `[0xFF, 0x00, 0x00, 0x06, 0x01, 0xAA]` ✅

**`txt` at (20,40), rotation=4, font=3, color=15, "0:00\0":**  
Payload: `[0x00, 0x14, 0x00, 0x28, 0x04, 0x03, 0x0F, 0x30, 0x3A, 0x30, 0x30, 0x00]` = 12 bytes  
Frame length = 1+1+1+1+12+1 = 17 = 0x11  
Expected: `FF 37 00 11 00 14 00 28 04 03 0F 30 3A 30 30 00 AA` ✅

**Spec example `txt` (§5.7): `0xFF3700140098008004020F68656C6C6F203400AA`**  
Decoded: x=152, y=128, rotation=4, font=2, color=15, "hello 4\0", length=20 ✅ — format identical to our encoder.

---

*Citations:*
- `ActiveLook/Activelook-API-Documentation:ActiveLook_API.md` — §2.3, §3.1, §3.5, §4.3, §4.6, §4.9, §5.4, §5.7, §5.10, §5.11, §6.1–6.8
- `AR-Runner/ARRunnerCore/Sources/ARRunnerCore/Glasses/ActiveLookCommand.swift:26–169`
- `AR-Runner/ARRunnerCore/Sources/ARRunnerCore/Glasses/RunningHUDFrame.swift:107–156`
- `AR-Runner/ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift:430–512, 590–624, 751–764`
- `AR-Runner/.squad/skills/activelook-hud-rendering/SKILL.md:7–13, 31–32`
- `AR-Runner/.squad/skills/activelook-ble-adapter-pitfalls/SKILL.md:29–34`

---

## TL;DR (final response to coordinator)

**Protocol-level verdict:** `txt` (0x37) is not misuse — the spec permits it as a live-draw primitive and the current `clear` + 3×`txt` encoding is byte-perfect against the spec. The three failed attempts were delivery failures (no `power(on:true)`, no write serialization, no flow-control gate), all of which PRs #53 and #55 claim to fix. **The critical remaining gap is that `didUpdateValueFor` in the adapter routes only battery notifications and silently discards all Control-char error values (0x03/0x06) and TX-char 0xE2 error responses** — so if the glasses are rejecting commands for any reason (malformed frame, protocol decode error, wrong connection state), the watch gets no feedback whatsoever. Adding 20 lines to parse and log these notifications would immediately reveal whether the glasses are accepting the `txt` commands or not. Secondary finding: the curated layout path has two dead bugs — `0x3A widgetUpdate` is a phantom command absent from the official spec, and `layoutDisplay` must carry the text string not just the ID — both are dormant in v0.3 but will cause silent failures when that path ships. Full report path: `/Users/joekrilov/Repos/AR-Runner/.squad/files/hud-api-spec-report.md`.
