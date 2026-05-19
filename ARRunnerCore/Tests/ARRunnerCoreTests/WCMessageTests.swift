// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class WCMessageTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = WCMessage.workoutLifecycle(.started(.running))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WCMessage.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, WCMessage.currentSchemaVersion)
    }

    /// v0.4-rc1 — glasses battery percent crosses the WC boundary as its
    /// own message case (schema v3). Round-trip guard so any future codable
    /// edit keeps the watch→phone battery delivery format wire-compatible.
    func testGlassesBatteryRoundTrip() throws {
        let original = WCMessage.glassesBattery(level: 73)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WCMessage.self, from: data)

        XCTAssertEqual(decoded, original)
        if case .glassesBattery(let level) = decoded {
            XCTAssertEqual(level, 73)
        } else {
            XCTFail("expected .glassesBattery, got \(decoded)")
        }
    }

    /// Schema v3 must remain backward compatible with v2 payloads. A peer
    /// running the rc16 watch app encodes `currentSchemaVersion = 2` for
    /// every message; the phone (now v3-aware) must still decode them.
    func testV2EncodedSnapshotIsDecodableByV3() throws {
        let snapshotJSON = """
        {"schemaVersion":2,"kind":"workoutLifecycle","lifecycleEvent":{"paused":{}}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WCMessage.self, from: snapshotJSON)
        XCTAssertEqual(decoded, .workoutLifecycle(.paused))
    }

    func testUnsupportedSchemaVersionThrows() {
        let futureJSON = """
        {"schemaVersion":99,"kind":"glassesBattery","batteryLevel":50}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(WCMessage.self, from: futureJSON))
    }
}
