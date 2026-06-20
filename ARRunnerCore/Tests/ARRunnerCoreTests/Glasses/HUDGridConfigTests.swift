// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// v0.6.5 — locks the variable HUD grid: the `HUDGridConfig` shape model, the
/// code-only `HUDGridDefinition.make(for:)` geometry factory, and the additive
/// backward-compatible `HUDLayout.grid` Codable field. Geometry stays in Core
/// and is validated here (never user-editable), the firewall against the
/// rc11→rc16 coordinate-regression class.
final class HUDGridConfigTests: XCTestCase {

    // MARK: - HUDGridConfig shape

    func testStandardIsThreeLineTwoOneOne() {
        XCTAssertEqual(HUDGridConfig.standard.lines, [2, 1, 1])
        XCTAssertEqual(HUDGridConfig.standard.slotCount, 4)
        XCTAssertTrue(HUDGridConfig.standard.isValid)
    }

    func testSlotCountIsSumOfLines() {
        XCTAssertEqual(HUDGridConfig(lines: [2, 2]).slotCount, 4)
        XCTAssertEqual(HUDGridConfig(lines: [1, 1, 1, 1]).slotCount, 4)
        XCTAssertEqual(HUDGridConfig(lines: [2, 2, 2, 2]).slotCount, 8)
        XCTAssertEqual(HUDGridConfig(lines: [1, 1]).slotCount, 2)
    }

    func testValidityRanges() {
        XCTAssertTrue(HUDGridConfig(lines: [2, 1]).isValid)
        XCTAssertTrue(HUDGridConfig(lines: [2, 2, 2, 2]).isValid)
        XCTAssertFalse(HUDGridConfig(lines: [2]).isValid, "1 line is below the minimum")
        XCTAssertFalse(HUDGridConfig(lines: [1, 1, 1, 1, 1]).isValid, "5 lines is above the max")
        XCTAssertFalse(HUDGridConfig(lines: [3, 1]).isValid, "3 items per line is unsupported")
        XCTAssertFalse(HUDGridConfig(lines: [0, 1]).isValid)
    }

    func testValidatedClampsAndFallsBack() {
        XCTAssertEqual(HUDGridConfig(lines: [3, 0, 1]).validated().lines, [2, 1, 1])
        XCTAssertEqual(HUDGridConfig(lines: [2, 2, 2, 2, 2]).validated().lines, [2, 2, 2, 2])
        XCTAssertEqual(HUDGridConfig(lines: []).validated().lines, HUDGridConfig.standard.lines)
        XCTAssertEqual(HUDGridConfig(lines: [2]).validated().lines.count, 2)
    }

    func testCodableRoundTrip() throws {
        let config = HUDGridConfig(lines: [2, 2, 1])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HUDGridConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    // MARK: - make(for:) geometry factory

    func testMakeForStandardIsByteIdenticalToStandard4() {
        let made = HUDGridDefinition.make(for: .standard)
        XCTAssertEqual(made, HUDGridDefinition.standard4)
        XCTAssertEqual(made.slots, HUDGridDefinition.standard4.slots)
    }

    func testMakeProducesSlotPerItemRowMajor() {
        for lines in [[2, 1], [2, 2], [1, 1, 1], [2, 1, 1], [2, 2, 1, 1], [1, 1, 1, 1]] {
            let config = HUDGridConfig(lines: lines)
            let made = HUDGridDefinition.make(for: config)
            XCTAssertEqual(made.slots.count, config.slotCount, "slot count for \(lines)")
        }
    }

    func testMakeFontsFollowAdaptiveHierarchy() {
        // 2-line: 1-item font 4, 2-item font 3.
        let twoLine = HUDGridDefinition.make(for: HUDGridConfig(lines: [1, 2]))
        XCTAssertEqual(twoLine.slots[0].font, 4)              // line 1, 1 item
        XCTAssertEqual(twoLine.slots[1].font, 3)              // line 2, left of 2
        XCTAssertEqual(twoLine.slots[2].font, 3)              // line 2, right of 2

        // 4-line: every line font 2.
        let fourLine = HUDGridDefinition.make(for: HUDGridConfig(lines: [2, 2, 1, 1]))
        XCTAssertTrue(fourLine.slots.allSatisfy { $0.font == 2 })
    }

    func testMakeTwoItemRightSlotUsesTightAnchor() {
        // The right slot of a 2-item line is the historically tight budget at
        // textX 83 (vs the left slot's 243).
        let made = HUDGridDefinition.make(for: HUDGridConfig(lines: [2, 2]))
        XCTAssertEqual(made.slots[0].textX, 243)
        XCTAssertEqual(made.slots[1].textX, 83)
    }

    // MARK: - HUDLayout.grid backward compatibility

    func testLegacyLayoutJSONWithoutGridDecodes() throws {
        // A v0.6.4 layout blob with no `grid` key must still decode (grid nil →
        // standard shape), proving the additive field is backward-compatible.
        let json = """
        {"id":"legacy","name":"Legacy","slots":["pace","heartRate","distance","duration"]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HUDLayout.self, from: json)
        XCTAssertNil(decoded.grid)
        XCTAssertEqual(decoded.resolvedGrid, .standard)
        XCTAssertEqual(decoded.slots, [.pace, .heartRate, .distance, .duration])
    }

    func testLayoutWithGridRoundTrips() throws {
        let layout = HUDLayout(
            id: "g", name: "Grid", slots: [.pace, .heartRate, .distance, .duration, .cadence, .energy],
            grid: HUDGridConfig(lines: [2, 2, 2])
        )
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(HUDLayout.self, from: data)
        XCTAssertEqual(decoded, layout)
        XCTAssertEqual(decoded.grid?.lines, [2, 2, 2])
    }

    func testValidatedPreservesGrid() {
        let layout = HUDLayout(
            id: "g", name: "Grid", slots: [.speed, .heartRate, .distance, .duration],
            grid: HUDGridConfig(lines: [2, 1, 1])
        )
        // `.speed` is invalid for a run and blanks, but the grid survives.
        let validated = layout.validated(for: .outdoorRun)
        XCTAssertEqual(validated.grid, layout.grid)
        XCTAssertNil(validated.slots[0])
    }
}
