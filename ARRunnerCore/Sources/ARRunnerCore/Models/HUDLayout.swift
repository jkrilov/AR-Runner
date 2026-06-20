// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct HUDLayout: Sendable, Codable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let slots: [MetricKind?]

    public init(id: String, name: String, slots: [MetricKind?]) {
        self.id = id
        self.name = name
        self.slots = slots
    }

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
