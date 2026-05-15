// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One-way input from the glasses transport into the workout controller.
///
/// Per D4 the workout never pauses on glasses disconnect — the controller
/// merely tracks the signal for telemetry (drop count → side store) and
/// surfaces an "HUD offline" hint via `WorkoutState.glassesConnected`.
public enum GlassesConnectivitySignal: Sendable, Equatable {
    case connected
    case disconnected(reason: String?)

    /// Bridge from Weiss's canonical `GlassesConnectionState` (the full
    /// transport-level lifecycle) to the minimal subset the workout cares
    /// about per D4. Anything other than `.connected` is treated as
    /// "HUD offline" — the workout keeps running regardless.
    public static func from(_ state: GlassesConnectionState) -> GlassesConnectivitySignal {
        switch state {
        case .connected:
            return .connected
        case .disconnected, .scanning, .connecting, .reconnecting, .failed:
            return .disconnected(reason: state.rawValue)
        }
    }

    /// Bridge from a side-channel `GlassesStatusEvent.dropped(reason:)` —
    /// useful when the caller has a richer drop reason than the bare
    /// connection-state transition can carry.
    public static func from(droppedReason reason: GlassesDisconnectReason) -> GlassesConnectivitySignal {
        let label: String
        switch reason {
        case .userInitiated: label = "userInitiated"
        case .linkLoss: label = "linkLoss"
        case .peerPoweredOff: label = "peerPoweredOff"
        case .hostUnavailable: label = "hostUnavailable"
        case .unknown(let code): label = "unknown(\(code))"
        }
        return .disconnected(reason: label)
    }
}
