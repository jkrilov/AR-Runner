// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Boundary-input hardening for `RunMetricFormatting`, complementing
/// `RunMetricFormattingTests` (happy path) and `UnitSystemFormattingTests`
/// (per-system + NaN/inf placeholders). Focus here: very-large, tiny, and
/// negative inputs across both unit systems — the values a flaky GPS / HR
/// stream actually emits — confirming we render a string and never trap.
final class FormatterEdgeCaseTests: XCTestCase {

    // MARK: - Distance extremes

    func testDistanceVeryLargeDoesNotCrash() {
        // 1,000 km ultra. Two-decimal contract holds, no overflow/format trap.
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 1_000_000, unitSystem: .metric), "1000.00 km")
        let imperial = RunMetricFormatting.formatDistance(meters: 1_000_000, unitSystem: .imperial)
        XCTAssertTrue(imperial.hasSuffix(" mi"))
        XCTAssertFalse(imperial.contains("nan"))
    }

    func testDistanceNegativeIsPreservedNotZeroed() {
        // A negative cumulative distance signals a bug upstream; surface it
        // (don't silently clamp to 0.00) so it's caught, not hidden.
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: -1609.344, unitSystem: .imperial), "-1.00 mi")
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: -1000, unitSystem: .metric), "-1.00 km")
    }

    func testDistanceTinyRoundsToZeroWithUnit() {
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 0.4, unitSystem: .metric), "0.00 km")
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 0.4, unitSystem: .imperial), "0.00 mi")
    }

    // MARK: - Speed extremes

    func testSpeedVeryLargeAndTinyPositive() {
        // Downhill sprint / sensor spike: 50 m/s = 180 km/h. No placeholder.
        XCTAssertEqual(RunMetricFormatting.formatSpeed(metersPerSecond: 50, unitSystem: .metric), "180.0 km/h")
        // Tiny positive is a real (slow) value, not a placeholder.
        XCTAssertEqual(RunMetricFormatting.formatSpeed(metersPerSecond: 0.05, unitSystem: .metric), "0.2 km/h")
    }

    func testSpeedNegativeZeroFormatsNotPlaceholder() {
        // -0.0 is finite and >= 0, so it takes the format path, not the
        // "-- mph" placeholder. printf preserves the sign bit, so the literal
        // output is "-0.0 mph" — documented here so a future "tidy the sign"
        // change is a conscious decision, not a silent regression.
        let result = RunMetricFormatting.formatSpeed(metersPerSecond: -0.0, unitSystem: .imperial)
        XCTAssertEqual(result, "-0.0 mph")
        XCTAssertNotEqual(result, "-- mph")
    }

    // MARK: - Pace extremes

    func testPaceVeryFastFromLargeDistance() {
        // 10 km in 30:00 → 3:00/km. Large distance, fast pace, no widening.
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: 1800, distanceMeters: 10_000, unitSystem: .metric),
            "3:00/km"
        )
    }

    func testPaceUltraSlowWidensToHoursBothSystems() {
        // 1 unit in 2h+ — both systems must widen to H:MM:SS, never overflow.
        let elapsed: TimeInterval = 2 * 3600 + 13 * 60 + 9
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: elapsed, distanceMeters: 1_000, unitSystem: .metric),
            "2:13:09/km"
        )
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: elapsed, distanceMeters: 1609.344, unitSystem: .imperial),
            "2:13:09/mi"
        )
    }

    func testPaceNegativeElapsedPlaceholders() {
        // A negative elapsed is nonsensical (clock skew) — placeholder, not a
        // negative "pace".
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: -60, distanceMeters: 1_000, unitSystem: .metric),
            "--:--/km"
        )
    }

    func testPaceHugeDistanceDoesNotTrap() {
        let result = RunMetricFormatting.formatAveragePace(
            elapsedSeconds: 3600,
            distanceMeters: 1_000_000,
            unitSystem: .metric
        )
        XCTAssertTrue(result.hasSuffix("/km"))
        XCTAssertFalse(result.contains("nan"))
    }

    // MARK: - Elevation extremes

    func testElevationNegativeNetDescent() {
        // Net downhill point-to-point — a real value, preserved with sign.
        XCTAssertEqual(RunMetricFormatting.formatElevation(meters: -85, unitSystem: .metric), "-85 m")
        XCTAssertEqual(RunMetricFormatting.formatElevation(meters: -85, unitSystem: .imperial), "-279 ft")
    }

    func testElevationVeryLargeMountain() {
        XCTAssertEqual(RunMetricFormatting.formatElevation(meters: 8848, unitSystem: .metric), "8848 m")
        let ft = RunMetricFormatting.formatElevation(meters: 8848, unitSystem: .imperial)
        XCTAssertTrue(ft.hasSuffix(" ft"))
        XCTAssertFalse(ft.contains("nan"))
    }
}
