// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension HUDLayout {
    /// A copy of this layout with every slot whose `MetricKind` isn't valid
    /// for the given workout type blanked to `nil`.
    ///
    /// Slot **indices and count are preserved** — a metric that doesn't apply
    /// (e.g. `.pace` on a bike, `.elevation` indoors) becomes an empty slot in
    /// place rather than being compacted out, so the fixed-slot grid geometry
    /// the render path depends on stays intact. Slots that are already `nil`
    /// stay `nil`. Applied by callers at render time (not inside the resolver),
    /// matching the rendering plan: the catalog stores the user's intent as-is
    /// and validity is a display-time concern.
    public func validated(for type: WorkoutType) -> HUDLayout {
        let validatedSlots = slots.map { slot -> MetricKind? in
            guard let metric = slot else { return nil }
            return metric.isValid(for: type) ? metric : nil
        }
        return HUDLayout(id: id, name: name, slots: validatedSlots)
    }
}
