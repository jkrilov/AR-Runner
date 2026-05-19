// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

/// Pure-Swift coverage for the rc17 standard-BLE Battery Service
/// (0x180F / 0x2A19) notification gatekeeper. The watch adapter feeds
/// every `didUpdateValueFor` payload's first byte through this filter,
/// so its behaviour is the contract for what reaches the iPhone mirror
/// and the on-watch indicator.
final class BatteryLevelFilterTests: XCTestCase {

    func testFirstValueIsEmitted() {
        var filter = BatteryLevelFilter()
        XCTAssertEqual(filter.process(byte: 73), .emit(73))
    }

    func testBoundaryValuesAreEmitted() {
        var filter = BatteryLevelFilter()
        XCTAssertEqual(filter.process(byte: 0), .emit(0),
                       "0% is a legitimate value — glasses about to power off")
        XCTAssertEqual(filter.process(byte: 100), .emit(100),
                       "100% is the spec maximum")
    }

    func testOutOfRangeBytesAreDropped() {
        var filter = BatteryLevelFilter()
        XCTAssertEqual(filter.process(byte: 101), .dropInvalid(rawByte: 101))
        XCTAssertEqual(filter.process(byte: 200), .dropInvalid(rawByte: 200))
        XCTAssertEqual(filter.process(byte: 0xFF), .dropInvalid(rawByte: 0xFF))
    }

    func testConsecutiveIdenticalValuesAreDeduped() {
        var filter = BatteryLevelFilter()
        XCTAssertEqual(filter.process(byte: 50), .emit(50))
        XCTAssertEqual(filter.process(byte: 50), .dropDuplicate)
        XCTAssertEqual(filter.process(byte: 50), .dropDuplicate)
    }

    func testChangedValueAfterDuplicateRunIsEmitted() {
        var filter = BatteryLevelFilter()
        _ = filter.process(byte: 50)
        _ = filter.process(byte: 50)
        XCTAssertEqual(filter.process(byte: 49), .emit(49),
                       "monotonic decrease should fire a fresh emit")
        XCTAssertEqual(filter.process(byte: 50), .emit(50),
                       "any change from the last-emitted value (even up) re-emits")
    }

    func testInvalidBytesDoNotPoisonDedupMemory() {
        var filter = BatteryLevelFilter()
        _ = filter.process(byte: 50)
        XCTAssertEqual(filter.process(byte: 250), .dropInvalid(rawByte: 250))
        XCTAssertEqual(filter.process(byte: 50), .dropDuplicate,
                       "the invalid byte must not be remembered as the new baseline")
    }

    func testResetClearsDedupMemory() {
        var filter = BatteryLevelFilter()
        XCTAssertEqual(filter.process(byte: 80), .emit(80))
        XCTAssertEqual(filter.process(byte: 80), .dropDuplicate)
        filter.reset()
        XCTAssertEqual(filter.process(byte: 80), .emit(80),
                       "after reset the first observation always lands — this is the rc17 ADR contract: the UI shows '—' across a drop and deserves a fresh value on reconnect")
    }
}
