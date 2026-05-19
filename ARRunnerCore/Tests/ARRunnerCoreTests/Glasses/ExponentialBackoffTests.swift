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

    /// rc17 ADR — `richards-adr-ble-link-lifecycle` P2: the auto-reconnect
    /// loop's backoff schedule MUST stabilise at 60 s (so a powered-off
    /// pair of glasses costs at most one radio cycle per minute) and start
    /// at 1 s (so a transient drop recovers fast). The exact intermediate
    /// values are not load-bearing — the ADR's prose `1/2/5/15/30/60`
    /// target is approximated by a pure-exponential schedule. Pin the
    /// envelope so a future tweak to the adapter constants cannot silently
    /// regress beyond it.
    func testADRv04BackoffStartsAtOneSecondAndCapsAtSixty() {
        let backoff = ExponentialBackoff.adrV04
        XCTAssertEqual(backoff.delay(forAttempt: 0), 1.0, accuracy: 1e-9,
                       "first attempt MUST be fast — user is actively wearing the HUD")
        XCTAssertEqual(backoff.delay(forAttempt: 1), 2.0, accuracy: 1e-9)
        XCTAssertEqual(backoff.delay(forAttempt: 2), 4.0, accuracy: 1e-9)
        XCTAssertEqual(backoff.delay(forAttempt: 6), 60.0, accuracy: 1e-9,
                       "must reach the 60 s ceiling by attempt 6 (≈ 2 min total)")
        XCTAssertEqual(backoff.delay(forAttempt: 1_000), 60.0, accuracy: 1e-9,
                       "60 s cap is steady state — never grows further so an unattended pair of glasses costs at most 1 radio cycle / minute")
    }
}
