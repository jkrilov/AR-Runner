// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

final class ActiveLookCommandTests: XCTestCase {
    func testClearFrameMatchesSpec() {
        // 0xFF | 0x01 | 0x00 | length=5 | 0xAA  → exactly 5 bytes
        let frame = ActiveLookCommand.clear()
        XCTAssertEqual(frame, [0xFF, 0x01, 0x00, 0x05, 0xAA])
    }

    func testPowerOnFrame() {
        let frame = ActiveLookCommand.power(on: true)
        XCTAssertEqual(frame.first, 0xFF)
        XCTAssertEqual(frame.last, 0xAA)
        XCTAssertEqual(frame[1], 0x00)            // command id
        XCTAssertEqual(frame[2], 0x00)            // format: no query, 1-byte len
        XCTAssertEqual(Int(frame[3]), frame.count) // length matches actual frame size
        XCTAssertTrue(frame.contains(0x01))        // payload byte = on
    }

    func testLumaClampsAboveMax() {
        let frame = ActiveLookCommand.luma(level: 99)
        // payload byte sits at index 4 (after start, cmd, format, length)
        XCTAssertEqual(frame[4], 15)
    }

    func testWidgetUpdateContainsLayoutAndFieldAndUTF8Value() {
        let frame = ActiveLookCommand.updateWidget(layoutID: 0x02, fieldIndex: 0x01, value: "5:42")
        XCTAssertEqual(frame.first, 0xFF)
        XCTAssertEqual(frame.last, 0xAA)
        XCTAssertEqual(frame[1], ActiveLookCommand.ID.widgetUpdate.rawValue)
        // payload starts at index 4
        XCTAssertEqual(frame[4], 0x02)
        XCTAssertEqual(frame[5], 0x01)
        // value bytes "5:42" + null terminator
        XCTAssertEqual(Array(frame[6..<10]), Array("5:42".utf8))
        XCTAssertEqual(frame[10], 0x00)
    }

    func testTwoByteLengthPromotionForLargePayload() {
        // Force length > 255 to verify the format byte's high bit flips.
        let big = String(repeating: "x", count: 300)
        let frame = ActiveLookCommand.updateWidget(layoutID: 0x01, fieldIndex: 0x00, value: big)
        XCTAssertGreaterThan(frame.count, 0xFF)
        // Format byte must indicate 2-byte length encoding.
        XCTAssertEqual(frame[2] & 0x10, 0x10)
        // Length is big-endian across [3], [4]
        let encodedLen = (Int(frame[3]) << 8) | Int(frame[4])
        XCTAssertEqual(encodedLen, frame.count)
    }

    func testQueryIDIsEncodedWhenPresent() {
        let frame = ActiveLookCommand.encode(id: .battery, payload: [], queryID: 0x1234)
        // format byte low nibble = 2 (queryID length)
        XCTAssertEqual(frame[2] & 0x0F, 0x02)
        // queryID bytes follow length
        XCTAssertEqual(frame[4], 0x12)
        XCTAssertEqual(frame[5], 0x34)
        XCTAssertEqual(frame.last, 0xAA)
    }

    func testDisplayLayoutFrameCarriesOnlyTheLayoutID() {
        // v0.2 spec compliance: cmd 0x62 takes a single layout-ID byte as
        // payload. Initial slot content is pushed via widgetUpdate, NOT
        // appended here. Regression guard for the v0.1 implementation that
        // appended UTF-8 text + a null terminator.
        let frame = ActiveLookCommand.displayLayout(id: 0x02)
        XCTAssertEqual(frame, [0xFF, 0x62, 0x00, 0x06, 0x02, 0xAA])
    }

    func testGATTUUIDsAreCanonical() {
        // Sanity-check the constants against the iOS SDK source — failing this
        // means we typo'd the GATT profile and would fail to discover services.
        XCTAssertEqual(ActiveLookGATT.commandService,
                       "0783B03E-8535-B5A0-7140-A304D2495CB7")
        XCTAssertEqual(ActiveLookGATT.rxCharacteristic,
                       "0783B03E-8535-B5A0-7140-A304D2495CBA")
        XCTAssertEqual(ActiveLookGATT.txCharacteristic,
                       "0783B03E-8535-B5A0-7140-A304D2495CB8")
    }
}
