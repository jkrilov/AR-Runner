// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

final class ActiveLookCommandTests: XCTestCase {
    func testClearFrameMatchesSpec() {
        // 0xFF | 0x01 (clear) | 0x01 (format: 1-byte queryID) | length=6 |
        // queryID=0x00 (placeholder; adapter stamps a real one) | 0xAA
        let frame = ActiveLookCommand.clear()
        XCTAssertEqual(frame, [0xFF, 0x01, 0x01, 0x06, 0x00, 0xAA])
    }

    func testPowerOnFrame() {
        let frame = ActiveLookCommand.power(on: true)
        XCTAssertEqual(frame.first, 0xFF)
        XCTAssertEqual(frame.last, 0xAA)
        XCTAssertEqual(frame[1], 0x00)            // command id
        XCTAssertEqual(frame[2], 0x01)            // format: 1-byte queryID, 1-byte len
        XCTAssertEqual(Int(frame[3]), frame.count) // length matches actual frame size
        XCTAssertEqual(frame[4], 0x00)            // queryID placeholder
        XCTAssertEqual(frame[5], 0x01)            // payload byte = on
    }

    func testLumaClampsAboveMax() {
        let frame = ActiveLookCommand.luma(level: 99)
        // payload byte sits at index 5 (after start, cmd, format, length, queryID)
        XCTAssertEqual(frame[5], 15)
    }

    func testWidgetUpdateContainsLayoutAndFieldAndUTF8Value() {
        let frame = ActiveLookCommand.updateWidget(layoutID: 0x02, fieldIndex: 0x01, value: "5:42")
        XCTAssertEqual(frame.first, 0xFF)
        XCTAssertEqual(frame.last, 0xAA)
        XCTAssertEqual(frame[1], ActiveLookCommand.ID.widgetUpdate.rawValue)
        XCTAssertEqual(frame[2], 0x01)            // format: 1-byte queryID
        // queryID placeholder at index 4; payload starts at index 5
        XCTAssertEqual(frame[4], 0x00)
        XCTAssertEqual(frame[5], 0x02)
        XCTAssertEqual(frame[6], 0x01)
        // value bytes "5:42" + null terminator
        XCTAssertEqual(Array(frame[7..<11]), Array("5:42".utf8))
        XCTAssertEqual(frame[11], 0x00)
    }

    func testTwoByteLengthPromotionForLargePayload() {
        // Force length > 255 to verify the format byte's high bit flips
        // while the queryID nibble stays at 0x01.
        let big = String(repeating: "x", count: 300)
        let frame = ActiveLookCommand.updateWidget(layoutID: 0x01, fieldIndex: 0x00, value: big)
        XCTAssertGreaterThan(frame.count, 0xFF)
        // Format byte must indicate 2-byte length encoding AND 1-byte queryID.
        XCTAssertEqual(frame[2] & 0x10, 0x10)
        XCTAssertEqual(frame[2] & 0x0F, 0x01)
        // Length is big-endian across [3], [4]; queryID at [5].
        let encodedLen = (Int(frame[3]) << 8) | Int(frame[4])
        XCTAssertEqual(encodedLen, frame.count)
        XCTAssertEqual(frame[5], 0x00) // queryID placeholder
    }

    func testEncodeIncludesQueryIDByDefault() {
        // Critical regression guard for the PR #49/#53/#55 root cause: every
        // application command MUST emit `format = 0x01` with a 1-byte queryID
        // so Engo 2 firmware parses the data region from the right offset.
        let frame = ActiveLookCommand.encode(id: .clear, payload: [])
        XCTAssertEqual(frame[2] & 0x0F, 0x01, "default encoding must include 1 queryID byte")
        XCTAssertEqual(frame[4], 0x00, "deterministic placeholder queryID for test stability")
    }

    func testEncodeUsesExplicitQueryIDByteWhenProvided() {
        let frame = ActiveLookCommand.encode(id: .clear, payload: [], queryID: 0x7F)
        XCTAssertEqual(frame[2] & 0x0F, 0x01)
        XCTAssertEqual(frame[4], 0x7F)
    }

