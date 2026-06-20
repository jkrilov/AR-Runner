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

    /// The framebuffer width budget (px) for the tight line-1-right slot of a
    /// grid: the right slot's text is right-anchored at `textX` and grows
    /// toward x = 0, so `textX` is the usable width before it runs off-panel.
    ///
    /// - TODO(bench): calibrate line-1 width threshold against real glyph
    ///   advances on hardware — this reuses the anchor as a conservative proxy.
    public static func line1RightBudget(grid: HUDGridDefinition = .standard4) -> Int {
        guard grid.slots.indices.contains(line1RightIndex) else { return 0 }
        return Int(grid.slots[line1RightIndex].textX)
    }

    /// Layout-slot index of the line-1-right slot — the horizontally tightest
    /// slot in `standard4` (it shares line 1 with the larger primary metric).
    public static let line1RightIndex = 1

    /// Slot indices whose sample value may be cut off on the glasses, as a
    /// best-effort, non-blocking hint. Only the line-1-right slot is checked:
    /// per the rendering plan it is the one tight horizontal budget, while the
    /// other slots have ample room. Returns an empty array when nothing is at
    /// risk (including when the slot is empty or out of range).
    public static func widthWarningSlots(
        for layout: HUDLayout,
        grid: HUDGridDefinition = .standard4,
        system: UnitSystem
    ) -> [Int] {
        let index = line1RightIndex
        guard layout.slots.indices.contains(index),
              grid.slots.indices.contains(index),
              let metric = layout.slots[index] else {
            return []
        }
        let value = sampleValue(for: metric, system: system)
        let width = ALookFontMetrics.width(of: value, fontSize: grid.slots[index].font)
        return width > line1RightBudget(grid: grid) ? [index] : []
    }
}
