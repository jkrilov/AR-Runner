// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

final class ARMetadataStoreTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = ARWorkoutMetadata(layoutID: "balanced-run", bleDropCount: 2, glassesBatteryAtEnd: 78)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ARWorkoutMetadata.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
