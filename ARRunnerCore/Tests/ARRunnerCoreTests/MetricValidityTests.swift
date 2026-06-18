// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

/// Locks the per-workout-type metric validity matrix and unit-label rules
/// (`MetricKind.isValid(for:)` / `.unitLabel(for:in:)`, v0.6.0). These guard
/// the domain invariants that have historically been wrong on cycling:
/// pace-vs-speed, indoor elevation noise, indoor-bike distance, and the
/// cadence unit (rpm vs spm).
final class MetricValidityTests: XCTestCase {

    // MARK: - Pace vs speed (the cycling correctness blocker)

    func testPaceInvalidForCyclingValidForRunWalk() {
        XCTAssertFalse(MetricKind.pace.isValid(for: .outdoorBike), "cycling must use speed, not pace")
        XCTAssertFalse(MetricKind.pace.isValid(for: .indoorBike))
        XCTAssertTrue(MetricKind.pace.isValid(for: .outdoorRun))
        XCTAssertTrue(MetricKind.pace.isValid(for: .indoorRun))
        XCTAssertTrue(MetricKind.pace.isValid(for: .outdoorWalk))
        XCTAssertTrue(MetricKind.pace.isValid(for: .indoorWalk))
    }

    func testSpeedValidForCyclingOnly() {
        XCTAssertTrue(MetricKind.speed.isValid(for: .outdoorBike), "speed is the cycling primary")
        XCTAssertTrue(MetricKind.speed.isValid(for: .indoorBike))
        XCTAssertFalse(MetricKind.speed.isValid(for: .outdoorRun))
        XCTAssertFalse(MetricKind.speed.isValid(for: .indoorWalk))
    }

    func testPaceAndSpeedAreMutuallyExclusivePerType() {
        // Exactly one of pace/speed is valid for any supported workout type —
        // never both, never neither.
        for type in WorkoutType.allCases {
            XCTAssertNotEqual(
                MetricKind.pace.isValid(for: type),
                MetricKind.speed.isValid(for: type),
                "pace and speed must be mutually exclusive for \(type.rawValue)"
            )
        }
    }

    // MARK: - Elevation: outdoor-only

    func testElevationInvalidIndoorsValidOutdoors() {
        XCTAssertTrue(MetricKind.elevation.isValid(for: .outdoorRun))
        XCTAssertTrue(MetricKind.elevation.isValid(for: .outdoorBike))
        XCTAssertTrue(MetricKind.elevation.isValid(for: .outdoorWalk))
        XCTAssertFalse(MetricKind.elevation.isValid(for: .indoorRun), "indoor barometric gain is noise")
        XCTAssertFalse(MetricKind.elevation.isValid(for: .indoorBike))
        XCTAssertFalse(MetricKind.elevation.isValid(for: .indoorWalk))
    }

    // MARK: - Distance: absent on a stationary bike

    func testDistanceInvalidForIndoorBikeOnly() {
        XCTAssertFalse(
            MetricKind.distance.isValid(for: .indoorBike),
            "stationary bike has no GPS or wheel sensor in Core"
        )
        // Treadmill run/walk still report distance.
        XCTAssertTrue(MetricKind.distance.isValid(for: .indoorRun))
        XCTAssertTrue(MetricKind.distance.isValid(for: .indoorWalk))
        XCTAssertTrue(MetricKind.distance.isValid(for: .outdoorBike))
        XCTAssertTrue(MetricKind.distance.isValid(for: .outdoorRun))
    }

    // MARK: - Universally valid metrics

    func testUniversalMetricsValidForEveryType() {
        for kind in [MetricKind.heartRate, .duration, .energy, .cadence] {
            for type in WorkoutType.allCases {
                XCTAssertTrue(
                    kind.isValid(for: type),
                    "\(kind.rawValue) should be valid for \(type.rawValue)"
                )
            }
        }
    }

    /// The shipped per-type HUD defaults must only ever contain metrics that
    /// are valid for that type — this ties the two contracts together so a
    /// future default edit can't sneak in an invalid metric.
    func testEveryDefaultLayoutSlotIsValidForItsType() {
        for type in WorkoutType.allCases {
            for slot in HUDLayout.default(for: type).slots {
                guard let metric = slot else { continue }
                XCTAssertTrue(
                    metric.isValid(for: type),
                    "default \(type.rawValue) layout has invalid metric \(metric.rawValue)"
                )
            }
        }
    }

    // MARK: - Unit labels

    func testCadenceUnitIsRpmForCyclingSpmOtherwise() {
        XCTAssertEqual(MetricKind.cadence.unitLabel(for: .outdoorBike, in: .metric), "rpm")
        XCTAssertEqual(MetricKind.cadence.unitLabel(for: .indoorBike, in: .imperial), "rpm")
        XCTAssertEqual(MetricKind.cadence.unitLabel(for: .outdoorRun, in: .metric), "spm")
        XCTAssertEqual(MetricKind.cadence.unitLabel(for: .indoorWalk, in: .imperial), "spm")
    }

    func testDistancePaceSpeedElevationLabelsTrackUnitSystem() {
        let run = WorkoutType.outdoorRun
        let bike = WorkoutType.outdoorBike
        XCTAssertEqual(MetricKind.distance.unitLabel(for: run, in: .metric), "km")
        XCTAssertEqual(MetricKind.distance.unitLabel(for: run, in: .imperial), "mi")
        XCTAssertEqual(MetricKind.pace.unitLabel(for: run, in: .metric), "/km")
        XCTAssertEqual(MetricKind.pace.unitLabel(for: run, in: .imperial), "/mi")
        XCTAssertEqual(MetricKind.speed.unitLabel(for: bike, in: .metric), "km/h")
        XCTAssertEqual(MetricKind.speed.unitLabel(for: bike, in: .imperial), "mph")
        XCTAssertEqual(MetricKind.elevation.unitLabel(for: run, in: .metric), "m")
        XCTAssertEqual(MetricKind.elevation.unitLabel(for: run, in: .imperial), "ft")
    }

    func testFixedLabelsIgnoreUnitSystem() {
        for system in UnitSystem.allCases {
            XCTAssertEqual(MetricKind.heartRate.unitLabel(for: .outdoorRun, in: system), "bpm")
            XCTAssertEqual(MetricKind.energy.unitLabel(for: .outdoorRun, in: system), "kcal")
            XCTAssertEqual(MetricKind.duration.unitLabel(for: .outdoorRun, in: system), "")
        }
    }
}
