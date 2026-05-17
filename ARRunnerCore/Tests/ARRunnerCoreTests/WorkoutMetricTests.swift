// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class WorkoutMetricTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = WorkoutMetric(kind: .pace, value: 312.4, unit: "s/km", timestamp: Date(timeIntervalSinceReferenceDate: 42))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutMetric.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testEnergyKindExistsAndRoundTrips() throws {
        // v0.2 audit P1.3 prereq: HealthKit's activeEnergyBurned needs a
        // dedicated MetricKind so the live "flame" reading isn't silently
        // coerced into .duration. Lock the contract here so the HK adapter
        // (Laughlin, Phase B) has a stable target case to emit.
        XCTAssertTrue(MetricKind.allCases.contains(.energy))

        let original = WorkoutMetric(
            kind: .energy,
            value: 142.5,
            unit: "kcal",
            timestamp: Date(timeIntervalSinceReferenceDate: 1_234)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutMetric.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.kind, .energy)
        XCTAssertEqual(decoded.unit, "kcal")
    }

    func testMetricKindRawValueStable() throws {
        // Lock the raw values — they participate in WCMessage / JSON
        // payloads, so a rename of .energy to e.g. "kcal" would silently
        // break watch↔phone decode on already-shipped builds.
        XCTAssertEqual(MetricKind.energy.rawValue, "energy")
    }
}
