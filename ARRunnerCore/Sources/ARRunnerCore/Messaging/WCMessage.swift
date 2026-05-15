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
    public static let currentSchemaVersion = 2

    case layoutConfig(HUDLayout)
    case workoutTick(WorkoutMetric)
    case workoutLifecycle(LifecycleEvent)
    case workoutSnapshot(WorkoutTickMessage)

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
    }

    private enum Kind: String, Codable {
        case layoutConfig
        case workoutTick
        case workoutLifecycle
        case workoutSnapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)

        // Accept current and any earlier schema we still know how to decode.
        // v1 lacked `workoutSnapshot`; older peers will simply never produce
        // that case so backward compatibility is automatic.
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
        }
    }
}

public enum WCMessageCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}
