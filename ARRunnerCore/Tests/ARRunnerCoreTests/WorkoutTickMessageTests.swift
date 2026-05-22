// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class WorkoutTickMessageTests: XCTestCase {
    func testCodableRoundTripInsideWCMessage() throws {
        let snapshot = WorkoutTickMessage(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-0000000000ab")!,
            sport: .running,
            phase: .running,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000 - 312),
            elapsedSeconds: 312,
            heartRateBeatsPerMinute: 156,
            distanceMeters: 980,
            paceSecondsPerKilometer: 320,
            estimatedActiveKilocalories: 47.5,
            glassesConnected: true
        )
        let original = WCMessage.workoutSnapshot(snapshot)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WCMessage.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, WCMessage.currentSchemaVersion)
        if case .workoutSnapshot(let snap) = decoded {
            XCTAssertEqual(snap.startedAt, snapshot.startedAt)
        } else {
            XCTFail("expected .workoutSnapshot, got \(decoded)")
        }
    }

    /// rc2 — WC schema bumped 3 → 4 to flag the additive
    /// `WorkoutTickMessage.startedAt` field for the phone-side "Started"
    /// row. v0.5.16 — bumped 4 → 5 to flag the additive
    /// `WorkoutTickMessage.latitude` / `.longitude` fields for the
    /// phone-side live route map. Pin the literal version so a regression
    /// knocking it back trips CI.
    func testCurrentSchemaVersionIsFive_v0_5_16() {
        XCTAssertEqual(WCMessage.currentSchemaVersion, 5)
    }

    /// v0.5.16 — a v4 snapshot from an older watch build (no lat/lon)
    /// must still decode on a v5 phone. The phone simply shows no map
    /// until lat/lon start arriving.
    func testV4SnapshotWithoutLatLonStillDecodesOnV5() throws {
        let v4JSON = """
        {
          "schemaVersion": 4,
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
            "glassesConnected": true
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WCMessage.self, from: v4JSON)
        guard case .workoutSnapshot(let snap) = decoded else {
            XCTFail("expected workoutSnapshot, got \(decoded)"); return
        }
        XCTAssertNil(snap.latitude)
        XCTAssertNil(snap.longitude)
        XCTAssertEqual(snap.elapsedSeconds, 312)
    }

    /// v0.5.16 — rc2 placeholder kept for archaeology. Schema version is
    /// pinned by `testCurrentSchemaVersionIsFive_v0_5_16` above.
    func testCurrentSchemaVersionIsFour_rc2() {
        // Intentionally relaxed — the literal `4` pin moved to the v5 test
        // above. Leaving the method name so blame on the rc2 commit still
        // resolves to the introduction of the per-version pinning pattern.
        XCTAssertGreaterThanOrEqual(WCMessage.currentSchemaVersion, 4)
    }

    /// rc2 — a v3 snapshot from an older watch build (no `startedAt`)
    /// must still decode on a v4 phone. The phone falls back to
    /// `timestamp − elapsedSeconds` for display when `startedAt` is nil.
    func testV3SnapshotWithoutStartedAtStillDecodesOnV4() throws {
        let v3JSON = """
        {
          "schemaVersion": 3,
          "kind": "workoutSnapshot",
          "snapshot": {
            "sessionID": "00000000-0000-0000-0000-0000000000ab",
            "sport": "running",
            "phase": "running",
            "timestamp": 1700000000,
            "elapsedSeconds": 312,
            "heartRateBeatsPerMinute": 156,
            "distanceMeters": 980,
            "paceSecondsPerKilometer": 320,
            "estimatedActiveKilocalories": 47.5,
            "glassesConnected": true
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WCMessage.self, from: v3JSON)
        guard case .workoutSnapshot(let snap) = decoded else {
            XCTFail("expected workoutSnapshot, got \(decoded)"); return
        }
        XCTAssertNil(snap.startedAt, "v3 snapshots have no startedAt — phone must fall back")
        XCTAssertEqual(snap.elapsedSeconds, 312)
    }

    func testV1MessagesStillDecodeAfterSchemaBump() throws {
        // Synthesize a v1 envelope by hand to verify backward-compat. v1
        // peers (older watch builds) must keep working against the v0.2
        // phone mirror.
        let v1JSON = """
        {
          "schemaVersion": 1,
          "kind": "workoutLifecycle",
          "lifecycleEvent": { "started": { "_0": "running" } }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WCMessage.self, from: v1JSON)
        XCTAssertEqual(decoded, .workoutLifecycle(.started(.running)))
    }

    func testUnsupportedFutureSchemaThrows() {
        let futureJSON = """
        { "schemaVersion": 99, "kind": "workoutSnapshot" }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(WCMessage.self, from: futureJSON)) { error in
            XCTAssertEqual(error as? WCMessageCodingError, .unsupportedSchemaVersion(99))
        }
    }
}