    func testEncodeOmitsQueryIDWhenWithoutQueryIdTrue() {
        // DFU-style opt-out (qspiErase / qspiWrite / reset). Mirrors the
        // ActiveLook iOS SDK convention so future DFU plumbing is byte-correct.
        let frame = ActiveLookCommand.encode(id: .clear, payload: [], withoutQueryId: true)
        XCTAssertEqual(frame[2] & 0x0F, 0x00, "withoutQueryId frames must have format nibble 0x00")
        // Frame is [0xFF, 0x01, 0x00, 0x05, 0xAA] — no queryID byte at all.
        XCTAssertEqual(frame, [0xFF, 0x01, 0x00, 0x05, 0xAA])
    }

    func testDisplayLayoutFrameCarriesOnlyTheLayoutID() {
        // v0.2 spec compliance: cmd 0x62 takes a single layout-ID byte as
        // payload. With the queryID byte, the frame is 7 bytes (was 6 in v0.1).
        let frame = ActiveLookCommand.displayLayout(id: 0x02)
        XCTAssertEqual(frame, [0xFF, 0x62, 0x01, 0x07, 0x00, 0x02, 0xAA])
    }

    /// rc9: holdFlush (cmdID 0x39) per ActiveLook spec §4.6 — wraps a
    /// batch of draw commands so they commit atomically to the display,
    /// eliminating intermediate blank/torn states between writes.
    /// Payload: action byte; 0x00 = HOLD, 0x01 = FLUSH.
    func testHoldFlushEncodesAsExpected() {
        // hold:true → action 0x00 (HOLD).
        // Wire: 0xFF | 0x39 | format=0x01 | len=7 | queryID=0x00 | 0x00 | 0xAA.
        let hold = ActiveLookCommand.holdFlush(hold: true)
        XCTAssertEqual(hold, [0xFF, 0x39, 0x01, 0x07, 0x00, 0x00, 0xAA])

        // hold:false → action 0x01 (FLUSH).
        let flush = ActiveLookCommand.holdFlush(hold: false)
        XCTAssertEqual(flush, [0xFF, 0x39, 0x01, 0x07, 0x00, 0x01, 0xAA])
    }

    func testCfgSetEncodesAsExpected() {
        // rc8: cfgSet(name: "ALooK") activates the ALooK configuration on
        // the glasses so fonts 1–5 / layouts / images are addressable.
        // Wire format: 0xFF | 0xD2 | format=0x01 | len | queryID=0x00 |
        // 'A' 'L' 'o' 'o' 'K' | 0x00 (NUL) | 0xAA.
        // Total = 1 + 1 + 1 + 1 + 1 + 5 + 1 + 1 = 12 bytes → len = 0x0C.
        let frame = ActiveLookCommand.cfgSet(name: "ALooK")
        XCTAssertEqual(frame, [
            0xFF, 0xD2, 0x01, 0x0C, 0x00,
            0x41, 0x4C, 0x6F, 0x6F, 0x4B,
            0x00,
            0xAA
        ])
    }

    func testCfgSetPayloadIsNullTerminated() {
        // The config-name string in the cfgSet payload is C-style NUL-
        // terminated; the byte immediately before the 0xAA footer must
        // be 0x00 regardless of name length.
        let short = ActiveLookCommand.cfgSet(name: "A")
        XCTAssertEqual(short[short.count - 2], 0x00, "NUL terminator before footer")
        XCTAssertEqual(short.last, 0xAA)

        let long = ActiveLookCommand.cfgSet(name: "DemoApp")
        XCTAssertEqual(long[long.count - 2], 0x00, "NUL terminator before footer")
        XCTAssertEqual(long.last, 0xAA)
        // UTF-8 bytes of "DemoApp" appear immediately before the NUL.
        let nameBytes = Array("DemoApp".utf8)
        let needleEnd = long.count - 2
        let needleStart = needleEnd - nameBytes.count
        XCTAssertEqual(Array(long[needleStart..<needleEnd]), nameBytes)
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
