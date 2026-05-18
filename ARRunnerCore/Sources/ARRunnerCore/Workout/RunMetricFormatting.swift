// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure, platform-agnostic formatters for the in-run watch display.
/// Lives in Core (not in the watch target) so the formatting contract
/// is exercisable from `ARRunnerCoreTests` without a watchOS test host
/// — Joe's v0.2.0 device feedback regressed twice on the same surface
/// (per-sample distance, missing avg-pace, divide-by-zero), so the
/// helpers are intentionally narrow and unit-tested.
public enum RunMetricFormatting {
    /// Meters → statute miles. Apple's `HKUnit.mile()` uses the same
    /// constant; duplicated here so non-HealthKit callers (tests, the
    /// iPhone mirror view) don't need to import HealthKit.
    public static let metersPerMile: Double = 1609.344

    /// Convert meters to miles. No clamping — callers handle 0 / nil.
    public static func miles(fromMeters meters: Double) -> Double {
        meters / metersPerMile
    }

    /// "2.34 mi" — two decimal places, suffixed with " mi". Matches
    /// Joe's device-test ask (v0.2.0 feedback). Negative inputs are
    /// preserved verbatim so a bug elsewhere surfaces rather than
    /// silently rounding to zero.
    public static func formatMiles(meters: Double) -> String {
        String(format: "%.2f mi", miles(fromMeters: meters))
    }

    /// Average pace as `MM:SS/mi` (or `H:MM:SS/mi` for ultra-slow walks).
    /// Returns the placeholder `--:--/mi` when the run has not yet
    /// accumulated enough distance to produce a stable pace — guards
    /// against divide-by-zero (run just started) and the runaway
    /// first-sample spike (e.g. 1m in 30s → 13:24/mi, useless noise).
    ///
    /// Threshold is 0.01 mi (~16 m); below that the display stays in
    /// placeholder mode rather than flashing a wildly varying number.
    public static func formatAveragePacePerMile(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double
    ) -> String {
        let distanceMiles = miles(fromMeters: distanceMeters)
        guard elapsedSeconds > 0, distanceMiles >= 0.01 else {
            return "--:--/mi"
        }
        let secondsPerMile = elapsedSeconds / distanceMiles
        guard secondsPerMile.isFinite, secondsPerMile > 0 else {
            return "--:--/mi"
        }
        let total = Int(secondsPerMile.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d/mi", h, m, s)
        }
        return String(format: "%d:%02d/mi", m, s)
    }
}
