// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum LifecycleEvent: Sendable, Codable, Equatable {
    case started(WorkoutType)
    case paused
    case resumed
    case ended
}

public enum WCMessage: Sendable, Codable, Equatable {
    /// v1 — layoutConfig / workoutTick (per-metric) / workoutLifecycle.
    /// v2 — adds workoutSnapshot for the iPhone live mirror (v0.2 #3).
    /// v3 — adds glassesBattery for v0.4 phone-side battery indicator.
    /// v4 — `WorkoutTickMessage.startedAt` (optional) for the rc2 phone
    ///      mirror "Started at …" row. Additive + optional, so a v4 phone
    ///      still decodes v3 snapshots and a v3 phone simply doesn't see
    ///      the new field. Watch forwards 0–100 percent from the Battery
    ///      Service (0x180F / 0x2A19) via transferUserInfo. Phone-optional:
    ///      missing the iPhone never blocks the watch.
    /// v5 — `WorkoutTickMessage.latitude` / `.longitude` (both optional)
    ///      for the v0.5.16 phone-side live route map. Additive + optional
    ///      so v5 ↔ v4/v3 peers keep working in both directions — older
    ///      watch builds simply don't populate them and the phone treats
    ///      that as "no map yet".
    /// v6 — v0.6.0 multi-workout-type foundation. Three changes, all
    ///      backward-compatible:
    ///      1. `LifecycleEvent.started` / `WorkoutTickMessage.sport` now carry
    ///         the orthogonal `WorkoutType`, which encodes the three legacy
    ///         outdoor variants as the unchanged raw strings "running" /
    ///         "walking" / "cycling" — so a v0.5.20 peer's `sport:"running"`
    ///         still decodes, and an unknown sport degrades to `.outdoorRun`
    ///         rather than fataling the decode.
    ///      2. New settings-sync cases `defaultWorkoutType` and
    ///         `unitPreference` (phone ↔ watch).
    ///      3. Unrecognized message `kind`s decode to `.unknown` instead of
    ///         throwing, so a future peer's new case can't strand the link.
    ///      Layout catalog/defaults payloads are deferred to v6.1.
    public static let currentSchemaVersion = 6

    case layoutConfig(HUDLayout)
    case workoutTick(WorkoutMetric)
    case workoutLifecycle(LifecycleEvent)
    case workoutSnapshot(WorkoutTickMessage)
    /// Glasses battery percentage (0–100) as reported by the standard
    /// Battery Service notification on the watch's BLE link.
    case glassesBattery(level: Int)
    /// v6 — phone → watch (or watch → phone) sync of the user's preferred
    /// default workout type.
    case defaultWorkoutType(WorkoutType)
    /// v6 — phone ↔ watch sync of the user's metric/imperial preference.
    case unitPreference(UnitSystem)
    /// Decode-only fallback for an unrecognized message `kind` from a
    /// newer/older peer on the same major schema. Never produced by an
    /// encoder under normal operation; receivers treat it as "ignore".
    case unknown

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
        case workoutType
        case unitSystem
    }

    private enum Kind: String, Codable {
        case layoutConfig
        case workoutTick
        case workoutLifecycle
        case workoutSnapshot
        case glassesBattery
        case defaultWorkoutType
        case unitPreference
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

        // Decode the discriminator leniently: an unrecognized `kind` from a
        // peer on the same major schema degrades to `.unknown` instead of
        // throwing, so one new case can't strand the whole link.
        let rawKind = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            self = .unknown
            return
        }

        switch kind {
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
        case .defaultWorkoutType:
            self = .defaultWorkoutType(try container.decode(WorkoutType.self, forKey: .workoutType))
        case .unitPreference:
            self = .unitPreference(try container.decode(UnitSystem.self, forKey: .unitSystem))
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
        case .defaultWorkoutType(let type):
            try container.encode(Kind.defaultWorkoutType, forKey: .kind)
            try container.encode(type, forKey: .workoutType)
        case .unitPreference(let system):
            try container.encode(Kind.unitPreference, forKey: .kind)
            try container.encode(system, forKey: .unitSystem)
        case .unknown:
            // A decode-only sentinel. Encode a stable, self-describing marker
            // so a round-trip of `.unknown` stays `.unknown` rather than
            // throwing; peers ignore it.
            try container.encode("unknown", forKey: .kind)
        }
    }
}

public enum WCMessageCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}
