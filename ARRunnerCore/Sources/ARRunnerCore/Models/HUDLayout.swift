import Foundation

public struct HUDLayout: Sendable, Codable, Identifiable, Equatable {
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
}
