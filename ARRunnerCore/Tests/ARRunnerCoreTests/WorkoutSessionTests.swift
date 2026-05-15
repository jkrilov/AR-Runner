// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class WorkoutSessionTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sport: .running,
            startedAt: Date(timeIntervalSinceReferenceDate: 600),
            status: .running,
            metricStream: [
                WorkoutMetric(kind: .heartRate, value: 151, unit: "count/min", timestamp: Date(timeIntervalSinceReferenceDate: 601))
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutSession.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
