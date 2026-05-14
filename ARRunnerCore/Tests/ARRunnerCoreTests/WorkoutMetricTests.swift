import Foundation
import XCTest
@testable import ARRunnerCore

final class WorkoutMetricTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = WorkoutMetric(kind: .pace, value: 312.4, unit: "s/km", timestamp: Date(timeIntervalSinceReferenceDate: 42))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutMetric.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
