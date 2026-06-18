// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User-selected measurement system for the in-run display and post-run
/// summaries. Pure Core type (no `Locale` / `Measurement` framework coupling)
/// so it crosses the Linux test boundary and the WCSession wire unchanged.
///
/// The phone owns the UI + App-Group persistence (Laughlin, later); Core owns
/// this type and the unit-aware formatters in `RunMetricFormatting`.
public enum UnitSystem: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    /// Kilometres, metres, min/km, km/h.
    case metric
    /// Statute miles, feet, min/mi, mph.
    case imperial
}
