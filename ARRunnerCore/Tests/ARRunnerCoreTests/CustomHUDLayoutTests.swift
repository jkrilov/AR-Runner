// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Custom-HUD Phase A: locks the new persistence/resolution value types —
/// `HUDLayoutCatalog`, `WorkoutLayoutDefaults`, `HUDLayout.validated(for:)`,
/// and the pure `HUDLayoutResolver`. All pure Swift, Linux-exercisable.
final class CustomHUDLayoutTests: XCTestCase {

    // MARK: - Catalog Codable + helper

    func testCatalogRoundTripPreservesLayoutsAndVersion() throws {
        let catalog = HUDLayoutCatalog(layouts: [
            HUDLayout(id: "c1", name: "Sprint", slots: [.pace, .heartRate, nil, .duration]),
            HUDLayout(id: "c2", name: "Climb", slots: [.elevation, .heartRate, .distance, .duration]),
        ])
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(HUDLayoutCatalog.self, from: data)
        XCTAssertEqual(decoded, catalog)
        XCTAssertEqual(decoded.schemaVersion, HUDLayoutCatalog.currentVersion)
    }

    func testCatalogDefaultsToCurrentVersionAndEmpty() {
        let catalog = HUDLayoutCatalog()
        XCTAssertEqual(catalog.schemaVersion, HUDLayoutCatalog.currentVersion)
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertTrue(catalog.layouts.isEmpty)
    }

    func testCatalogLayoutLookup() {
        let layout = HUDLayout(id: "c1", name: "Sprint", slots: [.pace, .heartRate])
        let catalog = HUDLayoutCatalog(layouts: [layout])
        XCTAssertEqual(catalog.layout(id: "c1"), layout)
        XCTAssertNil(catalog.layout(id: "missing"))
    }

    // MARK: - Defaults Codable + helper

    func testDefaultsRoundTripPreservesAssignmentsAndVersion() throws {
        let defaults = WorkoutLayoutDefaults(assignments: [
            WorkoutType.outdoorRun.rawValue: "c1",
            WorkoutType.indoorBike.rawValue: "c2",
        ])
        let data = try JSONEncoder().encode(defaults)
        let decoded = try JSONDecoder().decode(WorkoutLayoutDefaults.self, from: data)
        XCTAssertEqual(decoded, defaults)
        XCTAssertEqual(decoded.schemaVersion, WorkoutLayoutDefaults.currentVersion)
    }

    func testDefaultsDefaultsToCurrentVersionAndEmpty() {
        let defaults = WorkoutLayoutDefaults()
        XCTAssertEqual(defaults.schemaVersion, WorkoutLayoutDefaults.currentVersion)
        XCTAssertEqual(defaults.schemaVersion, 1)
        XCTAssertTrue(defaults.assignments.isEmpty)
    }

    func testDefaultsLayoutIDLookupKeyedByRawValue() {
        let defaults = WorkoutLayoutDefaults(assignments: [
            WorkoutType.outdoorRun.rawValue: "c1",
        ])
        XCTAssertEqual(defaults.layoutID(for: .outdoorRun), "c1")
        XCTAssertNil(defaults.layoutID(for: .indoorBike))
    }

    // MARK: - Resolver

    func testResolverReturnsAssignedCustomLayout() {
        let custom = HUDLayout(id: "c1", name: "Sprint", slots: [.pace, .heartRate, nil, .duration])
        let catalog = HUDLayoutCatalog(layouts: [custom])
        let defaults = WorkoutLayoutDefaults(assignments: [WorkoutType.outdoorRun.rawValue: "c1"])
        let resolved = HUDLayoutResolver.activeLayout(
            for: .outdoorRun, defaults: defaults, catalog: catalog
        )
        XCTAssertEqual(resolved, custom)
    }

    func testResolverFallsBackToBuiltInWhenNoAssignment() {
        let catalog = HUDLayoutCatalog()
        let defaults = WorkoutLayoutDefaults()
        let resolved = HUDLayoutResolver.activeLayout(
            for: .outdoorBike, defaults: defaults, catalog: catalog
        )
        XCTAssertEqual(resolved, HUDLayout.default(for: .outdoorBike))
    }

    func testResolverFallsBackOnDanglingAssignment() {
        // Assignment points at a layout id that isn't in the catalog (deleted).
        let catalog = HUDLayoutCatalog(layouts: [
            HUDLayout(id: "other", name: "Other", slots: [.duration]),
        ])
        let defaults = WorkoutLayoutDefaults(assignments: [WorkoutType.indoorRun.rawValue: "deleted-id"])
        let resolved = HUDLayoutResolver.activeLayout(
            for: .indoorRun, defaults: defaults, catalog: catalog
        )
        XCTAssertEqual(resolved, HUDLayout.default(for: .indoorRun))
    }

    func testResolverDoesNotApplyValidity() {
        // The resolver returns the stored custom as-is; validity is a
        // render-time concern applied by the caller.
        let custom = HUDLayout(id: "c1", name: "Bad", slots: [.pace, .speed, .elevation, .duration])
        let catalog = HUDLayoutCatalog(layouts: [custom])
        let defaults = WorkoutLayoutDefaults(assignments: [WorkoutType.indoorBike.rawValue: "c1"])
        let resolved = HUDLayoutResolver.activeLayout(
            for: .indoorBike, defaults: defaults, catalog: catalog
        )
        XCTAssertEqual(resolved.slots, [.pace, .speed, .elevation, .duration])
    }

    // MARK: - validated(for:)

    func testValidatedBlanksInvalidMetricsPreservingIndices() {
        // .pace is invalid for a bike, .speed/.heartRate stay.
        let layout = HUDLayout(id: "x", name: "X", slots: [.pace, .speed, .heartRate, .duration])
        let validated = layout.validated(for: .outdoorBike)
        XCTAssertEqual(validated.slots, [nil, .speed, .heartRate, .duration])
        XCTAssertEqual(validated.slots.count, layout.slots.count)
        XCTAssertEqual(validated.id, layout.id)
        XCTAssertEqual(validated.name, layout.name)
    }

    func testValidatedBlanksElevationIndoors() {
        let layout = HUDLayout(id: "x", name: "X", slots: [.heartRate, .elevation, .distance, .duration])
        let validated = layout.validated(for: .indoorRun)
        XCTAssertEqual(validated.slots, [.heartRate, nil, .distance, .duration])
    }

    func testValidatedKeepsAlreadyNilSlotsNil() {
        let layout = HUDLayout(id: "x", name: "X", slots: [.pace, nil, .heartRate, nil])
        let validated = layout.validated(for: .outdoorRun)
        XCTAssertEqual(validated.slots, [.pace, nil, .heartRate, nil])
    }

    func testValidatedIsIdentityWhenAllSlotsValid() {
        let layout = HUDLayout.default(for: .outdoorRun)
        XCTAssertEqual(layout.validated(for: .outdoorRun), layout)
    }

    func testEmptyStoreResolvesByteIdenticalToBuiltInDefaults() {
        // The byte-identical-behaviour guarantee for users with no customs:
        // empty catalog + empty defaults + validated == HUDLayout.default.
        let catalog = HUDLayoutCatalog()
        let defaults = WorkoutLayoutDefaults()
        for type in WorkoutType.allCases {
            let resolved = HUDLayoutResolver.activeLayout(
                for: type, defaults: defaults, catalog: catalog
            ).validated(for: type)
            XCTAssertEqual(resolved, HUDLayout.default(for: type), "type \(type.rawValue)")
        }
    }
}
