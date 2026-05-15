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
