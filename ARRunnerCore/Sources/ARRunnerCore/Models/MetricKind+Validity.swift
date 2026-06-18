// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Per-workout-type metric validity + unit-label rules (v0.6.0).
///
/// The orthogonal `WorkoutType` model means a metric that is meaningful for
/// one activity/environment is noise for another: cycling surfaces *speed*
/// rather than *pace*, indoor variants have no barometric *elevation*, and a
/// stationary bike reports no GPS/wheel *distance* without an external sensor.
/// Centralising the matrix here keeps the HUD layout editor, the watch render
/// path, and the phone mirror from each re-deriving (and disagreeing on) the
/// rules — and it is pure Swift so it stays exercisable from the Linux
/// `ARRunnerCoreTests` suite.
///
/// This is intentionally framework-free domain logic (no HealthKit / Locale).
extension MetricKind {

    /// Whether this metric is meaningful to display for the given workout
    /// type. Used to gate the layout editor (don't let a user assign `.pace`
    /// to a bike) and to decide whether a live sample is rendered or dropped.
    ///
    /// Rules (locked with the v0.6.0 per-type HUD defaults, see
    /// `HUDLayout.default(for:)`):
    /// - `.pace` is valid for running/walking only — cycling uses `.speed`.
    /// - `.speed` is valid for cycling only — run/walk use `.pace`.
    /// - `.elevation` is outdoor-only (indoor barometric gain is noise).
    /// - `.distance` is unavailable on an indoor bike (no GPS, no wheel
    ///   sensor in Core); treadmill run/walk still report distance.
    /// - `.heartRate`, `.duration`, `.energy`, `.cadence` are valid for all
    ///   (cadence semantics differ by unit — see `unitLabel(for:in:)`).
    public func isValid(for type: WorkoutType) -> Bool {
        switch self {
        case .heartRate, .duration, .energy, .cadence:
            return true
        case .pace:
            return type.activity != .cycling
        case .speed:
            return type.activity == .cycling
        case .elevation:
            return type.environment == .outdoor
        case .distance:
            // Indoor cycling has neither GPS nor a wheel-speed sensor in Core,
            // so distance is not derivable; every other combination has it.
            return !(type.activity == .cycling && type.environment == .indoor)
        }
    }

    /// The unit label to suffix this metric with for the given workout type
    /// and measurement system, e.g. `"km/h"`, `"/mi"`, `"rpm"`.
    ///
    /// `.cadence` is the only metric whose label depends on the *activity*:
    /// cycling reads in revolutions-per-minute (`"rpm"`) while running and
    /// walking read in steps-per-minute (`"spm"`). The distance/pace/speed/
    /// elevation labels depend only on the `UnitSystem`. `.duration` carries
    /// no unit suffix (it is rendered as a `H:MM:SS` clock).
    public func unitLabel(for type: WorkoutType, in system: UnitSystem) -> String {
        switch self {
        case .heartRate:
            return "bpm"
        case .energy:
            return "kcal"
        case .duration:
            return ""
        case .cadence:
            return type.activity == .cycling ? "rpm" : "spm"
        case .distance:
            return system == .metric ? "km" : "mi"
        case .pace:
            return system == .metric ? "/km" : "/mi"
        case .speed:
            return system == .metric ? "km/h" : "mph"
        case .elevation:
            return system == .metric ? "m" : "ft"
        }
    }
}
