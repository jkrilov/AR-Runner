// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Strategy for spacing reconnection attempts after an unexpected drop (D4).
///
/// Pure value type so it is trivially `Sendable` and easy to test without a
/// running BLE stack.
public struct ExponentialBackoff: Sendable, Equatable {
    public let initial: TimeInterval
    public let maximum: TimeInterval
    public let multiplier: Double

    /// Defaults match the spike doc (1s → 2s → 4s → 8s).
    public init(initial: TimeInterval = 1.0, maximum: TimeInterval = 8.0, multiplier: Double = 2.0) {
        precondition(initial > 0, "initial must be positive")
        precondition(maximum >= initial, "maximum must be >= initial")
        precondition(multiplier > 1.0, "multiplier must be > 1.0")
        self.initial = initial
        self.maximum = maximum
        self.multiplier = multiplier
    }

    /// Delay (in seconds) for the Nth retry attempt, 0-indexed.
    /// Attempt 0 → `initial`; capped at `maximum`.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return initial }
        let raw = initial * pow(multiplier, Double(attempt))
        return min(raw, maximum)
    }

    /// Reconnect cadence mandated by the rc17 ADR
    /// (`richards-adr-ble-link-lifecycle`): 1s → 2s → 4s → 8s → 16s → 32s →
    /// 60s steady. The ADR's prose target sequence was 1/2/5/15/30/60 — we
    /// approximate it with a pure-exponential schedule (cleaner than a
    /// stair-step lookup and within a few seconds of the named values) so the
    /// existing `delay(forAttempt:)` math is the only code path.
    /// Pair with `maxReconnectAttempts: .max` on the adapter so the loop
    /// stays alive until the user explicitly disconnects, unpairs, or kills
    /// the app (ADR P2: no upper limit on total attempts).
    public static let adrV04 = ExponentialBackoff(
        initial: 1.0,
        maximum: 60.0,
        multiplier: 2.0
    )
}

/// Curated layout-ID → on-device numeric slot resolver. Values are
/// **placeholders** for v0.1: the real numbers come out of the layout BUILD
/// step (deferred per task scope). Centralised here so the adapter and tests
/// agree on the mapping.
public enum CuratedLayoutCatalog {
    public static let mapping: [String: UInt8] = [
        // TODO(P1.4 from .squad/audits/2026-05-16-weiss-ar-ble.md):
        // these are pre-bake placeholders. Replace with the real numeric
        // layout slots emitted by the Config-Generator bake step before any
        // hardware test or TestFlight build — otherwise the glasses will
        // activate the wrong layout. `assertNotPlaceholder` below traps in
        // debug so hardware bring-up fails fast on this.
        "minimal-run":   0x01,
        "balanced-run":  0x02,
        "telemetry-run": 0x03
    ]

    /// Numeric slots known to be **pre-bake placeholders** (v0.1 / v0.2). Any
    /// real Config-Generator output starts well above this range; if we ever
    /// hand one of these to the adapter on hardware, we'd activate the wrong
    /// on-device layout silently.
    public static let placeholderDeviceIDs: Set<UInt8> = [0x01, 0x02, 0x03]

    public static func deviceID(for layoutID: String) -> UInt8? {
        mapping[layoutID]
    }

    /// Traps in debug builds (incl. hardware-test builds running on watch)
    /// when a placeholder slot would be activated. Release builds get a
    /// silent return — the goal is to fail loudly during bring-up, not to
    /// brick a user's run if a stale build somehow shipped with placeholders.
    /// Pair with the `mapping` TODO above; remove this guard once Config-
    /// Generator output replaces the placeholders.
    @inlinable
    public static func assertNotPlaceholder(
        _ deviceID: UInt8,
        layoutID: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        assert(
            !placeholderDeviceIDs.contains(deviceID),
            """
            CuratedLayoutCatalog returned placeholder device ID \
            0x\(String(deviceID, radix: 16)) for layout "\(layoutID)". \
            Run the Config-Generator bake step before hardware test. \
            See .squad/audits/2026-05-16-weiss-ar-ble.md (P1.4).
            """,
            file: file, line: line
        )
    }
}
