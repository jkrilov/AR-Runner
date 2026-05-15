// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Connection lifecycle for the glasses link.
///
/// Per D4, the workout never depends on this being `.connected`: callers
/// should treat anything other than `.connected` as "HUD offline" and keep
/// the workout running.
public enum GlassesConnectionState: String, Sendable, Codable, CaseIterable, Equatable {
    /// No link, no scan in progress.
    case disconnected
    /// Actively scanning for a peripheral matching the ActiveLook service UUID.
    case scanning
    /// Peripheral discovered; GATT connect / service discovery in flight.
    case connecting
    /// Fully ready: services discovered, characteristics subscribed, ready to write.
    case connected
    /// Link was lost mid-session; auto-reconnect is in progress (per D4).
    case reconnecting
    /// Terminal failure for this attempt; caller may invoke `connect()` again.
    case failed
}
