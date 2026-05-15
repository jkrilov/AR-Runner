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
}

/// Curated layout-ID → on-device numeric slot resolver. Values are
/// **placeholders** for v0.1: the real numbers come out of the layout BUILD
/// step (deferred per task scope). Centralised here so the adapter and tests
/// agree on the mapping.
public enum CuratedLayoutCatalog {
    public static let mapping: [String: UInt8] = [
        "minimal-run":   0x01,
        "balanced-run":  0x02,
        "telemetry-run": 0x03
    ]

    public static func deviceID(for layoutID: String) -> UInt8? {
        mapping[layoutID]
    }
}
