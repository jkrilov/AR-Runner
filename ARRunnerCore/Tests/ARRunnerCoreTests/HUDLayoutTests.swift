import XCTest
@testable import ARRunnerCore

final class HUDLayoutTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = HUDLayout.telemetryRun()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HUDLayout.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
