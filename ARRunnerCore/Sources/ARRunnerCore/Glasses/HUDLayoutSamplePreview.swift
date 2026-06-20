// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Synthetic sample values + a conservative width heuristic for the phone's
/// static HUD-layout preview (custom-HUD Phase B).
///
/// The phone editor paints an amber-on-black approximation of the 304×256
/// Engo 2 panel so the user can see metric placement before saving. Those
/// preview strings are *representative synthetic values* — never live data —
/// and the width check is a best-effort "this may clip on glasses" hint, not
/// a hard constraint (saving is never blocked).
///
/// Pure Foundation so the value table and the width heuristic stay exercisable
/// from the Linux `ARRunnerCoreTests` suite. The phone view layer renders these
/// strings; it does not re-derive them.
public enum HUDLayoutSamplePreview {

    /// A representative synthetic display value for `metric`, **without** a
    /// unit suffix, in the given measurement system. Mirrors what the glasses
    /// render (icon + bare value), so this is also what the width heuristic
    /// measures.
    ///
    /// Values are illustrative (a 5:30/km run at 4.2 km / 23:18) — chosen to
    /// look plausible in the editor, not to reflect any real workout.
    public static func sampleValue(for metric: MetricKind, system: UnitSystem) -> String {
        switch metric {
        case .heartRate:
            return "152"
        case .duration:
            return "23:18"
        case .cadence:
            return "168"
        case .energy:
            return "320"
        case .pace:
            return system == .metric ? "5:30" : "8:51"
        case .distance:
            return system == .metric ? "4.20" : "2.61"
        case .speed:
            return system == .metric ? "27.4" : "17.0"
        case .elevation:
            return system == .metric ? "152" : "499"
        case .heading:
            // System-independent bearing sample (cardinal + degrees), matching
            // `RunMetricFormatting.formatHeading` output shape.
            return "NE 045°"
        }
    }

    /// The sample value with its unit label suffixed, e.g. `"152 bpm"`,
    /// `"5:30/km"`, `"168 spm"`. `type` resolves the activity-dependent
    /// cadence label (`spm` vs `rpm`); it defaults to an outdoor run since the
    /// preview is not bound to a single workout type. `.duration` carries no
    /// suffix (it reads as a clock). Pace's `/km`-style label joins without a
    /// space so it reads `"5:30/km"` rather than `"5:30 /km"`.
    public static func sampleValueWithUnit(
        for metric: MetricKind,
        type: WorkoutType = .outdoorRun,
        system: UnitSystem
    ) -> String {
        let value = sampleValue(for: metric, system: system)
        let unit = metric.unitLabel(for: type, in: system)
        if unit.isEmpty { return value }
        return unit.hasPrefix("/") ? value + unit : value + " " + unit
    }

    /// The framebuffer width budget (px) for a right-anchored slot: its text
    /// is right-anchored at `textX` and grows toward x = 0, so `textX` is the
    /// usable width before it runs off-panel.
    ///
    /// - TODO(bench): calibrate the width threshold against real glyph advances
    ///   on hardware — this reuses the anchor as a conservative proxy.
    public static func budget(forSlotAt index: Int, grid: HUDGridDefinition) -> Int {
        guard grid.slots.indices.contains(index) else { return 0 }
        return Int(grid.slots[index].textX)
    }

    /// Flat (row-major) slot indices that are the *right* item of a 2-item
    /// line — the horizontally tightest slots, where two metrics share the
    /// line. These are the only slots the width hint checks; 1-item lines and
    /// left slots have ample room.
    public static func twoItemRightSlotIndices(for config: HUDGridConfig) -> [Int] {
        var result: [Int] = []
        var flat = 0
        for items in config.validated().lines {
            if items == 2 { result.append(flat + 1) }
            flat += items
        }
        return result
    }

    /// Layout-slot index of the line-1-right slot in the legacy `standard4`
    /// shape — retained for callers/tests pinned to the fixed 4-slot grid.
    public static let line1RightIndex = 1

    /// Legacy convenience: the line-1-right budget for the standard4 grid.
    public static func line1RightBudget(grid: HUDGridDefinition = .standard4) -> Int {
        budget(forSlotAt: line1RightIndex, grid: grid)
    }

    /// Slot indices whose sample value may be cut off on the glasses, as a
    /// best-effort, non-blocking hint. Every 2-item line's right slot is
    /// checked (the tight horizontal budgets); 1-item lines and left slots have
    /// room to spare. Returns an empty array when nothing is at risk (including
    /// empty or out-of-range slots).
    public static func widthWarningSlots(
        for layout: HUDLayout,
        system: UnitSystem
    ) -> [Int] {
        let config = layout.resolvedGrid
        let grid = HUDGridDefinition.make(for: config)
        var flagged: [Int] = []
        for index in twoItemRightSlotIndices(for: config) {
            guard layout.slots.indices.contains(index),
                  grid.slots.indices.contains(index),
                  let metric = layout.slots[index] else { continue }
            let value = sampleValue(for: metric, system: system)
            let width = ALookFontMetrics.width(of: value, fontSize: grid.slots[index].font)
            if width > budget(forSlotAt: index, grid: grid) { flagged.append(index) }
        }
        return flagged
    }
}
