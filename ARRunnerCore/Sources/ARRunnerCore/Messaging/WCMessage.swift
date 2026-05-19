// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum LifecycleEvent: Sendable, Codable, Equatable {
    case started(SportType)
    case paused
    case resumed
    case ended
}

public enum WCMessage: Sendable, Codable, Equatable {
    /// v1 — layoutConfig / workoutTick (per-metric) / workoutLifecycle.
    /// v2 — adds workoutSnapshot for the iPhone live mirror (v0.2 #3).
    /// v3 — adds glassesBattery for v0.4 phone-side battery indicator. Watch
    ///      forwards 0–100 percent from the Battery Service (0x180F / 0x2A19)
    ///      via transferUserInfo. Phone-optional: missing the iPhone never
    ///      blocks the watch.
    public static let currentSchemaVersion = 3

    case layoutConfig(HUDLayout)
    case workoutTick(WorkoutMetric)
    case workoutLifecycle(LifecycleEvent)
    case workoutSnapshot(WorkoutTickMessage)
    /// Glasses battery percentage (0–100) as reported by the standard
    /// Battery Service notification on the watch's BLE link.
    case glassesBattery(level: Int)

    public var schemaVersion: Int {
        Self.currentSchemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case layout
        case metric
        case lifecycleEvent
        case snapshot
        case batteryLevel
    }

    private enum Kind: String, Codable {
        case layoutConfig
        case workoutTick
        case workoutLifecycle
        case workoutSnapshot
        case glassesBattery
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)

        // Accept current and any earlier schema we still know how to decode.
        // Older peers simply never produce the newer cases so backward
        // compatibility is automatic.
        guard schemaVersion >= 1, schemaVersion <= Self.currentSchemaVersion else {
            throw WCMessageCodingError.unsupportedSchemaVersion(schemaVersion)
        }

        switch try container.decode(Kind.self, forKey: .kind) {
        case .layoutConfig:
            self = .layoutConfig(try container.decode(HUDLayout.self, forKey: .layout))
        case .workoutTick:
            self = .workoutTick(try container.decode(WorkoutMetric.self, forKey: .metric))
        case .workoutLifecycle:
            self = .workoutLifecycle(try container.decode(LifecycleEvent.self, forKey: .lifecycleEvent))
        case .workoutSnapshot:
            self = .workoutSnapshot(try container.decode(WorkoutTickMessage.self, forKey: .snapshot))
        case .glassesBattery:
            self = .glassesBattery(level: try container.decode(Int.self, forKey: .batteryLevel))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)

        switch self {
        case .layoutConfig(let layout):
            try container.encode(Kind.layoutConfig, forKey: .kind)
            try container.encode(layout, forKey: .layout)
        case .workoutTick(let metric):
            try container.encode(Kind.workoutTick, forKey: .kind)
            try container.encode(metric, forKey: .metric)
        case .workoutLifecycle(let event):
            try container.encode(Kind.workoutLifecycle, forKey: .kind)
            try container.encode(event, forKey: .lifecycleEvent)
        case .workoutSnapshot(let snapshot):
            try container.encode(Kind.workoutSnapshot, forKey: .kind)
            try container.encode(snapshot, forKey: .snapshot)
        case .glassesBattery(let level):
            try container.encode(Kind.glassesBattery, forKey: .kind)
            try container.encode(level, forKey: .batteryLevel)
        }
    }
}

public enum WCMessageCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}
