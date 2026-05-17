// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Per-`fieldIndex` last-write-wins throttle for HUD field updates (D6).
///
/// Glasses do not need 60Hz — ActiveLook renders autonomously from the
/// pre-baked layout and runtime traffic is ~20–40 byte field-value writes per
/// metric tick. The audit (`.squad/audits/2026-05-16-weiss-ar-ble.md` P1.4
/// note on `updateField`) flagged the absence of any backstop: at the
/// telemetry-run preset (6 slots × controller emission rate) we can saturate
/// the BLE link.
///
/// This throttle is the cheap, deterministic backstop: it answers a single
/// question — "should this `(fieldIndex, timestamp)` update be sent now?" —
/// based on a configurable minimum gap per fieldIndex. Callers are expected
/// to drop the update on a `false` answer; the *value* itself is not buffered
/// because the metric stream already produces fresh values on the next tick
/// (last-write-wins is the desired semantic).
///
/// Pure value type; trivially `Sendable`. Caller owns the storage and is
/// responsible for serialising access (e.g. via an enclosing actor).
public struct HUDFieldThrottle: Sendable, Equatable {
    /// Default cadence: one update per field per second. Matches the
    /// 1Hz controller emission rate without ever fast-forwarding beyond it.
    public static let defaultMinimumInterval: TimeInterval = 1.0

    public let minimumInterval: TimeInterval
    private var lastSentByField: [UInt8: Date] = [:]

    public init(minimumInterval: TimeInterval = HUDFieldThrottle.defaultMinimumInterval) {
        precondition(minimumInterval >= 0, "minimumInterval must be non-negative")
        self.minimumInterval = minimumInterval
    }

    /// Returns `true` if the caller should send this update; records the
    /// timestamp so subsequent calls within the window are rejected.
    /// Returns `false` (without recording) when the previous send for this
    /// `fieldIndex` was within `minimumInterval` of `now`.
    public mutating func shouldSend(fieldIndex: UInt8, now: Date) -> Bool {
        if let last = lastSentByField[fieldIndex],
           now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        lastSentByField[fieldIndex] = now
        return true
    }

    /// Drop all per-field state. Call on disconnect so the next reconnect's
    /// first update for each field is delivered immediately.
    public mutating func reset() {
        lastSentByField.removeAll(keepingCapacity: true)
    }
}
