// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import XCTest
@testable import ARRunnerPhone

/// Exercises the pure transformation logic + mutation/sync wiring of the
/// custom-HUD Phase B editor view model. Phone tests build in CI but don't
/// execute, so these are kept correct as a living spec.
@MainActor
final class HUDLayoutsViewModelTests: XCTestCase {

    /// Captures the layouts/defaults pushed to the "watch".
    private final class SpySync: HUDLayoutSyncing {
        var catalogs: [HUDLayoutCatalog] = []
        var defaults: [WorkoutLayoutDefaults] = []
        func sendLayoutCatalog(_ catalog: HUDLayoutCatalog) { catalogs.append(catalog) }
        func sendLayoutDefaults(_ d: WorkoutLayoutDefaults) { defaults.append(d) }
    }

    private func makeVM(
        catalog: HUDLayoutCatalog = HUDLayoutCatalog(),
        defaults: WorkoutLayoutDefaults = WorkoutLayoutDefaults()
    ) -> (HUDLayoutsViewModel, SpySync) {
        let spy = SpySync()
        let vm = HUDLayoutsViewModel(
            catalog: catalog, defaults: defaults, sync: spy, persistsToStore: false
        )
        return (vm, spy)
    }

    private func layout(_ id: String, _ name: String, _ slots: [MetricKind?] = [.pace, .heartRate, .distance, .duration]) -> HUDLayout {
        HUDLayout(id: id, name: name, slots: slots)
    }

    // MARK: - Auto-naming

    func test_nextAutoName_picksFirstFreeIndex() {
        XCTAssertEqual(HUDLayoutsViewModel.nextAutoName(existingNames: []), "Custom Layout 1")
        XCTAssertEqual(
            HUDLayoutsViewModel.nextAutoName(existingNames: ["Custom Layout 1", "Custom Layout 2"]),
            "Custom Layout 3"
        )
        // Gaps are filled by the lowest free index.
        XCTAssertEqual(
            HUDLayoutsViewModel.nextAutoName(existingNames: ["Custom Layout 2"]),
            "Custom Layout 1"
        )
    }

    func test_uniqueName_disambiguatesCollisions() {
        XCTAssertEqual(HUDLayoutsViewModel.uniqueName(base: "Tempo", existingNames: []), "Tempo")
        XCTAssertEqual(HUDLayoutsViewModel.uniqueName(base: "Tempo", existingNames: ["Tempo"]), "Tempo 2")
        XCTAssertEqual(
            HUDLayoutsViewModel.uniqueName(base: "Tempo", existingNames: ["Tempo", "Tempo 2"]),
            "Tempo 3"
        )
    }

    // MARK: - Cap

    func test_canAdd_enforcesCap() {
        XCTAssertTrue(HUDLayoutsViewModel.canAdd(count: 0))
        XCTAssertTrue(HUDLayoutsViewModel.canAdd(count: HUDLayoutsViewModel.maxCustomLayouts - 1))
        XCTAssertFalse(HUDLayoutsViewModel.canAdd(count: HUDLayoutsViewModel.maxCustomLayouts))
    }

    func test_upsert_atCap_rejectsNewButAllowsReplace() {
        let full = (0..<HUDLayoutsViewModel.maxCustomLayouts).map { layout("c\($0)", "L\($0)") }
        let (vm, spy) = makeVM(catalog: HUDLayoutCatalog(layouts: full))
        XCTAssertFalse(vm.canAddCustom)

        vm.upsert(layout("new", "Nope"))
        XCTAssertEqual(vm.catalog.layouts.count, HUDLayoutsViewModel.maxCustomLayouts)
        XCTAssertTrue(spy.catalogs.isEmpty, "rejected new layout must not sync")

        // Replacing an existing id is still allowed at the cap.
        vm.upsert(layout("c0", "Renamed"))
        XCTAssertEqual(vm.catalog.layouts.first { $0.id == "c0" }?.name, "Renamed")
        XCTAssertEqual(spy.catalogs.count, 1)
    }

    // MARK: - Slot building (no duplicates)

    func test_updatedSlots_clearsDuplicateMetric() {
        let slots: [MetricKind?] = [.pace, .heartRate, .distance, .duration]
        // Putting pace into slot 2 must clear it from slot 0.
        let result = HUDLayoutsViewModel.updatedSlots(slots, setting: .pace, at: 2)
        XCTAssertEqual(result, [nil, .heartRate, .pace, .duration])
    }

