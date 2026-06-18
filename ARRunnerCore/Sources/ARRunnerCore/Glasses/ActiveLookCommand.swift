// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure-Swift encoder for the ActiveLook BLE wire format.
///
/// Frame layout (per `Activelook-API-Documentation/ActiveLook_API.md` §3.1):
///
/// ```text
/// 0xFF | cmdID | format | length(1–2) | queryID? | data | 0xAA
/// ```
///
/// `format` byte:
///   * bit 4 (0x10) — set when length is encoded as 2 bytes, big-endian
///   * bits 0–3   — number of bytes in the queryID (0–15)
///
/// `length` is the **total** frame size including the start byte and the
/// trailing 0xAA footer.
///
/// **queryID is implicitly required by Engo 2 firmware.** Although the spec
/// marks queryID as 0–15 bytes (optional), the official ActiveLook iOS SDK
/// (`Glasses.sendCommand`) ALWAYS attaches a 1-byte queryID for every
/// application command — `withoutQueryId: true` is only passed for three DFU
/// ops (`qspiErase`, `qspiWrite`, `reset`). Mirror that exactly: the encoder
/// defaults to `format = 0x01` with a 1-byte queryID. PRs #49, #53, #55 all
/// shipped `format = 0x00` frames; the Engo 2 firmware then misread the first
/// payload byte as the queryID — `power(on:true)` became a no-op, `txt`
/// coordinates shifted by 1 byte rendered text 5000+ px off-screen.
///
/// The adapter is responsible for stamping a unique incrementing queryID on
/// each frame just before write; this encoder emits `queryID = 0x00` as a
/// deterministic placeholder so unit tests can pin exact byte sequences.
///
/// This file is deliberately Foundation-only so it builds on the Linux CI
/// runner; the watchOS adapter consumes these `[UInt8]` payloads directly.
public enum ActiveLookCommand {
    // MARK: - Command IDs (subset required for v0.1)

    public enum ID: UInt8 {
        case power          = 0x00
        case clear          = 0x01
        case battery        = 0x05
        case luma           = 0x10
        case holdFlush      = 0x39
        case textUpdate     = 0x37
        case layoutDisplay  = 0x62
        case layoutClearAndDisplay = 0x69
        case layoutPosition = 0x65
        case cfgSet         = 0xD2
        case imgDisplay     = 0x42
    }

    // MARK: - Public encoders

    /// Power on / off the display. (CmdID 0x00)
    public static func power(on: Bool) -> [UInt8] {
        encode(id: .power, payload: [on ? 0x01 : 0x00])
    }

    /// Clear the display to black. (CmdID 0x01)
    public static func clear() -> [UInt8] {
        encode(id: .clear, payload: [])
    }

    /// Per ActiveLook spec §4.6: defer display commits while building a frame.
    /// Use action 0 (HOLD) before a batch of draw commands, action 1 (FLUSH)
    /// after to atomically commit. Eliminates flicker on per-tick HUD updates.
    public static func holdFlush(hold: Bool) -> [UInt8] {
        encode(id: .holdFlush, payload: [hold ? 0x00 : 0x01])
    }

    /// Select the named ActiveLook configuration. Must be called once per
    /// connect before any display command that references ALooK assets
    /// (fonts 1–5, layouts, images). The ALooK configuration ships
    /// pre-installed on Engo 2 and contains all stock fonts and layouts.
    /// Without this, txt(font:3) silently fails — fonts live in the config,
    /// not in base firmware.
    ///
    /// Per ActiveLook-Visual-Assets README: `cfgSet("ALooK")` is required
    /// to use fonts, layouts, and images from the default configuration.
    /// The official demo app (`LayoutCommandsViewController.swift`) calls
    /// `glasses.cfgSet(name: "ALooK")` before every single display command
    /// — treat it as a mandatory prerequisite, not an optional hint.
    ///
    /// Wire format: cmdID 0xD2, payload = UTF-8 name bytes + 0x00 NUL.
    public static func cfgSet(name: String) -> [UInt8] {
        var payload = Array(name.utf8)
        payload.append(0x00)   // NUL-terminate the config name string
        return encode(id: .cfgSet, payload: payload)
    }

    /// Request the glasses' battery level. Response arrives as a TX notification.
    /// (CmdID 0x05) The adapter stamps a fresh queryID on each frame so the
    /// `queryID` parameter here is only useful for tests pinning exact bytes.
    public static func batteryQuery(queryID: UInt8 = 0x00) -> [UInt8] {
        encode(id: .battery, payload: [], queryID: queryID)
    }

    /// Set HUD luminosity (0–15 per ActiveLook spec; we clamp).
    public static func luma(level: UInt8) -> [UInt8] {
        let clamped = min(level, 15)
        return encode(id: .luma, payload: [clamped])
    }

