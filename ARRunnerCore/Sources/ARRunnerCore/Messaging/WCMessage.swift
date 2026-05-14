import Foundation

public enum LifecycleEvent: Sendable, Codable, Equatable {
    case started(SportType)
    case paused
    case resumed
    case ended
}

public enum WCMessage: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    case layoutConfig(HUDLayout)
    case workoutTick(WorkoutMetric)
    case workoutLifecycle(LifecycleEvent)

    public var schemaVersion: Int {
        Self.currentSchemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case layout
        case metric
        case lifecycleEvent
    }

    private enum Kind: String, Codable {
        case layoutConfig
        case workoutTick
        case workoutLifecycle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)

        guard schemaVersion == Self.currentSchemaVersion else {
            throw WCMessageCodingError.unsupportedSchemaVersion(schemaVersion)
        }

        switch try container.decode(Kind.self, forKey: .kind) {
        case .layoutConfig:
            self = .layoutConfig(try container.decode(HUDLayout.self, forKey: .layout))
        case .workoutTick:
            self = .workoutTick(try container.decode(WorkoutMetric.self, forKey: .metric))
        case .workoutLifecycle:
            self = .workoutLifecycle(try container.decode(LifecycleEvent.self, forKey: .lifecycleEvent))
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
        }
    }
}

public enum WCMessageCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}
