// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

/// Locks the per-workout-type default HUD layouts (v0.6.0). Key invariants:
/// cycling uses `.speed` (never `.pace`); indoor variants never show
/// `.elevation`; every default has exactly four slots.
final class HUDLayoutDefaultsTests: XCTestCase {

    func testOutdoorRunDefault() {
        XCTAssertEqual(
            HUDLayout.default(for: .outdoorRun).slots,
            [.pace, .heartRate, .distance, .duration]
        )
    }

    func testIndoorRunDefaultUsesCadenceNoDistance() {
        XCTAssertEqual(
            HUDLayout.default(for: .indoorRun).slots,
            [.pace, .heartRate, .cadence, .duration]
        )
    }

    func testOutdoorWalkDefault() {
        XCTAssertEqual(
            HUDLayout.default(for: .outdoorWalk).slots,
            [.pace, .heartRate, .distance, .duration]
        )
    }

    func testIndoorWalkDefault() {
        XCTAssertEqual(
            HUDLayout.default(for: .indoorWalk).slots,
            [.duration, .heartRate, .distance, .energy]
        )
    }

    func testOutdoorBikeUsesSpeedNotPace() {
        let slots = HUDLayout.default(for: .outdoorBike).slots
        XCTAssertEqual(slots, [.speed, .heartRate, .distance, .duration])
        XCTAssertFalse(slots.contains(.pace), "cycling must use speed, never pace")
    }

    func testIndoorBikeDefault() {
        let slots = HUDLayout.default(for: .indoorBike).slots
        XCTAssertEqual(slots, [.cadence, .heartRate, .duration, .energy])
        XCTAssertFalse(slots.contains(.pace), "cycling must use speed, never pace")
    }

    func testNoIndoorDefaultShowsElevationAndAllHaveFourSlots() {
        for type in WorkoutType.allCases {
            let layout = HUDLayout.default(for: type)
            XCTAssertEqual(layout.slots.count, 4, "\(type.rawValue) should have 4 slots")
            if type.isIndoor {
                XCTAssertFalse(
                    layout.slots.contains(.elevation),
                    "\(type.rawValue) is indoor and must not show elevation"
                )
            }
        }
    }

    func testDefaultsAreCodableRoundTrippable() throws {
        for type in WorkoutType.allCases {
            let layout = HUDLayout.default(for: type)
            let data = try JSONEncoder().encode(layout)
            let decoded = try JSONDecoder().decode(HUDLayout.self, from: data)
            XCTAssertEqual(decoded, layout)
        }
    }
}
