// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class TCXEncoderTests: XCTestCase {

    // MARK: - Fixtures

    private let fixedID = UUID(uuidString: "DEADBEEF-0000-0000-0000-000000000001")!
    private let start = Date(timeIntervalSince1970: 1_716_192_000) // 2024-05-20T08:00:00Z
    private var end: Date { start.addingTimeInterval(1800) }       // +30 min

    private func makeData(
        trackpoints: [TCXTrackpoint] = [],
        laps: [TCXLap]? = nil
    ) -> TCXWorkoutData {
        TCXWorkoutData(
            workoutID: fixedID,
            startDate: start,
            endDate: end,
            totalDistanceMeters: 5_000,
            totalDurationSeconds: 1_800,
            sport: "Running",
            trackpoints: trackpoints,
            laps: laps ?? []
        )
    }

    // MARK: - Well-formed XML

    /// Parses output to assert the document is syntactically valid XML.
    private func assertWellFormedXML(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        let parser = XMLParser(data: data)
        let ok = parser.parse()
        XCTAssertTrue(ok, "XMLParser failed: \(parser.parserError?.localizedDescription ?? "unknown")", file: file, line: line)
    }

    // MARK: - Structure tests

    func testEmptyWorkoutProducesValidMinimalTCX() throws {
        let data = TCXEncoder.encode(makeData())
        assertWellFormedXML(data)

        let xml = String(data: data, encoding: .utf8)!
        XCTAssertTrue(xml.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        XCTAssertTrue(xml.contains("<TrainingCenterDatabase"))
        XCTAssertTrue(xml.contains("xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\""))
        XCTAssertTrue(xml.contains("<Activity Sport=\"Running\">"))
        XCTAssertTrue(xml.contains("<Lap StartTime="), "Must synthesize a single lap even with no data")
        XCTAssertFalse(xml.contains("<Track>"), "Empty trackpoints must NOT emit an empty <Track>")
        XCTAssertTrue(xml.contains("</TrainingCenterDatabase>"))
    }

    func testFullWorkoutWithRouteAndHR() throws {
        let tps: [TCXTrackpoint] = (0..<5).map { i in
            TCXTrackpoint(
                timestamp: start.addingTimeInterval(TimeInterval(i * 60)),
                latitude: 37.7749 + Double(i) * 0.0001,
                longitude: -122.4194 + Double(i) * 0.0001,
                altitudeMeters: 10 + Double(i),
                heartRateBPM: 140 + i
            )
        }
        let data = TCXEncoder.encode(makeData(trackpoints: tps))
        assertWellFormedXML(data)
        let xml = String(data: data, encoding: .utf8)!

        // Trackpoint cardinality.
        let tpCount = xml.components(separatedBy: "<Trackpoint>").count - 1
        XCTAssertEqual(tpCount, 5)

        XCTAssertTrue(xml.contains("<LatitudeDegrees>37.7749000</LatitudeDegrees>"))
        XCTAssertTrue(xml.contains("<LongitudeDegrees>-122.4194000</LongitudeDegrees>"))
        XCTAssertTrue(xml.contains("<AltitudeMeters>10.00</AltitudeMeters>"))
        XCTAssertTrue(xml.contains("<HeartRateBpm>"))
        XCTAssertTrue(xml.contains("<Value>140</Value>"))
        XCTAssertTrue(xml.contains("<Value>144</Value>"))
    }

    func testRouteOnlyNoHR() throws {
        let tps = [
            TCXTrackpoint(timestamp: start, latitude: 1.0, longitude: 2.0, altitudeMeters: 3.0),
            TCXTrackpoint(timestamp: start.addingTimeInterval(60), latitude: 1.1, longitude: 2.1, altitudeMeters: 3.1)
        ]
        let data = TCXEncoder.encode(makeData(trackpoints: tps))
        assertWellFormedXML(data)
        let xml = String(data: data, encoding: .utf8)!

        XCTAssertTrue(xml.contains("<Position>"))
        XCTAssertFalse(xml.contains("<HeartRateBpm>"), "Must not emit HR when no samples present")
    }

    func testHROnlyNoRoute() throws {
        let tps = [
            TCXTrackpoint(timestamp: start, heartRateBPM: 120),
            TCXTrackpoint(timestamp: start.addingTimeInterval(30), heartRateBPM: 135)
        ]
        let data = TCXEncoder.encode(makeData(trackpoints: tps))
        assertWellFormedXML(data)
        let xml = String(data: data, encoding: .utf8)!

        XCTAssertFalse(xml.contains("<Position>"), "Must not emit empty <Position>")
        XCTAssertFalse(xml.contains("<LatitudeDegrees>"), "Must not emit empty position children")
        XCTAssertTrue(xml.contains("<HeartRateBpm>"))
        XCTAssertTrue(xml.contains("<Value>120</Value>"))
    }

    // MARK: - Field correctness

    func testExternalIDIsIncluded() throws {
        let data = TCXEncoder.encode(makeData())
        let xml = String(data: data, encoding: .utf8)!
        // workoutID (Strava external_id) is embedded in <Notes> so that
        // golden-file comparisons can verify idempotency-key propagation
        // without needing the upload layer.
        XCTAssertTrue(xml.contains(fixedID.uuidString.uppercased())
                      || xml.contains(fixedID.uuidString),
                      "external_id (workoutID UUID) must appear in output")
    }

    func testViaARRunnerDescription() throws {
        let data = TCXEncoder.encode(makeData())
        let xml = String(data: data, encoding: .utf8)!
        XCTAssertTrue(xml.contains("via AR-Runner"))
    }

    func testDistanceAndDurationPrecision() throws {
        let d = TCXWorkoutData(
            workoutID: fixedID,
            startDate: start,
            endDate: end,
            totalDistanceMeters: 5_123.45,
            totalDurationSeconds: 1_834.5,
            trackpoints: [],
            laps: []
        )
        let xml = TCXEncoder.encodeToString(d)
        XCTAssertTrue(xml.contains("<DistanceMeters>5123.45</DistanceMeters>"))
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>1834.50</TotalTimeSeconds>"))
    }

    func testCustomLapWithHRAggregates() throws {
        let lap = TCXLap(
            startTime: start,
            totalTimeSeconds: 1_800,
            distanceMeters: 5_000,
            calories: 350,
            averageHeartRate: 145,
            maximumHeartRate: 172,
            trackpoints: []
        )
        let xml = TCXEncoder.encodeToString(makeData(laps: [lap]))
        XCTAssertTrue(xml.contains("<Calories>350</Calories>"))
        XCTAssertTrue(xml.contains("<AverageHeartRateBpm>"))
        XCTAssertTrue(xml.contains("<Value>145</Value>"))
        XCTAssertTrue(xml.contains("<MaximumHeartRateBpm>"))
        XCTAssertTrue(xml.contains("<Value>172</Value>"))
    }

    func testTimestampFormatIsISO8601WithMillisUTC() throws {
        let formatted = TCXEncoder.formatTimestamp(start)
        // Expected: 2024-05-20T08:00:00.000Z
        XCTAssertEqual(formatted, "2024-05-20T08:00:00.000Z")
    }

    func testNamespaceConstants() {
        XCTAssertEqual(TCXEncoder.namespace,
                       "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2")
    }

    // MARK: - Determinism

    func testEncoderIsDeterministic() throws {
        let d = makeData(trackpoints: [
            TCXTrackpoint(timestamp: start, latitude: 1, longitude: 2, heartRateBPM: 130)
        ])
        let a = TCXEncoder.encode(d)
        let b = TCXEncoder.encode(d)
        XCTAssertEqual(a, b, "Same input must produce byte-identical output (Strava idempotency)")
    }

    // MARK: - XML escaping

    func testXMLEscapingOfSpecialChars() {
        XCTAssertEqual(TCXEncoder.escapeText("A & B < C > D"),
                       "A &amp; B &lt; C &gt; D")
        XCTAssertEqual(TCXEncoder.escapeAttr("a\"b'c&d<e>f"),
                       "a&quot;b&apos;c&amp;d&lt;e&gt;f")
    }

    func testSportNameIsEscapedInAttribute() {
        let d = TCXWorkoutData(
            workoutID: fixedID,
            startDate: start,
            endDate: end,
            totalDistanceMeters: 0,
            totalDurationSeconds: 0,
            sport: "Run & \"go\"",
            trackpoints: [],
            laps: []
        )
        let xml = TCXEncoder.encodeToString(d)
        XCTAssertTrue(xml.contains("Sport=\"Run &amp; &quot;go&quot;\""))
        // Document must remain well-formed even with escaping.
        assertWellFormedXML(xml.data(using: .utf8)!)
    }

    // MARK: - Locale safety

    func testDecimalFormattingIsLocaleIndependent() {
        // Even if a French locale is the device default, "%.2f" via
        // en_US_POSIX must still produce "." as the decimal separator.
        XCTAssertEqual(TCXEncoder.formatDecimal(1.5), "1.50")
        XCTAssertEqual(TCXEncoder.formatCoordinate(-122.4194), "-122.4194000")
    }
}
