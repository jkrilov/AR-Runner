// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation

/// Abstracts the watch push so `HUDLayoutsViewModel` can be unit-tested
/// without a live `WCSession`. `WatchConnectivityService` conforms with its
/// existing `sendLayoutCatalog(_:)` / `sendLayoutDefaults(_:)` (added inert in
/// Phase A — Phase B is the first caller).
protocol HUDLayoutSyncing: AnyObject {
    func sendLayoutCatalog(_ catalog: HUDLayoutCatalog)
    func sendLayoutDefaults(_ defaults: WorkoutLayoutDefaults)
}

extension WatchConnectivityService: HUDLayoutSyncing {}

/// Drives the phone-side custom HUD layout editor (custom-HUD Phase B).
///
/// Owns the in-memory `HUDLayoutCatalog` (user customs) and
/// `WorkoutLayoutDefaults` (per-workout-type assignments). Every mutation
/// persists to the App Group `HUDLayoutStore` and pushes to the paired watch
/// via `HUDLayoutSyncing`, so the change is durable and applied at the watch's
/// **next** workout start (never mid-run — the watch resolves once at start).
///
/// The pure transformation logic — auto-naming, duplicate-name handling, the
/// 16-layout cap, building a layout from slot selections, assignment updates,
/// and the per-type validity warning — is factored into `static` methods so it
/// is testable without touching the store, the sync link, or the UI.
@MainActor
@Observable
final class HUDLayoutsViewModel {

    /// Maximum number of user-authored custom layouts (Richards' cap keeps the
    /// synced App Group blob a few KB, well within `applicationContext`).
    static let maxCustomLayouts = 16

    private(set) var catalog: HUDLayoutCatalog
    private(set) var defaults: WorkoutLayoutDefaults

    private let sync: HUDLayoutSyncing?
    /// When `false`, mutations skip the App Group write (used by unit tests so
    /// they don't touch shared `UserDefaults`). Sync is still driven through
    /// the injected `HUDLayoutSyncing` mock.
    private let persistsToStore: Bool

    init(
        catalog: HUDLayoutCatalog,
        defaults: WorkoutLayoutDefaults,
        sync: HUDLayoutSyncing?,
        persistsToStore: Bool = true
    ) {
        self.catalog = catalog
        self.defaults = defaults
        self.sync = sync
        self.persistsToStore = persistsToStore
    }

    /// Production initialiser: seeds from the App Group store and pushes
    /// through the shared WCSession mirror.
    convenience init() {
        self.init(
            catalog: HUDLayoutStore.currentCatalog,
            defaults: HUDLayoutStore.currentDefaults,
            sync: ARRunnerPhoneEnvironment.shared.mirror
        )
    }

    // MARK: - Derived state

    /// The read-only curated system presets shown in the list's first section.
    var presets: [HUDLayout] { HUDLayout.curatedPresets() }

    /// Whether another custom layout can be created (cap not yet reached).
    var canAddCustom: Bool {
        Self.canAdd(count: catalog.layouts.count)
    }

    // MARK: - Mutations (persist + sync)

    /// Insert a new custom layout or replace an existing one (matched by `id`).
    /// A brand-new layout is rejected silently when the cap is already reached
    /// — callers gate creation on `canAddCustom`.
    func upsert(_ layout: HUDLayout) {
        if let index = catalog.layouts.firstIndex(where: { $0.id == layout.id }) {
            catalog.layouts[index] = layout
        } else if canAddCustom {
            catalog.layouts.append(layout)
        } else {
            return
        }
        persistCatalog()
    }

    /// Create an editable custom copy of a (read-only) preset, respecting the
    /// cap. The copy gets a fresh `id` and a de-duplicated "… Copy" name.
    func duplicate(_ source: HUDLayout) {
        guard canAddCustom else { return }
        let copy = Self.duplicate(source, existingNames: catalog.layouts.map(\.name))
        catalog.layouts.append(copy)
        persistCatalog()
    }

    /// Delete custom layouts at the given offsets and drop any per-type
    /// assignment that referenced them (the resolver would fall back to the
    /// built-in default anyway, but this keeps the synced blob tidy).
    func deleteCustom(at offsets: IndexSet) {
        let removedIDs = Set(offsets.compactMap { catalog.layouts.indices.contains($0) ? catalog.layouts[$0].id : nil })
        catalog.layouts = catalog.layouts.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        let prunedAssignments = defaults.assignments.filter { !removedIDs.contains($0.value) }
        let assignmentsChanged = prunedAssignments.count != defaults.assignments.count
        defaults.assignments = prunedAssignments
        persistCatalog()
        if assignmentsChanged { persistDefaults() }
    }

