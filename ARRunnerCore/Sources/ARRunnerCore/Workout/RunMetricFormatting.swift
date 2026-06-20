// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure, platform-agnostic formatters for the in-run watch display.
/// Lives in Core (not the watch target) so the formatting contract is
/// exercisable from `ARRunnerCoreTests` without a watchOS test host.
/// Helpers are intentionally narrow and unit-tested — this surface has
/// regressed on per-sample distance, missing avg-pace, and divide-by-zero
/// in the past.
public enum RunMetricFormatting {
    /// Meters → statute miles. Matches `HKUnit.mile()` exactly; duplicated
    /// so non-HealthKit callers (tests, iPhone mirror) don't import HK.
    public static let metersPerMile: Double = 1609.344

    /// Meters → kilometers divisor.
    public static let metersPerKilometer: Double = 1000.0

    /// Meters → feet. Matches `HKUnit.foot()`.
    public static let feetPerMeter: Double = 3.280839895013123

    /// Convert meters to miles. No clamping — callers handle 0 / nil.
    public static func miles(fromMeters meters: Double) -> Double {
        meters / metersPerMile
    }

    /// Convert meters to kilometers. No clamping — callers handle 0 / nil.
    public static func kilometers(fromMeters meters: Double) -> Double {
        meters / metersPerKilometer
    }

    /// Convert meters to feet. No clamping.
    public static func feet(fromMeters meters: Double) -> Double {
        meters * feetPerMeter
    }

    // MARK: - Distance

    /// Unit-aware distance, e.g. "2.34 mi" (imperial) or "3.77 km" (metric).
    /// Non-finite inputs return a `--` placeholder; 0 renders as "0.00".
    public static func formatDistance(meters: Double, unitSystem: UnitSystem) -> String {
        switch unitSystem {
        case .imperial:
            guard meters.isFinite else { return "-- mi" }
            return String(format: "%.2f mi", miles(fromMeters: meters))
        case .metric:
            guard meters.isFinite else { return "-- km" }
            return String(format: "%.2f km", kilometers(fromMeters: meters))
        }
    }

    /// "2.34 mi" — two decimal places, suffixed with " mi". Negative inputs
    /// are preserved verbatim so a bug elsewhere surfaces rather than
    /// silently rounding to zero.
    ///
    /// Retained for callers that are still hard-wired to miles; prefer
    /// `formatDistance(meters:unitSystem:)` for unit-aware display.
    public static func formatMiles(meters: Double) -> String {
        String(format: "%.2f mi", miles(fromMeters: meters))
    }

    // MARK: - Pace

    /// Unit-aware average pace: `MM:SS/mi` (imperial) or `MM:SS/km` (metric),
    /// widening to `H:MM:SS` for ultra-slow efforts. Returns the matching
    /// `--:--` placeholder until enough distance has accumulated to produce a
    /// stable pace (guards divide-by-zero and the first-sample spike).
    public static func formatAveragePace(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double,
        unitSystem: UnitSystem
    ) -> String {
        switch unitSystem {
        case .imperial:
            return formatAveragePacePerMile(
                elapsedSeconds: elapsedSeconds,
                distanceMeters: distanceMeters
            )
        case .metric:
            return formatAveragePacePerKilometer(
                elapsedSeconds: elapsedSeconds,
                distanceMeters: distanceMeters
            )
        }
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
        return formatPace(secondsPerUnit: elapsedSeconds / distanceMiles, suffix: "/mi")
            ?? "--:--/mi"
    }

    /// Average pace as `MM:SS/km` (or `H:MM:SS/km`). Threshold is 0.01 km
    /// (~10 m) — same first-sample-spike guard as the per-mile variant.
    public static func formatAveragePacePerKilometer(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double
    ) -> String {
        let distanceKilometers = kilometers(fromMeters: distanceMeters)
        guard elapsedSeconds > 0, distanceKilometers >= 0.01 else {
            return "--:--/km"
        }
        return formatPace(secondsPerUnit: elapsedSeconds / distanceKilometers, suffix: "/km")
            ?? "--:--/km"
    }

    // MARK: - Speed (cycling)

