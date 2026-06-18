// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

/// Structural guarantees for the per-type default HUD layouts that
/// `HUDLayoutDefaultsTests` (slot contents) doesn't assert: every default has
/// a unique, stable `id`; the indoor bike carries no GPS `.distance`; and a
/// well-formed name/id pair exists for all six types.
final class HUDLayoutDefaultUniquenessTests: XCTestCase {

    func testAllDefaultLayoutIDsAreUnique() {
        let ids = WorkoutType.allCases.map { HUDLayout.default(for: $0).id }
        XCTAssertEqual(Set(ids).count, ids.count, "default layout ids must be unique: \(ids)")
        XCTAssertEqual(ids.count, 6)
    }

    func testIndoorBikeHasNoGPSDistance() {
        let slots = HUDLayout.default(for: .indoorBike).slots
        XCTAssertFalse(
            slots.contains(.distance),
            "stationary bike has no GPS/wheel distance — default must not show it"
        )
    }

    func testEveryDefaultIDFollowsStablePrefixAndIsNonEmpty() {
        for type in WorkoutType.allCases {
            let layout = HUDLayout.default(for: type)
            XCTAssertFalse(layout.id.isEmpty, "\(type.rawValue) default id is empty")
            XCTAssertFalse(layout.name.isEmpty, "\(type.rawValue) default name is empty")
            XCTAssertTrue(
                layout.id.hasPrefix("default-"),
                "\(type.rawValue) default id should be namespaced: \(layout.id)"
            )
        }
    }

    func testDefaultIDsAreStableContractStrings() {
        // These ids are persisted/synced; a rename silently orphans a user's
        // saved selection. Pin them.
        XCTAssertEqual(HUDLayout.default(for: .outdoorRun).id, "default-outdoor-run")
        XCTAssertEqual(HUDLayout.default(for: .indoorRun).id, "default-indoor-run")
        XCTAssertEqual(HUDLayout.default(for: .outdoorWalk).id, "default-outdoor-walk")
        XCTAssertEqual(HUDLayout.default(for: .indoorWalk).id, "default-indoor-walk")
        XCTAssertEqual(HUDLayout.default(for: .outdoorBike).id, "default-outdoor-bike")
        XCTAssertEqual(HUDLayout.default(for: .indoorBike).id, "default-indoor-bike")
    }

    func testNoDefaultMixesPaceAndSpeed() {
        // pace and speed are mutually exclusive per type — a default must
        // never contain both (would be a contradictory display).
        for type in WorkoutType.allCases {
            let slots = HUDLayout.default(for: type).slots
            XCTAssertFalse(
                slots.contains(.pace) && slots.contains(.speed),
                "\(type.rawValue) default mixes pace and speed"
            )
        }
    }
}
