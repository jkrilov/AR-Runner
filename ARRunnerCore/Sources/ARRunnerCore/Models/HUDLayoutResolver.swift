// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Resolves which `HUDLayout` to render for a workout type, given the user's
/// per-type assignments and their custom-layout catalog.
///
/// Pure (no I/O) so it stays exercisable from the Linux `ARRunnerCoreTests`
/// suite and so the watch render path can call it without touching the App
/// Group store inline. The store reads happen at the call site; the resolution
/// rule itself is a deterministic function of its inputs.
///
/// Resolution order:
///   1. If the user assigned a custom layout for `workoutType` *and* that
///      layout still exists in `catalog`, return it.
///   2. Otherwise (no assignment, or a dangling reference to a deleted
///      layout), fall through to the code-defined `HUDLayout.default(for:)`.
///
/// Validity (`HUDLayout.validated(for:)`) is intentionally **not** applied
/// here — callers apply it at render time so an unrenderable slot blanks to
/// `nil` without the resolver having to know about display rules.
public enum HUDLayoutResolver {
    public static func activeLayout(
        for workoutType: WorkoutType,
        defaults: WorkoutLayoutDefaults,
        catalog: HUDLayoutCatalog
    ) -> HUDLayout {
        if let id = defaults.layoutID(for: workoutType),
           let layout = catalog.layout(id: id) {
            return layout
        }
        return HUDLayout.default(for: workoutType)
    }
}
