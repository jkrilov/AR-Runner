// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Locks the v0.6.0 metric-correctness branch in `makeSummary`: cycling
/// reports `averageSpeedMetersPerSecond` and leaves pace nil; running keeps
/// computing pace and leaves speed nil.
final class WorkoutControllerCyclingTests: XCTestCase {

    func testCyclingSummaryReportsSpeedNotPace() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate)

        _ = try await controller.start(activityType: .outdoorBike)
        // 5,000 m over 1,000 s active → 5.0 m/s.
        await substrate.queueResult(
            WorkoutHealthResult(
                healthKitWorkoutID: UUID(),
                endedAt: Date(timeIntervalSince1970: 1_000),
                activeDuration: 1_000,
                totalDistanceMeters: 5_000
            )
        )
        let summary = try await controller.end()

        XCTAssertEqual(summary.sport, .outdoorBike)
        XCTAssertNil(summary.averagePaceSecondsPerKilometer, "cycling must not report pace")
        let speed = try XCTUnwrap(summary.averageSpeedMetersPerSecond)
        XCTAssertEqual(speed, 5.0, accuracy: 1e-9)
    }

    func testRunningSummaryReportsPaceNotSpeed() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate)

        _ = try await controller.start(activityType: .outdoorRun)
        // 2,000 m over 600 s → 300 s/km pace.
        await substrate.queueResult(
            WorkoutHealthResult(
                healthKitWorkoutID: UUID(),
                endedAt: Date(timeIntervalSince1970: 600),
                activeDuration: 600,
                totalDistanceMeters: 2_000
            )
        )
        let summary = try await controller.end()

        XCTAssertNil(summary.averageSpeedMetersPerSecond, "running must not report speed")
        let pace = try XCTUnwrap(summary.averagePaceSecondsPerKilometer)
        XCTAssertEqual(pace, 300.0, accuracy: 1e-9)
    }
}
