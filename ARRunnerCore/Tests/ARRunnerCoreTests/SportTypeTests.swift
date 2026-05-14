import XCTest
@testable import ARRunnerCore

final class SportTypeTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = SportType.running
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SportType.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
