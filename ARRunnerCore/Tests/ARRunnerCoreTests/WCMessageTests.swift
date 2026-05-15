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
}
