// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

final class ExponentialBackoffTests: XCTestCase {
    func testFirstAttemptReturnsInitial() {
        let backoff = ExponentialBackoff(initial: 1.0, maximum: 8.0, multiplier: 2.0)
        XCTAssertEqual(backoff.delay(forAttempt: 0), 1.0, accuracy: 1e-9)
    }

    func testSequenceMatchesSpike() {
        // Spike doc: 1s, 2s, 4s, 8s (then capped).
        let backoff = ExponentialBackoff()
        XCTAssertEqual(backoff.delay(forAttempt: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(backoff.delay(forAttempt: 1), 2.0, accuracy: 1e-9)
        XCTAssertEqual(backoff.delay(forAttempt: 2), 4.0, accuracy: 1e-9)
        XCTAssertEqual(backoff.delay(forAttempt: 3), 8.0, accuracy: 1e-9)
        XCTAssertEqual(backoff.delay(forAttempt: 10), 8.0, accuracy: 1e-9, "capped at max")
    }

    func testCuratedLayoutMappingResolvesKnownIDs() {
        XCTAssertEqual(CuratedLayoutCatalog.deviceID(for: "minimal-run"), 0x01)
        XCTAssertEqual(CuratedLayoutCatalog.deviceID(for: "balanced-run"), 0x02)
        XCTAssertEqual(CuratedLayoutCatalog.deviceID(for: "telemetry-run"), 0x03)
        XCTAssertNil(CuratedLayoutCatalog.deviceID(for: "made-up-layout"))
    }
}
