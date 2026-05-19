// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure-value gatekeeper for the standard BLE Battery Service (0x180F /
/// 0x2A19) notification stream.
///
/// Lives in Core so it can be unit-tested on Linux CI (no CoreBluetooth
/// imports). The watch's `ActiveLookGlassesAdapter` owns the only
/// production instance; the adapter feeds raw bytes from `didUpdateValueFor`
/// in and decides whether to `emit(.batteryLevel(...))` based on the
/// returned action.
///
/// Two responsibilities:
///   1. **Range validation.** The Bluetooth SIG spec defines 0x2A19 as a
///      single `uint8` in `[0, 100]`. Out-of-range bytes are firmware
///      bugs / charger glitches and MUST be dropped, not propagated to the
///      UI (see Amber's rc17 QA item C4 "value sanity").
///   2. **Dedup of identical consecutive notifications.** The 30 s notify
///      cadence often re-publishes the same percent; suppressing redundant
///      emits keeps downstream observers (WC sender, watch UI) quiet
///      without adding their own equality checks (Amber's QA item C5).
public struct BatteryLevelFilter: Sendable {
    public enum Action: Sendable, Equatable {
        /// Caller should emit `.batteryLevel(level)`.
        case emit(Int)
        /// Caller should drop the notification silently (duplicate of the
        /// previous emit).
        case dropDuplicate
        /// Caller should drop and log — byte was outside `[0, 100]`.
        case dropInvalid(rawByte: UInt8)
    }

    private var lastEmitted: Int?

    public init() {
        self.lastEmitted = nil
    }

    /// Resets the dedup memory. The adapter calls this on every transition
    /// **out of** `.connected` (drop / disconnect) so the first
    /// notification after a reconnect always lands — even when the
    /// battery level hasn't changed in the interim, the UI was showing
    /// "unknown" during the gap and deserves a fresh value.
    public mutating func reset() {
        lastEmitted = nil
    }

    /// Decide what to do with an incoming battery-level byte. Adapter
    /// pattern:
    /// ```swift
    /// switch batteryFilter.process(byte: rawByte) {
    /// case .emit(let level):
    ///     emit(.batteryLevel(level))
    /// case .dropDuplicate:
    ///     break
    /// case .dropInvalid(let raw):
    ///     logger.warning("Battery byte 0x\(String(raw, radix: 16)) out of range")
    /// }
    /// ```
    public mutating func process(byte: UInt8) -> Action {
        guard byte <= 100 else {
            return .dropInvalid(rawByte: byte)
        }
        let level = Int(byte)
        if let last = lastEmitted, last == level {
            return .dropDuplicate
        }
        lastEmitted = level
        return .emit(level)
    }
}