    /// Activate a baked layout by its on-device numeric ID and render `text`
    /// into the layout's text field. (CmdID 0x62 — `layoutDisplay`.)
    ///
    /// Per ActiveLook API spec §4.9, the `layoutDisplay` frame is
    /// `[id, text_string, 0x00]` — the NUL-terminated text string is part of
    /// **this** command, not a separate update. The example in spec §5.11
    /// (`0xFF62000914383500AA`) displays layout #20 with text `"85\0"`.
    ///
    /// A v0.1 bug shipped `[id]` only; the layout activated but rendered no
    /// text. `text` defaults to the empty string (still NUL-terminated) so
    /// callers that only need to activate a slot — and push content later
    /// via `layoutClearAndDisplay(...)` — keep working unchanged.
    public static func displayLayout(id: UInt8, text: String = "") -> [UInt8] {
        var payload: [UInt8] = [id]
        payload.append(contentsOf: Array(text.utf8))
        payload.append(0x00)   // NUL-terminate the layout text string
        return encode(id: .layoutDisplay, payload: payload)
    }

    /// Atomically clear a layout's clipping region and redraw it with `text`.
    /// (CmdID 0x69 — `layoutClearAndDisplay`.) This is the correct per-tick
    /// live-update primitive per ActiveLook spec §4.9: a single atomic
    /// erase+draw avoids the ghosting a bare `layoutDisplay` (0x62) redraw
    /// would leave behind when the new value is shorter than the old one.
    ///
    /// Wire format (identical shape to `layoutDisplay`): `[id, text, 0x00]`.
    ///
    /// Replaces the phantom `0x3A widgetUpdate` command removed in this
    /// change — that command ID does not exist in `ActiveLook_API.md`
    /// (the table goes `0x39 holdFlush → (gap) → 0x3C arc`) and triggered a
    /// 0xE2 protocol-decode error (code 4) on Engo 2 firmware.
    public static func layoutClearAndDisplay(id: UInt8, text: String) -> [UInt8] {
        var payload: [UInt8] = [id]
        payload.append(contentsOf: Array(text.utf8))
        payload.append(0x00)   // NUL-terminate the layout text string
        return encode(id: .layoutClearAndDisplay, payload: payload)
    }

    /// Draw a UTF-8 string at an absolute (x, y) coordinate on the HUD.
    /// (CmdID 0x37 — `txt`.) Used by the v0.3 raw-text running HUD that
    /// renders time / distance / pace without needing a pre-baked on-device
    /// layout slot.
    ///
    /// Payload layout (per `Activelook-API-Documentation/ActiveLook_API.md`
    /// §5.7 and `Activelook-ios-sdk` `Commands.swift` `txt`):
    /// ```text
    /// x(i16 BE) | y(i16 BE) | rotation(u8) | font(u8) | color(u8) | bytes | 0x00
    /// ```
    ///
    /// Defaults match ActiveLook's iOS sample app for landscape, head-up
    /// reading orientation on Engo 2 (rotation = 4 → bottom-RL, the natural
    /// orientation when the glasses sit on a runner's nose; font = 3 →
    /// largest stock font; color = 15 → full white on the monochrome OLED).
    public static func text(
        x: Int16,
        y: Int16,
        rotation: UInt8 = 4,
        fontSize: UInt8 = 3,
        color: UInt8 = 15,
        string: String
    ) -> [UInt8] {
        let xBits = UInt16(bitPattern: x)
        let yBits = UInt16(bitPattern: y)
        var payload: [UInt8] = []
        payload.reserveCapacity(7 + string.utf8.count + 1)
        payload.append(UInt8((xBits >> 8) & 0xFF))
        payload.append(UInt8(xBits & 0xFF))
        payload.append(UInt8((yBits >> 8) & 0xFF))
        payload.append(UInt8(yBits & 0xFF))
        payload.append(rotation)
        payload.append(fontSize)
        payload.append(color)
        payload.append(contentsOf: Array(string.utf8))
        payload.append(0x00)
        return encode(id: .textUpdate, payload: payload)
    }