    /// Unit-aware ground speed: "27.4 km/h" (metric) or "17.0 mph" (imperial).
    /// Non-finite or negative inputs return the matching `--` placeholder.
    public static func formatSpeed(metersPerSecond: Double, unitSystem: UnitSystem) -> String {
        switch unitSystem {
        case .metric:
            guard metersPerSecond.isFinite, metersPerSecond >= 0 else { return "-- km/h" }
            return String(format: "%.1f km/h", metersPerSecond * 3.6)
        case .imperial:
            guard metersPerSecond.isFinite, metersPerSecond >= 0 else { return "-- mph" }
            return String(format: "%.1f mph", metersPerSecond * 3600.0 / metersPerMile)
        }
    }

    /// Unit-aware *instantaneous* pace from a seconds-per-kilometre value.
    ///
    /// Distinct from `formatAveragePace(...)`, which derives pace from
    /// cumulative elapsed/distance. This variant formats a pace the caller
    /// already holds in sec/km (e.g. the `.pace` `WorkoutMetric` the glasses
    /// fan-out delivers). Metric renders `MM:SS/km`; imperial converts to
    /// `MM:SS/mi`. Non-finite / non-positive input returns the matching
    /// `--:--` placeholder.
    public static func formatPace(
        secondsPerKilometer: Double,
        unitSystem: UnitSystem
    ) -> String {
        switch unitSystem {
        case .metric:
            return formatPace(secondsPerUnit: secondsPerKilometer, suffix: "/km") ?? "--:--/km"
        case .imperial:
            // sec/km → sec/mi by scaling the per-unit distance.
            let secondsPerMile = secondsPerKilometer * (metersPerMile / metersPerKilometer)
            return formatPace(secondsPerUnit: secondsPerMile, suffix: "/mi") ?? "--:--/mi"
        }
    }

    // MARK: - Elevation

    /// Unit-aware elevation, e.g. "123 m" (metric) or "404 ft" (imperial).
    /// Non-finite inputs return the matching `--` placeholder.
    public static func formatElevation(meters: Double, unitSystem: UnitSystem) -> String {
        switch unitSystem {
        case .metric:
            guard meters.isFinite else { return "-- m" }
            return String(format: "%.0f m", meters)
        case .imperial:
            guard meters.isFinite else { return "-- ft" }
            return String(format: "%.0f ft", feet(fromMeters: meters))
        }
    }

    // MARK: - Heading (compass)

    /// 8-point cardinal abbreviations, indexed clockwise from North.
    private static let cardinalPoints = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// Compass heading as an 8-point cardinal + zero-padded degrees, e.g.
    /// `"NE 045°"`. Unit-system independent (a bearing is the same in metric
    /// and imperial), unlike every other helper here.
    ///
    /// - Normalises `degrees` into `0..<360` (negative inputs wrap up; values
    ///   ≥ 360 wrap down). Non-finite inputs (NaN / ±inf) return the `--`
    ///   placeholder.
    /// - Cardinal index = `Int((normalized + 22.5) / 45) % 8`, so 337.5°…22.5°
    ///   reads `N`, 22.5°…67.5° reads `NE`, and so on.
    /// - Degrees are zero-padded to three digits (`%03d°`) and wrapped at 360
    ///   so `359.6` rounds to `000°` rather than `360°`.
    public static func formatHeading(degrees: Double) -> String {
        guard degrees.isFinite else { return "--" }
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        let cardinal = cardinalPoints[Int((normalized + 22.5) / 45) % 8]
        let wholeDegrees = Int(normalized.rounded()) % 360
        return String(format: "%@ %03d°", cardinal, wholeDegrees)
    }

    // MARK: - Private

    /// Render `secondsPerUnit` as `M:SS` / `H:MM:SS` plus `suffix`. Returns
    /// `nil` for non-finite / non-positive input so callers emit a placeholder.
    private static func formatPace(secondsPerUnit: Double, suffix: String) -> String? {
        guard secondsPerUnit.isFinite, secondsPerUnit > 0 else { return nil }
        let total = Int(secondsPerUnit.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d\(suffix)", h, m, s)
        }
        return String(format: "%d:%02d\(suffix)", m, s)
    }
}
