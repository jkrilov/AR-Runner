// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Locks the synthetic sample values + the conservative line-1 width heuristic
/// that drive the phone's static HUD-layout preview (custom-HUD Phase B). Pure
/// Core so it runs on the Linux suite — the phone view layer only renders the
/// strings this produces.
final class HUDLayoutSamplePreviewTests: XCTestCase {

    // MARK: - Sample values

    func testSampleValueIsUnitSystemAwareForDistanceAndPaceAndSpeed() {
        XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .distance, system: .metric), "4.20")
        XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .distance, system: .imperial), "2.61")
        XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .pace, system: .metric), "5:30")
        XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .pace, system: .imperial), "8:51")
        XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .speed, system: .metric), "27.4")
        XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .speed, system: .imperial), "17.0")
    }

    func testSampleValueIsSystemIndependentForCountedMetrics() {
        for system in [UnitSystem.metric, .imperial] {
            XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .heartRate, system: system), "152")
            XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .duration, system: system), "23:18")
            XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .cadence, system: system), "168")
            XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .energy, system: system), "320")
        }
    }

    // MARK: - Sample value with unit

    func testSampleValueWithUnitSuffixesCorrectLabel() {
        XCTAssertEqual(
            HUDLayoutSamplePreview.sampleValueWithUnit(for: .heartRate, system: .metric),
            "152 bpm"
        )
        XCTAssertEqual(
            HUDLayoutSamplePreview.sampleValueWithUnit(for: .distance, system: .metric),
            "4.20 km"
        )
        XCTAssertEqual(
            HUDLayoutSamplePreview.sampleValueWithUnit(for: .speed, system: .imperial),
            "17.0 mph"
        )
    }

    func testPaceUnitJoinsWithoutSpace() {
        XCTAssertEqual(
            HUDLayoutSamplePreview.sampleValueWithUnit(for: .pace, system: .metric),
            "5:30/km"
        )
        XCTAssertEqual(
            HUDLayoutSamplePreview.sampleValueWithUnit(for: .pace, system: .imperial),
            "8:51/mi"
        )
    }

    func testDurationHasNoUnitSuffix() {
        XCTAssertEqual(
            HUDLayoutSamplePreview.sampleValueWithUnit(for: .duration, system: .metric),
            "23:18"
        )
    }

    func testCadenceUnitTracksActivity() {
        XCTAssertEqual(
            HUDLayoutSamplePreview.sampleValueWithUnit(for: .cadence, type: .outdoorRun, system: .metric),
            "168 spm"
        )
        XCTAssertEqual(
            HUDLayoutSamplePreview.sampleValueWithUnit(for: .cadence, type: .indoorBike, system: .metric),
            "168 rpm"
        )
    }

    // MARK: - Width heuristic

    func testWidthBudgetUsesGridAnchor() {
        XCTAssertEqual(HUDLayoutSamplePreview.line1RightBudget(), 83)
    }

    func testWidthWarningFlagsWideLine1RightValue() {
        // duration "23:18" is 5 glyphs at font 2 (18px each = 90px) which
        // exceeds the 83px line-1-right budget.
        let layout = HUDLayout(id: "t", name: "T", slots: [.heartRate, .duration, .distance, .pace])
        XCTAssertEqual(
            HUDLayoutSamplePreview.widthWarningSlots(for: layout, system: .metric),
            [HUDLayoutSamplePreview.line1RightIndex]
        )
    }

    func testWidthWarningClearsForNarrowLine1RightValue() {
        // heartRate "152" is 3 glyphs (54px) — well within budget.
        let layout = HUDLayout(id: "t", name: "T", slots: [.duration, .heartRate, .distance, .pace])
        XCTAssertTrue(HUDLayoutSamplePreview.widthWarningSlots(for: layout, system: .metric).isEmpty)
    }

    func testWidthWarningIgnoresEmptyLine1RightSlot() {
        let layout = HUDLayout(id: "t", name: "T", slots: [.pace, nil, .distance, .duration])
        XCTAssertTrue(HUDLayoutSamplePreview.widthWarningSlots(for: layout, system: .metric).isEmpty)
    }

    // MARK: - Heading + variable-grid width warnings (v0.6.5)

    func testSampleValueForHeadingIsSystemIndependent() {
        for system in [UnitSystem.metric, .imperial] {
            XCTAssertEqual(HUDLayoutSamplePreview.sampleValue(for: .heading, system: system), "NE 045°")
        }
    }

    func testTwoItemRightSlotIndicesAreRowMajorRightOfEachPair() {
        XCTAssertEqual(HUDLayoutSamplePreview.twoItemRightSlotIndices(for: .standard), [1])
        // [2,2]: right slots at flat index 1 and 3.
        XCTAssertEqual(
            HUDLayoutSamplePreview.twoItemRightSlotIndices(for: HUDGridConfig(lines: [2, 2])),
            [1, 3]
        )
        // [1,1,1,1]: no 2-item lines → no tight slots.
        XCTAssertTrue(
            HUDLayoutSamplePreview.twoItemRightSlotIndices(for: HUDGridConfig(lines: [1, 1, 1, 1])).isEmpty
        )
    }

    func testWidthWarningScansEveryTwoItemRightSlot() {
        // A 2-line × 2-item grid: line 2's right slot (flat index 3) holds a
        // wide "23:18" duration that overruns the tight right budget.
        let layout = HUDLayout(
            id: "t", name: "T",
            slots: [.pace, .heartRate, .distance, .duration],
            grid: HUDGridConfig(lines: [2, 2])
        )
        let flagged = HUDLayoutSamplePreview.widthWarningSlots(for: layout, system: .metric)
        XCTAssertTrue(flagged.contains(3), "the second 2-item line's right slot must be checked")
    }
}