    /// Display a preloaded image from the active configuration's flash
    /// at the given framebuffer coordinates. (CmdID 0x42 — `imgDisplay`.)
    ///
    /// Per ActiveLook API spec §4.7 (modern, post-4.0.0 firmware):
    /// ```text
    /// id(u8) | x(u16 BE) | y(u16 BE)
    /// ```
    ///
    /// Unlike `txt` (0x37), `imgDisplay` carries **no rotation flag** —
    /// the icon bitmap is blitted framebuffer-direct at `(x, y)` as its
    /// top-left corner. The Engo 2 lens still applies its 180°
    /// point-symmetric flip, so an icon at fb `(x, y)` with dimensions
    /// `w × h` appears to the wearer at wearer coords `[303 − x − w,
    /// 303 − x]` × `[255 − y − h, 255 − y]`, rotated 180°. Pre-rotated
    /// assets (like the stock ALooK preloaded icons shipped in
    /// `ActiveLook/Activelook-Visual-Assets`) are designed so the
    /// post-lens orientation reads upright to the wearer.
    ///
    /// **Preloaded ALooK icons** used by the rc16 live HUD (flash IDs
    /// from the Visual-Assets repo README — the leading number in each
    /// asset filename is the literal `id` byte the firmware indexes by):
    /// * 40 → `40_chrono_40x40` (time)
    /// * 12 → `12_heart-beat_28x28` (heart rate)
    /// *  9 → `9_distance_28x28` (distance)
    /// * 17 → `17_pace-avg_28x28` (avg pace)
    ///
    /// These ship inside the stock `ALooK` configuration which we already
    /// activate in `connectFrames()` / `framesWithPowerOn(for:)` via
    /// `cfgSet("ALooK")` (rc8 PR #60). No upload pipeline (`cfgWrite` /
    /// chunked `imgSave`) is required to render them — that whole
    /// iceberg, documented in `.squad/files/hud-icon-research.md` from
    /// rc15, applies only to *custom* user-supplied artwork.
    public static func imgDisplay(id: UInt8, x: UInt16, y: UInt16) -> [UInt8] {
        var payload: [UInt8] = []
        payload.reserveCapacity(5)
        payload.append(id)
        payload.append(UInt8((x >> 8) & 0xFF))
        payload.append(UInt8(x & 0xFF))
        payload.append(UInt8((y >> 8) & 0xFF))
        payload.append(UInt8(y & 0xFF))
        return encode(id: .imgDisplay, payload: payload)
    }

    // MARK: - Frame builder

    /// Wraps `payload` in the ActiveLook framing bytes.
    ///
    /// **Always emits a 1-byte queryID by default** (`format = 0x01`) to
    /// match the official ActiveLook iOS SDK convention. Engo 2 firmware
    /// silently mis-parses frames that omit the queryID byte (PRs #49/#53/#55
    /// root cause). Callers pass `withoutQueryId: true` ONLY for DFU ops
    /// (`qspiErase`, `qspiWrite`, `reset`) per the SDK's own convention —
    /// none of those are wired in v0.3.
    ///
    /// The encoder writes a deterministic `queryID = 0x00` placeholder; the
    /// adapter stamps a unique incrementing queryID on every frame just
    /// before `peripheral.writeValue` so each command is uniquely
    /// correlatable with its eventual response on the TX characteristic.
    ///
    /// Exposed `internal` so tests can exercise edge cases (long payloads,
    /// queryID variations, withoutQueryId opt-out) without going through
    /// every command-specific helper.
    static func encode(
        id: ID,
        payload: [UInt8],
        queryID: UInt8 = 0x00,
        withoutQueryId: Bool = false
    ) -> [UInt8] {
        let queryBytes: [UInt8] = withoutQueryId ? [] : [queryID]
        let queryLen = UInt8(queryBytes.count) // 0 (DFU only) or 1 (everything else)

        // Total = 0xFF + cmd + format + lenBytes + queryBytes + payload + 0xAA
        // Tentatively assume 1-byte length, then promote if it overflows.
        let oneByteTotal = 1 + 1 + 1 + 1 + queryBytes.count + payload.count + 1
        let useTwoByteLen = oneByteTotal > 0xFF
        let total = useTwoByteLen ? oneByteTotal + 1 : oneByteTotal

        var format: UInt8 = queryLen & 0x0F
        if useTwoByteLen { format |= 0x10 }

        var frame: [UInt8] = []
        frame.reserveCapacity(total)
        frame.append(0xFF)
        frame.append(id.rawValue)
        frame.append(format)
        if useTwoByteLen {
            frame.append(UInt8((total >> 8) & 0xFF))
            frame.append(UInt8(total & 0xFF))
        } else {
            frame.append(UInt8(total & 0xFF))
        }
        frame.append(contentsOf: queryBytes)
        frame.append(contentsOf: payload)
        frame.append(0xAA)
        return frame
    }
}

// MARK: - GATT UUIDs

/// String constants for the ActiveLook custom GATT profile. Kept as plain
/// strings (not `CBUUID`) so this file stays Linux-buildable in `ARRunnerCore`.
/// The watchOS adapter wraps these in `CBUUID(string:)` at the boundary.
public enum ActiveLookGATT {
    public static let commandService     = "0783B03E-8535-B5A0-7140-A304D2495CB7"
    public static let txCharacteristic   = "0783B03E-8535-B5A0-7140-A304D2495CB8" // notify
    public static let controlChar        = "0783B03E-8535-B5A0-7140-A304D2495CB9" // notify (flow control)
    public static let rxCharacteristic   = "0783B03E-8535-B5A0-7140-A304D2495CBA" // write
    public static let gestureChar        = "0783B03E-8535-B5A0-7140-A304D2495CBB" // notify (v1)
    public static let touchChar          = "0783B03E-8535-B5A0-7140-A304D2495CBC" // notify (v1)

    /// Standard battery service / characteristic.
    public static let batteryService     = "180F"
    public static let batteryLevelChar   = "2A19"
}