    /// Assign `layoutID` (a custom layout) as the default for `type`, or pass
    /// `nil` to revert that type to its built-in default.
    func assign(layoutID: String?, to type: WorkoutType) {
        defaults.assignments = Self.updatedAssignments(
            defaults.assignments, setting: layoutID, for: type
        )
        persistDefaults()
    }

    /// A fresh, unsaved draft layout seeded from the user's default workout
    /// type, named "Custom Layout N". Not yet inserted — `upsert` commits it.
    func makeDraft() -> HUDLayout {
        let seed = HUDLayout.default(for: WorkoutTypePreference.current)
        return HUDLayout(
            id: UUID().uuidString,
            name: Self.nextAutoName(existingNames: catalog.layouts.map(\.name)),
            slots: seed.slots,
            grid: seed.grid
        )
    }

    /// The custom layout currently assigned to `type`, or `nil` when it uses
    /// the built-in default.
    func assignedLayout(for type: WorkoutType) -> HUDLayout? {
        guard let id = defaults.layoutID(for: type) else { return nil }
        return catalog.layout(id: id)
    }

    // MARK: - Persistence

    private func persistCatalog() {
        if persistsToStore { HUDLayoutStore.currentCatalog = catalog }
        sync?.sendLayoutCatalog(catalog)
    }

    private func persistDefaults() {
        if persistsToStore { HUDLayoutStore.currentDefaults = defaults }
        sync?.sendLayoutDefaults(defaults)
    }

    // MARK: - Pure logic (testable)

    static func canAdd(count: Int, max: Int = maxCustomLayouts) -> Bool {
        count < max
    }

    /// "Custom Layout N" with the smallest N ≥ 1 that isn't already taken.
    static func nextAutoName(existingNames: [String]) -> String {
        let taken = Set(existingNames)
        var index = 1
        while taken.contains("Custom Layout \(index)") { index += 1 }
        return "Custom Layout \(index)"
    }

