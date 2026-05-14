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
