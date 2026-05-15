// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Reason a glasses link dropped. Mirrors the subset of CoreBluetooth disconnect
/// reasons we care about, but lives in Core so it is Linux-buildable and easy
/// to mock.
public enum GlassesDisconnectReason: Sendable, Equatable, Codable {
    /// `disconnect()` was called by the host app or workout shutdown.
    case userInitiated
    /// Radio link loss (out of range, glasses powered off, interference).
    case linkLoss
    /// Peer powered off or rebooted.
    case peerPoweredOff
    /// Host Bluetooth subsystem was disabled (airplane mode, BT toggle).
    case hostUnavailable
    /// Anything else; carries the underlying numeric error code if available.
    case unknown(code: Int)
}

/// Side-channel events the transport surfaces alongside (not in place of)
/// the connection-state stream. Used by the run-metadata side store (D9)
/// and the watch UI's "HUD offline" indicator (D4).
public enum GlassesStatusEvent: Sendable, Equatable {
    /// Battery level reported by the glasses Battery Service (0–100).
    case batteryLevel(Int)
    /// Signal quality — RSSI in dBm (typically -90 ... -30). `nil` if unknown.
    case signalQuality(Int)
    /// The link dropped. Workout MUST continue (D4).
    case dropped(reason: GlassesDisconnectReason, at: Date)
    /// Auto-reconnect succeeded. `gap` is wall-clock time the HUD was offline.
    case reconnected(gap: TimeInterval, at: Date)
    /// A reconnect attempt failed; transport will retry per backoff policy.
    case reconnectAttemptFailed(attempt: Int, nextDelay: TimeInterval)
}