    func test_updatedSlots_nilEmptiesSlotOnly() {
        let slots: [MetricKind?] = [.pace, .heartRate, .distance, .duration]
        XCTAssertEqual(
            HUDLayoutsViewModel.updatedSlots(slots, setting: nil, at: 1),
            [.pace, nil, .distance, .duration]
        )
    }

    func test_makeLayout_blankNameFallsBackToAutoName() {
        let made = HUDLayoutsViewModel.makeLayout(
            id: "x", name: "   ", slots: [.pace, nil, nil, nil], existingNames: ["Custom Layout 1"]
        )
        XCTAssertEqual(made.name, "Custom Layout 2")
    }

    func test_makeLayout_trimsName() {
        let made = HUDLayoutsViewModel.makeLayout(id: "x", name: "  Tempo  ", slots: [])
        XCTAssertEqual(made.name, "Tempo")
    }

    // MARK: - Duplicate

    func test_duplicate_clonesSlotsWithFreshIDAndCopyName() {
        let source = layout("preset", "Balanced Run")
        let copy = HUDLayoutsViewModel.duplicate(source, existingNames: ["Balanced Run Copy"])
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.slots, source.slots)
        XCTAssertEqual(copy.name, "Balanced Run Copy 2")
    }

    func test_duplicateFromPreset_appendsAndSyncs() {
        let (vm, spy) = makeVM()
        vm.duplicate(HUDLayout.balancedRun())
        XCTAssertEqual(vm.catalog.layouts.count, 1)
        XCTAssertEqual(vm.catalog.layouts.first?.name, "Balanced Run Copy")
        XCTAssertEqual(spy.catalogs.count, 1)
    }

    // MARK: - Assignments

    func test_updatedAssignments_setAndClear() {
        var a = HUDLayoutsViewModel.updatedAssignments([:], setting: "c1", for: .outdoorRun)
        XCTAssertEqual(a["running"], "c1")
        a = HUDLayoutsViewModel.updatedAssignments(a, setting: nil, for: .outdoorRun)
        XCTAssertNil(a["running"])
    }

    func test_assign_persistsAndSyncs() {
        let (vm, spy) = makeVM(catalog: HUDLayoutCatalog(layouts: [layout("c1", "Tempo")]))
        vm.assign(layoutID: "c1", to: .indoorBike)
        XCTAssertEqual(vm.defaults.layoutID(for: .indoorBike), "c1")
        XCTAssertEqual(vm.assignedLayout(for: .indoorBike)?.id, "c1")
        XCTAssertEqual(spy.defaults.count, 1)
    }

    // MARK: - Delete prunes assignments

    func test_deleteCustom_prunesReferencingAssignments() {
        let (vm, spy) = makeVM(
            catalog: HUDLayoutCatalog(layouts: [layout("c1", "Tempo")]),
            defaults: WorkoutLayoutDefaults(assignments: ["running": "c1", "cycling": "c1"])
        )
        vm.deleteCustom(at: IndexSet(integer: 0))
        XCTAssertTrue(vm.catalog.layouts.isEmpty)
        XCTAssertTrue(vm.defaults.assignments.isEmpty)
        XCTAssertEqual(spy.catalogs.count, 1)
        XCTAssertEqual(spy.defaults.count, 1, "pruned assignments must also sync")
    }

    // MARK: - Validity warning

    func test_invalidMetrics_flagsTypeMismatches() {
        // pace + elevation on an indoor bike: pace invalid (cycling),
        // elevation invalid (indoor), distance invalid (indoor cycling).
        let l = layout("c1", "Mixed", [.pace, .elevation, .distance, .heartRate])
        let invalid = HUDLayoutsViewModel.invalidMetrics(in: l, for: .indoorBike)
        XCTAssertEqual(invalid, [.pace, .elevation, .distance])
    }

    func test_invalidMetrics_emptyWhenAllValid() {
        let l = layout("c1", "Run", [.pace, .heartRate, .distance, .duration])
        XCTAssertTrue(HUDLayoutsViewModel.invalidMetrics(in: l, for: .outdoorRun).isEmpty)
    }

    // MARK: - Summaries / labels

    func test_slotSummary_joinsFilledSlots() {
        XCTAssertEqual(
            HUDLayoutsViewModel.slotSummary(layout("c1", "L", [.pace, .heartRate, nil, .duration])),
            "Pace · HR · Time"
        )
        XCTAssertEqual(
            HUDLayoutsViewModel.slotSummary(layout("c1", "L", [nil, nil, nil, nil])),
            "Empty"
        )
    }

    func test_displayLabel_coversAllMetrics() {
        for metric in MetricKind.allCases {
            XCTAssertFalse(HUDLayoutsViewModel.displayLabel(for: metric).isEmpty)
            XCTAssertFalse(HUDLayoutsViewModel.shortLabel(for: metric).isEmpty)
        }
    }

    func test_iconSymbol_coversAllMetricsAndIconFlag() {
        for metric in MetricKind.allCases {
            XCTAssertFalse(HUDLayoutsViewModel.iconSymbol(for: metric).isEmpty)
        }
        // The four metrics with real preloaded glasses glyphs render full
        // strength; the rest are muted in the preview.
        for metric in [MetricKind.duration, .heartRate, .distance, .pace] {
            XCTAssertTrue(HUDLayoutsViewModel.hasGlassesIcon(for: metric))
        }
        for metric in [MetricKind.speed, .cadence, .energy, .elevation, .heading] {
            XCTAssertFalse(HUDLayoutsViewModel.hasGlassesIcon(for: metric))
        }
    }

    func test_headingLabels() {
        XCTAssertEqual(HUDLayoutsViewModel.displayLabel(for: .heading), "Compass")
        XCTAssertEqual(HUDLayoutsViewModel.shortLabel(for: .heading), "Dir")
    }

    // MARK: - Variable grid configuration (v0.6.5)

    func test_resizedSlots_padsTruncatesPreservingOrder() {
        let slots: [MetricKind?] = [.pace, .heartRate, .distance, .duration]
        XCTAssertEqual(
            HUDLayoutsViewModel.resizedSlots(slots, toSlotCount: 6),
            [.pace, .heartRate, .distance, .duration, nil, nil]
        )
        XCTAssertEqual(
            HUDLayoutsViewModel.resizedSlots(slots, toSlotCount: 2),
            [.pace, .heartRate]
        )
        XCTAssertEqual(HUDLayoutsViewModel.resizedSlots(slots, toSlotCount: 4), slots)
    }

    func test_updatedGrid_lineCountClampsAndPreservesItems() {
        let config = HUDGridConfig(lines: [2, 1, 1])
        // Grow to 4 lines — added line defaults to 1 item.
        XCTAssertEqual(HUDLayoutsViewModel.updatedGrid(config, lineCount: 4).lines, [2, 1, 1, 1])
        // Shrink to 2 lines — keeps the first two.
        XCTAssertEqual(HUDLayoutsViewModel.updatedGrid(config, lineCount: 2).lines, [2, 1])
        // Out-of-range is clamped into 2…4.
        XCTAssertEqual(HUDLayoutsViewModel.updatedGrid(config, lineCount: 9).lines.count, 4)
        XCTAssertEqual(HUDLayoutsViewModel.updatedGrid(config, lineCount: 1).lines.count, 2)
    }

    func test_updatedGrid_itemsPerLine() {
        let config = HUDGridConfig(lines: [2, 1, 1])
        XCTAssertEqual(HUDLayoutsViewModel.updatedGrid(config, items: 2, atLine: 1).lines, [2, 2, 1])
        XCTAssertEqual(HUDLayoutsViewModel.updatedGrid(config, items: 1, atLine: 0).lines, [1, 1, 1])
        // Out-of-bounds line index is a no-op.
        XCTAssertEqual(HUDLayoutsViewModel.updatedGrid(config, items: 2, atLine: 9).lines, [2, 1, 1])
    }

    func test_makeLayout_storesGridAndNormalizesSlots() {
        // A non-standard shape is stored as an explicit grid; slots are
        // normalised to the grid's slot count.
        let made = HUDLayoutsViewModel.makeLayout(
            id: "g", name: "Six", slots: [.pace, .heartRate],
            grid: HUDGridConfig(lines: [2, 2, 2])
        )
        XCTAssertEqual(made.grid?.lines, [2, 2, 2])
        XCTAssertEqual(made.slots.count, 6)
        XCTAssertEqual(made.slots[0], .pace)
        XCTAssertEqual(made.slots[1], .heartRate)
    }

    func test_makeLayout_standardShapeStoresNilGrid() {
        // The legacy [2,1,1] shape stores `nil` so v0.6.4 layouts stay
        // byte-identical and the wire blob stays small.
        let made = HUDLayoutsViewModel.makeLayout(
            id: "s", name: "Std", slots: [.pace, .heartRate, .distance, .duration],
            grid: HUDGridConfig(lines: [2, 1, 1])
        )
        XCTAssertNil(made.grid)
        XCTAssertEqual(made.resolvedGrid, .standard)
    }
}
