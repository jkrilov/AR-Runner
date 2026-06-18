// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Locks the unit-aware formatters added for the v0.6.0 metric/imperial
/// toggle. Covers both systems for pace, speed, distance, and elevation,
/// plus the placeholder guards for 0 / NaN / inf inputs.
final class UnitSystemFormattingTests: XCTestCase {

    // MARK: - Distance

    func testDistanceImperial() {
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 0, unitSystem: .imperial), "0.00 mi")
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 1609.344, unitSystem: .imperial), "1.00 mi")
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 5_000, unitSystem: .imperial), "3.11 mi")
    }

    func testDistanceMetric() {
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 0, unitSystem: .metric), "0.00 km")
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 1_000, unitSystem: .metric), "1.00 km")
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: 5_000, unitSystem: .metric), "5.00 km")
    }

    func testDistancePlaceholderForNonFinite() {
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: .nan, unitSystem: .metric), "-- km")
        XCTAssertEqual(RunMetricFormatting.formatDistance(meters: .infinity, unitSystem: .imperial), "-- mi")
    }

    // MARK: - Pace

    func testPaceImperialMatchesLegacyPerMile() {
        // 1 mile in 9:00.
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: 540, distanceMeters: 1609.344, unitSystem: .imperial),
            "9:00/mi"
        )
    }

    func testPaceMetricPerKilometer() {
        // 1 km in 5:00.
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: 300, distanceMeters: 1_000, unitSystem: .metric),
            "5:00/km"
        )
        // 2 km in 11:30 → 5:45/km.
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: 690, distanceMeters: 2_000, unitSystem: .metric),
            "5:45/km"
        )
    }

    func testPaceMetricWidensToHoursForUltraSlow() {
        let elapsed: TimeInterval = 3600 + 5 * 60 + 4 // 1:05:04
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: elapsed, distanceMeters: 1_000, unitSystem: .metric),
            "1:05:04/km"
        )
    }

    func testPacePlaceholdersGuardDivideByZeroAndSpike() {
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: 0, distanceMeters: 1_000, unitSystem: .metric),
            "--:--/km"
        )
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: 30, distanceMeters: 0, unitSystem: .metric),
            "--:--/km"
        )
        // < 0.01 km (~10 m) first-sample spike.
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: 5, distanceMeters: 5, unitSystem: .metric),
            "--:--/km"
        )
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: .nan, distanceMeters: 1_000, unitSystem: .metric),
            "--:--/km"
        )
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePace(elapsedSeconds: .infinity, distanceMeters: 1609.344, unitSystem: .imperial),
            "--:--/mi"
        )
    }

    // MARK: - Speed (cycling)

    func testSpeedMetric() {
        // 10 m/s = 36.0 km/h.
        XCTAssertEqual(RunMetricFormatting.formatSpeed(metersPerSecond: 10, unitSystem: .metric), "36.0 km/h")
        XCTAssertEqual(RunMetricFormatting.formatSpeed(metersPerSecond: 0, unitSystem: .metric), "0.0 km/h")
    }

    func testSpeedImperial() {
        // 10 m/s = 22.369 mph → 22.4 mph.
        XCTAssertEqual(RunMetricFormatting.formatSpeed(metersPerSecond: 10, unitSystem: .imperial), "22.4 mph")
    }

    func testSpeedPlaceholders() {
        XCTAssertEqual(RunMetricFormatting.formatSpeed(metersPerSecond: .nan, unitSystem: .metric), "-- km/h")
        XCTAssertEqual(RunMetricFormatting.formatSpeed(metersPerSecond: .infinity, unitSystem: .imperial), "-- mph")
        XCTAssertEqual(RunMetricFormatting.formatSpeed(metersPerSecond: -3, unitSystem: .metric), "-- km/h")
    }

    // MARK: - Elevation

    func testElevationMetric() {
        XCTAssertEqual(RunMetricFormatting.formatElevation(meters: 123, unitSystem: .metric), "123 m")
        XCTAssertEqual(RunMetricFormatting.formatElevation(meters: 0, unitSystem: .metric), "0 m")
    }

    func testElevationImperial() {
        // 123 m ≈ 403.5 ft → 404 ft (round half to even / away — %.0f rounds 403.54 → 404).
        XCTAssertEqual(RunMetricFormatting.formatElevation(meters: 123, unitSystem: .imperial), "404 ft")
    }

    func testElevationPlaceholders() {
        XCTAssertEqual(RunMetricFormatting.formatElevation(meters: .nan, unitSystem: .metric), "-- m")
        XCTAssertEqual(RunMetricFormatting.formatElevation(meters: .infinity, unitSystem: .imperial), "-- ft")
    }
}
