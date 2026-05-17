// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// P1.2 (audit 2026-05-16) — throttle backstop on the wired-up HUD path.
///
/// `WorkoutViewModel` now fans the controller's metric stream into
/// `GlassesService`, which uses this throttle to keep BLE traffic at 1Hz per
/// `fieldIndex`. These tests pin the contract that backstop is built on:
///
///   * first send for a fieldIndex always passes
///   * second send within the window is dropped (no record-on-deny)
///   * sends after the window pass and re-arm the gate
///   * different fieldIndices are independent
///   * `reset()` clears every per-field gate (used on disconnect/reconnect)
final class HUDFieldThrottleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func test_firstSendPerFieldIsAllowed() {
        var throttle = HUDFieldThrottle(minimumInterval: 1.0)
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 0, now: t0))
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 5, now: t0))
    }

    func test_secondSendWithinWindowIsDropped() {
        var throttle = HUDFieldThrottle(minimumInterval: 1.0)
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 0, now: t0))
        XCTAssertFalse(throttle.shouldSend(fieldIndex: 0, now: t0.addingTimeInterval(0.25)))
        XCTAssertFalse(throttle.shouldSend(fieldIndex: 0, now: t0.addingTimeInterval(0.999)))
    }

    func test_sendAtBoundaryAndBeyondIsAllowed() {
        var throttle = HUDFieldThrottle(minimumInterval: 1.0)
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 0, now: t0))
        // Exactly at the boundary — strict `<` comparison means the boundary
        // passes. Lock this in so a future change to `<=` is caught.
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 0, now: t0.addingTimeInterval(1.0)))
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 0, now: t0.addingTimeInterval(2.5)))
    }

    func test_deniedSendDoesNotAdvanceTheGate() {
        var throttle = HUDFieldThrottle(minimumInterval: 1.0)
        _ = throttle.shouldSend(fieldIndex: 0, now: t0)
        // Denied attempts at 0.5s must not push the next-allowed point out
        // to 1.5s — the gate must remain anchored at the last successful
        // send so the next allowed send is still at t0 + 1.0s.
        XCTAssertFalse(throttle.shouldSend(fieldIndex: 0, now: t0.addingTimeInterval(0.5)))
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 0, now: t0.addingTimeInterval(1.0)))
    }

    func test_perFieldIndependence() {
        var throttle = HUDFieldThrottle(minimumInterval: 1.0)
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 0, now: t0))
        // A burst across 4 distinct slots (matches the balanced-run layout)
        // must all pass even within the same millisecond — fields don't
        // share the gate.
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 1, now: t0))
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 2, now: t0))
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 3, now: t0))
        // ...but a repeat on field 0 is still gated.
        XCTAssertFalse(throttle.shouldSend(fieldIndex: 0, now: t0))
    }

    func test_resetReleasesEveryFieldGate() {
        var throttle = HUDFieldThrottle(minimumInterval: 1.0)
        _ = throttle.shouldSend(fieldIndex: 0, now: t0)
        _ = throttle.shouldSend(fieldIndex: 1, now: t0)
        throttle.reset()
        // First post-reset send for each field passes immediately — this is
        // what `GlassesService.selectLayout` / `resetThrottle` rely on so
        // the first reconnect tick reaches the glasses without delay.
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 0, now: t0.addingTimeInterval(0.1)))
        XCTAssertTrue(throttle.shouldSend(fieldIndex: 1, now: t0.addingTimeInterval(0.1)))
    }

    func test_defaultMinimumIntervalIsOneSecond() {
        XCTAssertEqual(HUDFieldThrottle.defaultMinimumInterval, 1.0)
    }
}
