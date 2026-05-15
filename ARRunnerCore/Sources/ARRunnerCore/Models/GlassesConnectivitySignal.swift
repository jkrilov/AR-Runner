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
}
