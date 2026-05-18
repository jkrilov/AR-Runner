// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

final class GlassesAdvertisementFilterTests: XCTestCase {
    func test_isActiveLookPeripheral_acceptsMicrooledManufacturerData() {
        let data = Data([0xFA, 0xDA, 0x01, 0x02, 0x03])
        XCTAssertTrue(GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: data))
    }

    func test_isActiveLookPeripheral_acceptsExactlyTwoBytePrefix() {
        // Minimum-length payload that should still be accepted (just the
        // company ID, no trailing model bytes).
        let data = Data([0xFA, 0xDA])
        XCTAssertTrue(GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: data))
    }

    func test_isActiveLookPeripheral_rejectsOtherManufacturer() {
        // 0x004C is Apple's company ID in little-endian form.
        let data = Data([0x4C, 0x00, 0xFA, 0xDA])
        XCTAssertFalse(GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: data))
    }

    func test_isActiveLookPeripheral_rejectsByteSwappedPrefix() {
        // Guard against the easy mistake of writing big-endian 0xDA 0xFA.
        let data = Data([0xDA, 0xFA, 0x00])
        XCTAssertFalse(GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: data))
    }

    func test_isActiveLookPeripheral_rejectsTooShort() {
        XCTAssertFalse(GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: Data([0xFA])))
    }

    func test_isActiveLookPeripheral_rejectsEmpty() {
        XCTAssertFalse(GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: Data()))
    }

    func test_isActiveLookPeripheral_rejectsNil() {
        XCTAssertFalse(GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: nil))
    }

    func test_isActiveLookPeripheral_respectsNonZeroStartIndex() {
        // Slices preserve the original startIndex; the helper must index from
        // the slice's start, not absolute byte 0, or it would silently accept
        // any blob whose absolute bytes 0..1 happen to be 0xFA 0xDA.
        let backing = Data([0x00, 0x00, 0xFA, 0xDA, 0x10])
        let slice = backing.suffix(from: 2)
        XCTAssertTrue(GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: slice))

        let mismatchedSlice = backing.prefix(2) // [0x00, 0x00]
        XCTAssertFalse(
            GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: mismatchedSlice)
        )
    }
}
