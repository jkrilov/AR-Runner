// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Locks the WCMessage v5 → v6 migration: schema bump, new settings-sync
/// cases, the legacy `sport:"running"` decode path, the non-fatal unknown
/// workout-type fallback, and the lenient unknown-`kind` decode.
final class WCMessageV6Tests: XCTestCase {

    func testSchemaVersionIsSix() {
        XCTAssertEqual(WCMessage.currentSchemaVersion, 6)
    }

    // MARK: - New v6 cases round-trip

    func testDefaultWorkoutTypeRoundTrip() throws {
        for type in WorkoutType.allCases {
            let original = WCMessage.defaultWorkoutType(type)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(WCMessage.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }

    func testUnitPreferenceRoundTrip() throws {
        for system in UnitSystem.allCases {
            let original = WCMessage.unitPreference(system)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(WCMessage.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }

    // MARK: - Backward compat: a v5 (v0.5.20) peer's payloads still decode

    func testV5SnapshotWithLegacySportStringDecodesOnV6() throws {
        let v5JSON = """
        {
          "schemaVersion": 5,
          "kind": "workoutSnapshot",
          "snapshot": {
            "sessionID": "00000000-0000-0000-0000-0000000000ab",
            "sport": "running",
            "phase": "running",
            "timestamp": 1700000000,
            "startedAt": 1699999688,
            "elapsedSeconds": 312,
            "heartRateBeatsPerMinute": 156,
            "distanceMeters": 980,
            "paceSecondsPerKilometer": 320,
            "estimatedActiveKilocalories": 47.5,
            "glassesConnected": true,
            "latitude": 47.6,
            "longitude": -122.3
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WCMessage.self, from: v5JSON)
        guard case .workoutSnapshot(let snap) = decoded else {
            XCTFail("expected workoutSnapshot, got \(decoded)"); return
        }
        XCTAssertEqual(snap.sport, .outdoorRun, "legacy sport:\"running\" must map to outdoor run")
    }

    func testLegacyLifecycleStartedRunningDecodesToOutdoorRun() throws {
        let json = """
        {
          "schemaVersion": 5,
          "kind": "workoutLifecycle",
          "lifecycleEvent": { "started": { "_0": "running" } }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WCMessage.self, from: json)
        XCTAssertEqual(decoded, .workoutLifecycle(.started(.outdoorRun)))
    }

    // MARK: - Non-fatal fallbacks

    func testUnknownSportDecodesToFallbackNotFatal() throws {
        let json = """
        {
          "schemaVersion": 6,
          "kind": "defaultWorkoutType",
          "workoutType": "jetpacking"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WCMessage.self, from: json)
        XCTAssertEqual(decoded, .defaultWorkoutType(.fallback))
    }

    func testUnknownKindDecodesToUnknownNotFatal() throws {
        let json = """
        { "schemaVersion": 6, "kind": "someFutureCase", "futurePayload": 42 }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WCMessage.self, from: json)
        XCTAssertEqual(decoded, .unknown)
    }

    func testUnknownRoundTripsToUnknown() throws {
        let data = try JSONEncoder().encode(WCMessage.unknown)
        let decoded = try JSONDecoder().decode(WCMessage.self, from: data)
        XCTAssertEqual(decoded, .unknown)
    }

    // MARK: - Hard incompatibility still throws

    func testUnsupportedFutureSchemaStillThrows() {
        let json = """
        { "schemaVersion": 99, "kind": "workoutSnapshot" }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(WCMessage.self, from: json)) { error in
            XCTAssertEqual(error as? WCMessageCodingError, .unsupportedSchemaVersion(99))
        }
    }
}
