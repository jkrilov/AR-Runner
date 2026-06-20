// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct HUDLayout: Sendable, Codable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let slots: [MetricKind?]
    /// The grid *shape* (line count + items-per-line). Optional + additive:
    /// `nil` ⇒ the legacy `HUDGridConfig.standard` (`[2, 1, 1]`) so v0.6.4
    /// layouts encoded without this key decode and render unchanged. The
    /// pixel geometry for a shape lives in `HUDGridDefinition`, never here.
    public let grid: HUDGridConfig?

    public init(id: String, name: String, slots: [MetricKind?], grid: HUDGridConfig? = nil) {
        self.id = id
        self.name = name
        self.slots = slots
        self.grid = grid
    }

    /// The resolved grid shape — the explicit `grid` when present, otherwise
    /// the legacy `standard` shape. Use this (never `grid` directly) so the
    /// `nil`-means-standard contract is honoured everywhere.
    public var resolvedGrid: HUDGridConfig { grid ?? .standard }

    public static func minimalRun() -> HUDLayout {
        HUDLayout(
            id: "minimal-run",
            name: "Minimal Run",
            slots: [.pace, .heartRate, nil, .duration]
        )
    }

    public static func balancedRun() -> HUDLayout {
        HUDLayout(
            id: "balanced-run",
            name: "Balanced Run",
            slots: [.pace, .heartRate, .distance, .duration]
        )
    }

    public static func telemetryRun() -> HUDLayout {
        HUDLayout(
            id: "telemetry-run",
            name: "Telemetry Run",
            slots: [.pace, .heartRate, .distance, .cadence, .duration, .elevation]
        )
    }

    public static func curatedPresets() -> [HUDLayout] {
        [minimalRun(), balancedRun(), telemetryRun()]
    }

    /// The code-defined default layout for a given workout type (v0.6.0).
    ///
    /// Reconciled defaults (Killian UX + Weiss HUD): cycling surfaces `.speed`
    /// (never `.pace`); indoor variants carry no `.elevation` (no GPS, no
    /// barometric gain worth showing) and substitute `.cadence` / `.energy`
    /// where `.distance` is unavailable or uninteresting.
    public static func `default`(for type: WorkoutType) -> HUDLayout {
        switch (type.activity, type.environment) {
        case (.running, .outdoor):
            return HUDLayout(
                id: "default-outdoor-run",
                name: "Outdoor Run",
                slots: [.pace, .heartRate, .distance, .duration]
            )
        case (.running, .indoor):
            return HUDLayout(
                id: "default-indoor-run",
                name: "Indoor Run",
                slots: [.pace, .heartRate, .cadence, .duration]
            )
        case (.walking, .outdoor):
            return HUDLayout(
                id: "default-outdoor-walk",
                name: "Outdoor Walk",
                slots: [.pace, .heartRate, .distance, .duration]
            )
        case (.walking, .indoor):
            return HUDLayout(
                id: "default-indoor-walk",
                name: "Indoor Walk",
                slots: [.duration, .heartRate, .distance, .energy]
            )
        case (.cycling, .outdoor):
            return HUDLayout(
                id: "default-outdoor-bike",
                name: "Outdoor Bike",
                slots: [.speed, .heartRate, .distance, .duration]
            )
        case (.cycling, .indoor):
            return HUDLayout(
                id: "default-indoor-bike",
                name: "Indoor Bike",
                slots: [.cadence, .heartRate, .duration, .energy]
            )
        }
    }
}
