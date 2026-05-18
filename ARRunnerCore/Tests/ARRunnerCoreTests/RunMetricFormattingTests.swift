// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Lock the contract for the in-run watch display formatters. Joe's
/// v0.2.0 device test regressed on all three of these (distance in the
/// wrong unit, distance jumping per-sample instead of cumulative, avg
/// pace missing entirely) so the helpers are intentionally narrow and
/// fully covered here.
final class RunMetricFormattingTests: XCTestCase {

    // MARK: - miles(fromMeters:)

    func testMilesConversionMatchesStatuteMile() {
        XCTAssertEqual(RunMetricFormatting.miles(fromMeters: 1609.344), 1.0, accuracy: 1e-9)
        XCTAssertEqual(RunMetricFormatting.miles(fromMeters: 0), 0.0)
        XCTAssertEqual(RunMetricFormatting.miles(fromMeters: 5_000), 3.10685596, accuracy: 1e-6)
    }

    // MARK: - formatMiles(meters:)

    func testFormatMilesProducesTwoDecimalsWithSuffix() {
        XCTAssertEqual(RunMetricFormatting.formatMiles(meters: 0), "0.00 mi")
        XCTAssertEqual(RunMetricFormatting.formatMiles(meters: 1609.344), "1.00 mi")
        // 5,000 m ≈ 3.1069 mi → rounds to 3.11 mi.
        XCTAssertEqual(RunMetricFormatting.formatMiles(meters: 5_000), "3.11 mi")
        // Joe's example from the spec.
        XCTAssertEqual(RunMetricFormatting.formatMiles(meters: 1609.344 * 2.34), "2.34 mi")
    }

    // MARK: - formatAveragePacePerMile(...)

    func testAveragePacePlaceholderWhenDistanceZero() {
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: 30, distanceMeters: 0),
            "--:--/mi"
        )
    }

    func testAveragePacePlaceholderWhenElapsedZero() {
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: 0, distanceMeters: 1609.344),
            "--:--/mi"
        )
    }

    func testAveragePacePlaceholderBelowFirstSampleThreshold() {
        // <0.01 mi (~16 m) — the early-run spike that would otherwise
        // produce a wildly fluctuating pace on the watch face.
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: 5, distanceMeters: 5),
            "--:--/mi"
        )
    }

    func testAveragePaceFormatsMinutesSecondsPerMile() {
        // 1 mile in exactly 9:00.
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: 540, distanceMeters: 1609.344),
            "9:00/mi"
        )
        // 2 miles in 19:30 → 9:45/mi.
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: 1170, distanceMeters: 1609.344 * 2),
            "9:45/mi"
        )
    }

    func testAveragePacePadsSecondsToTwoDigits() {
        // 1 mile in 7:05 — verifies the "%02d" pad so we never show "7:5/mi".
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: 425, distanceMeters: 1609.344),
            "7:05/mi"
        )
    }

    func testAveragePaceIncludesHoursForUltraSlowWalks() {
        // 1 mile in 1h05m04s — extremely slow walk, still well-formed.
        let elapsed: TimeInterval = 3600 + 5 * 60 + 4
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: elapsed, distanceMeters: 1609.344),
            "1:05:04/mi"
        )
    }

    func testAveragePaceGuardsAgainstNonFiniteInputs() {
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: .infinity, distanceMeters: 1609.344),
            "--:--/mi"
        )
        XCTAssertEqual(
            RunMetricFormatting.formatAveragePacePerMile(elapsedSeconds: .nan, distanceMeters: 1609.344),
            "--:--/mi"
        )
    }
}
