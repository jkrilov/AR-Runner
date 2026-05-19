// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Phone-side glasses battery indicator helper (v0.4-rc1).
///
/// The watch forwards a 0–100 percentage from the glasses' standard
/// Battery Service (0x180F / 0x2A19) via WCSession `transferUserInfo`.
/// Phone-optional: when no value has arrived yet the helpers fall back to
/// a neutral "unknown" presentation so the UI never asserts a fake state.
enum GlassesBatteryIcon {
    /// SF Symbol best matching the given percent. Returns the unknown
    /// glyph when `level` is nil (no notification has arrived yet).
    static func symbol(for level: Int?) -> String {
        guard let level else { return "battery.0percent" }
        switch max(0, min(100, level)) {
        case 88...:  return "battery.100percent"
        case 63...:  return "battery.75percent"
        case 38...:  return "battery.50percent"
        case 13...:  return "battery.25percent"
        default:     return "battery.0percent"
        }
    }

    /// Tint colour for the battery icon. Red ≤ 15 %, orange ≤ 30 %, green
    /// otherwise; secondary while still unknown.
    static func tint(for level: Int?) -> Color {
        guard let level else { return .secondary }
        switch level {
        case ...15: return .red
        case ...30: return .orange
        default:    return .green
        }
    }
}
