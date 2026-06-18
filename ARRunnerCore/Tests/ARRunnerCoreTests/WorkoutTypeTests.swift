// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Locks the orthogonal workout-type model: legacy-string stability for the
/// three outdoor variants (the wire/side-store backward-compat guarantee),
/// the indoor/GPS conveniences, and the non-throwing unknown-rawValue
/// fallback that keeps a bad field from fataling a whole WCMessage decode.
final class WorkoutTypeTests: XCTestCase {

    // MARK: - Codable round-trips

    func testAllCombinationsRoundTrip() throws {
        for type in WorkoutType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(WorkoutType.self, from: data)
            XCTAssertEqual(decoded, type, "round-trip failed for \(type.rawValue)")
        }
        XCTAssertEqual(WorkoutType.allCases.count, 6)
    }

    /// The shipped wire/side-store contract: outdoor run/walk/cycle MUST keep
    /// encoding as exactly "running"/"walking"/"cycling" so v0.5.20 data and
    /// peers keep decoding unchanged.
    func testLegacyOutdoorRawStringsAreStable() throws {
        let cases: [(WorkoutType, String)] = [
            (.outdoorRun, "running"),
            (.outdoorWalk, "walking"),
            (.outdoorBike, "cycling"),
        ]
        for (type, expected) in cases {
            let json = String(data: try JSONEncoder().encode(type), encoding: .utf8)
            XCTAssertEqual(json, "\"\(expected)\"")
            // And the legacy string decodes back to the outdoor variant.
            let decoded = try JSONDecoder().decode(
                WorkoutType.self,
                from: Data("\"\(expected)\"".utf8)
            )
            XCTAssertEqual(decoded, type)
        }
    }

    func testIndoorRawStringsAreStableAndDistinct() throws {
        let cases: [(WorkoutType, String)] = [
            (.indoorRun, "indoor_running"),
            (.indoorWalk, "indoor_walking"),
            (.indoorBike, "indoor_cycling"),
        ]
        for (type, expected) in cases {
            XCTAssertEqual(type.rawValue, expected)
            XCTAssertEqual(WorkoutType(rawValue: expected), type)
        }
    }

    // MARK: - Conveniences

    func testIsIndoorAndUsesGPS() {
        XCTAssertFalse(WorkoutType.outdoorRun.isIndoor)
        XCTAssertTrue(WorkoutType.outdoorRun.usesGPS)
        XCTAssertFalse(WorkoutType.outdoorBike.isIndoor)
        XCTAssertTrue(WorkoutType.outdoorBike.usesGPS, "outdoor cycling records a GPS route")

        XCTAssertTrue(WorkoutType.indoorRun.isIndoor)
        XCTAssertFalse(WorkoutType.indoorRun.usesGPS)
        XCTAssertTrue(WorkoutType.indoorBike.isIndoor)
        XCTAssertFalse(WorkoutType.indoorBike.usesGPS)
    }

    func testBaseActivityAndDisplayName() {
        XCTAssertEqual(WorkoutType.indoorBike.baseActivity, .cycling)
        XCTAssertEqual(WorkoutType.outdoorRun.displayName, "Outdoor Run")
        XCTAssertEqual(WorkoutType.indoorWalk.displayName, "Indoor Walk")
        XCTAssertEqual(WorkoutType.outdoorBike.displayName, "Outdoor Bike")
    }

    // MARK: - Unknown-value fallback (non-throwing)

    func testUnknownRawValueDecodesToFallbackWithoutThrowing() throws {
        let unknown = Data("\"jetpacking\"".utf8)
        let decoded = try JSONDecoder().decode(WorkoutType.self, from: unknown)
        XCTAssertEqual(decoded, .fallback)
        XCTAssertEqual(decoded, .outdoorRun)
    }

    func testInitRawValueRejectsUnknown() {
        XCTAssertNil(WorkoutType(rawValue: "jetpacking"))
    }
}