    /// Disambiguate `base` against `existingNames`, appending " 2", " 3", …
    /// until unique. Returns `base` unchanged when it is already free.
    static func uniqueName(base: String, existingNames: [String]) -> String {
        let taken = Set(existingNames)
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    /// Set `metric` at `index`, clearing any *other* slot holding the same
    /// metric so no metric appears twice (Killian's no-duplicate rule). Passing
    /// `nil` simply empties the slot.
    static func updatedSlots(
        _ slots: [MetricKind?],
        setting metric: MetricKind?,
        at index: Int
    ) -> [MetricKind?] {
        guard slots.indices.contains(index) else { return slots }
        var result = slots
        if let metric {
            for other in result.indices where other != index && result[other] == metric {
                result[other] = nil
            }
        }
        result[index] = metric
        return result
    }

    /// Build a custom layout from an edited name + slot selection. A blank or
    /// whitespace-only name falls back to an auto-name so a layout is never
    /// nameless.
    static func makeLayout(
        id: String,
        name: String,
        slots: [MetricKind?],
        grid: HUDGridConfig? = nil,
        existingNames: [String] = []
    ) -> HUDLayout {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? nextAutoName(existingNames: existingNames) : trimmed
        // Normalise slot count to the grid shape so the catalog never stores a
        // layout whose slot array disagrees with its grid (the renderer relies
        // on slotCount == slots.count).
        let resolvedGrid = (grid ?? .standard).validated()
        let normalizedSlots = resizedSlots(slots, toSlotCount: resolvedGrid.slotCount)
        // A nil grid is stored only when the shape is exactly the legacy
        // standard4 — keeps v0.6.4 layouts byte-identical and the wire blob
        // small for the common case.
        let storedGrid: HUDGridConfig? =
            resolvedGrid.lines == HUDGridConfig.standard.lines ? nil : resolvedGrid
        return HUDLayout(id: id, name: resolved, slots: normalizedSlots, grid: storedGrid)
    }

    // MARK: - Grid configuration (testable)

    /// Pad (with `nil`) or truncate `slots` so its count matches `slotCount`,
    /// preserving existing selections in order. Used when the grid shape
    /// changes so metric assignments survive add/remove of lines or items.
    static func resizedSlots(_ slots: [MetricKind?], toSlotCount slotCount: Int) -> [MetricKind?] {
        if slots.count == slotCount { return slots }
        if slots.count > slotCount { return Array(slots.prefix(slotCount)) }
        return slots + Array(repeating: nil, count: slotCount - slots.count)
    }

    /// Change the grid's line count to `lineCount` (clamped 2…4), preserving
    /// each surviving line's items-per-line. Added lines default to 1 item.
    static func updatedGrid(_ config: HUDGridConfig, lineCount: Int) -> HUDGridConfig {
        let target = min(4, max(2, lineCount))
        var lines = config.lines
        if lines.count > target {
            lines = Array(lines.prefix(target))
        } else if lines.count < target {
            lines += Array(repeating: 1, count: target - lines.count)
        }
        return HUDGridConfig(lines: lines).validated()
    }

    /// Set the number of items (1 or 2) on the line at `lineIndex`.
    static func updatedGrid(_ config: HUDGridConfig, items: Int, atLine lineIndex: Int) -> HUDGridConfig {
        guard config.lines.indices.contains(lineIndex) else { return config }
        var lines = config.lines
        lines[lineIndex] = min(2, max(1, items))
        return HUDGridConfig(lines: lines).validated()
    }

    /// An editable copy of `source` with a fresh `id` and a unique "… Copy"
    /// name.
    static func duplicate(_ source: HUDLayout, existingNames: [String]) -> HUDLayout {
        HUDLayout(
            id: UUID().uuidString,
            name: uniqueName(base: "\(source.name) Copy", existingNames: existingNames),
            slots: source.slots,
            grid: source.grid
        )
    }

    /// Apply (or clear) a per-type assignment. `nil` removes the key so the
    /// type resolves to its built-in default rather than persisting an empty
    /// string.
    static func updatedAssignments(
        _ assignments: [String: String],
        setting layoutID: String?,
        for type: WorkoutType
    ) -> [String: String] {
        var result = assignments
        if let layoutID {
            result[type.rawValue] = layoutID
        } else {
            result.removeValue(forKey: type.rawValue)
        }
        return result
    }

    /// Metrics in `layout` that aren't meaningful for `type` — they render as
    /// `--` on the glasses. Drives the warn-not-block caption on the per-type
    /// default rows. Order follows slot order; duplicates are de-duplicated.
    static func invalidMetrics(in layout: HUDLayout, for type: WorkoutType) -> [MetricKind] {
        var seen = Set<MetricKind>()
        var result: [MetricKind] = []
        for case let metric? in layout.slots where !metric.isValid(for: type) {
            if seen.insert(metric).inserted { result.append(metric) }
        }
        return result
    }

    // MARK: - Display helpers

    /// Human-readable label for a metric, used in the picker + slot summaries.
    static func displayLabel(for metric: MetricKind) -> String {
        switch metric {
        case .heartRate: return "Heart Rate"
        case .pace:      return "Pace"
        case .distance:  return "Distance"
        case .duration:  return "Duration"
        case .cadence:   return "Cadence"
        case .elevation: return "Elevation"
        case .energy:    return "Energy"
        case .speed:     return "Speed"
        case .heading:   return "Compass"
        }
    }

    /// Short label for compact slot summaries, e.g. "Pace · HR · Dist".
    static func shortLabel(for metric: MetricKind) -> String {
        switch metric {
        case .heartRate: return "HR"
        case .pace:      return "Pace"
        case .distance:  return "Dist"
        case .duration:  return "Time"
        case .cadence:   return "Cad"
        case .elevation: return "Elev"
        case .energy:    return "kcal"
        case .speed:     return "Speed"
        case .heading:   return "Dir"
        }
    }

    /// "Pace · HR · Dist · Time" summary of a layout's filled slots, or
    /// "Empty" when nothing is assigned.
    static func slotSummary(_ layout: HUDLayout) -> String {
        let filled = layout.slots.compactMap { $0 }.map(shortLabel(for:))
        return filled.isEmpty ? "Empty" : filled.joined(separator: " · ")
    }

    // MARK: - Preview icons

    /// SF Symbol for a metric in the phone editor preview. Mirrors the real
    /// outdoor-run HUD: the four metrics with preloaded ALooK glasses glyphs
    /// (`duration`, `heartRate`, `distance`, `pace`) render at full strength;
    /// the rest get a representative symbol shown muted (see
    /// `hasGlassesIcon(for:)`) so the preview never over-promises an on-glass
    /// icon that won't exist.
    static func iconSymbol(for metric: MetricKind) -> String {
        switch metric {
        case .duration:  return "stopwatch"
        case .heartRate: return "heart.fill"
        case .distance:  return "ruler"
        case .pace:      return "speedometer"
        case .speed:     return "gauge.with.dots.needle.67percent"
        case .cadence:   return "metronome"
        case .energy:    return "flame.fill"
        case .elevation: return "mountain.2.fill"
        case .heading:   return "location.north.line"
        }
    }

    /// Whether `metric` has a real preloaded icon on the glasses. Drives the
    /// preview's full-strength vs. muted icon treatment.
    static func hasGlassesIcon(for metric: MetricKind) -> Bool {
        switch metric {
        case .duration, .heartRate, .distance, .pace:
            return true
        case .speed, .cadence, .energy, .elevation, .heading:
            return false
        }
    }
}
