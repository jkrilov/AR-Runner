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
/// This file is deliberately Foundation-only so it builds on the Linux CI
/// runner; the watchOS adapter consumes these `[UInt8]` payloads directly.
public enum ActiveLookCommand {
    // MARK: - Command IDs (subset required for v0.1)

    public enum ID: UInt8 {
        case power          = 0x00
        case clear          = 0x01
        case battery        = 0x05
        case luma           = 0x10
        case widgetUpdate   = 0x3A
        case textUpdate     = 0x37
        case layoutDisplay  = 0x62
        case layoutPosition = 0x65
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

    /// Request the glasses' battery level. Response arrives as a TX notification.
    /// (CmdID 0x05)
    public static func batteryQuery(queryID: UInt16 = 0) -> [UInt8] {
        encode(id: .battery, payload: [], queryID: queryID == 0 ? nil : queryID)
    }

    /// Set HUD luminosity (0–15 per ActiveLook spec; we clamp).
    public static func luma(level: UInt8) -> [UInt8] {
        let clamped = min(level, 15)
        return encode(id: .luma, payload: [clamped])
    }

    /// Activate a baked layout by its on-device numeric ID. (CmdID 0x62)
    /// `text` is optional initial value for the layout's primary slot.
    public static func displayLayout(id: UInt8, text: String = "") -> [UInt8] {
        var payload: [UInt8] = [id]
        payload.append(contentsOf: Array(text.utf8))
        payload.append(0x00) // null terminator
        return encode(id: .layoutDisplay, payload: payload)
    }

    /// Update one slot inside the currently displayed layout. (CmdID 0x3A)
    /// This is the runtime hot-path encoder — keep it allocation-light.
    public static func updateWidget(layoutID: UInt8, fieldIndex: UInt8, value: String) -> [UInt8] {
        var payload: [UInt8] = [layoutID, fieldIndex]
        payload.append(contentsOf: Array(value.utf8))
        payload.append(0x00)
        return encode(id: .widgetUpdate, payload: payload)
    }

    // MARK: - Frame builder

    /// Wraps `payload` in the ActiveLook framing bytes.
    /// Exposed `internal` so tests can exercise edge cases (long payloads,
    /// queryID variations) without going through every command-specific helper.
    static func encode(id: ID, payload: [UInt8], queryID: UInt16? = nil) -> [UInt8] {
        let queryBytes: [UInt8] = queryID.map { [UInt8($0 >> 8), UInt8($0 & 0xFF)] } ?? []
        let queryLen = UInt8(queryBytes.count) // 0 or 2 in practice; spec allows 0–15

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
