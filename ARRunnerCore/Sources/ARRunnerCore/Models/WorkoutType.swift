// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The base human activity of a workout (the "what you're doing" axis).
public enum ActivityKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case running
    case walking
    case cycling
}

/// Where the workout happens (the "GPS vs treadmill" axis). Indoor workouts
/// suppress GPS / `HKWorkoutRouteBuilder` on the watch shell.
public enum WorkoutEnvironment: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case outdoor
    case indoor
}

/// Orthogonal workout-type model: `activity × environment`.
///
/// Supersedes the flat `SportType` enum (≤ v0.5.x). The supported set is the
/// full 3 × 2 product — outdoor/indoor run, outdoor/indoor walk,
/// outdoor/indoor bike.
///
/// **Wire/storage compatibility (locked decision, jkrilov 2026-06-17).** The
/// custom `Codable` encodes the three *outdoor* variants as exactly the legacy
/// raw strings — `"running"`, `"walking"`, `"cycling"` — so v0.5.20 wire
/// payloads and side-store records keep decoding unchanged. The new indoor
/// combos get new, stable raw strings (`"indoor_running"` etc.). Decoding an
/// unrecognized raw value never throws: it falls back to ``fallback`` so a
/// newer/older peer can't fatal a whole `WCMessage` decode on one bad field.
public struct WorkoutType: Sendable, Equatable, Hashable, RawRepresentable, CaseIterable {
    public let activity: ActivityKind
    public let environment: WorkoutEnvironment

    public init(activity: ActivityKind, environment: WorkoutEnvironment) {
        self.activity = activity
        self.environment = environment
    }

    // MARK: - RawRepresentable (stable wire strings)

    public var rawValue: String {
        switch (activity, environment) {
        case (.running, .outdoor): return "running"
        case (.walking, .outdoor): return "walking"
        case (.cycling, .outdoor): return "cycling"
        case (.running, .indoor): return "indoor_running"
        case (.walking, .indoor): return "indoor_walking"
        case (.cycling, .indoor): return "indoor_cycling"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "running": self.init(activity: .running, environment: .outdoor)
        case "walking": self.init(activity: .walking, environment: .outdoor)
        case "cycling": self.init(activity: .cycling, environment: .outdoor)
        case "indoor_running": self.init(activity: .running, environment: .indoor)
        case "indoor_walking": self.init(activity: .walking, environment: .indoor)
        case "indoor_cycling": self.init(activity: .cycling, environment: .indoor)
        default: return nil
        }
    }

    // MARK: - Conveniences

    /// `true` for treadmill / stationary-bike variants. The watch shell uses
    /// this to pick `HKWorkoutSessionLocationType.indoor` and skip the GPS
    /// route builder.
    public var isIndoor: Bool { environment == .indoor }

    /// `true` when the workout records a GPS route. All outdoor variants use
    /// GPS (including outdoor cycling); no indoor variant does.
    public var usesGPS: Bool { environment == .outdoor }

    /// The underlying activity, independent of environment. Convenience alias
    /// so call sites that only care about run-vs-walk-vs-bike read cleanly.
    public var baseActivity: ActivityKind { activity }

    /// Human-readable label, e.g. "Outdoor Run", "Indoor Bike".
    public var displayName: String {
        let place = environment == .indoor ? "Indoor" : "Outdoor"
        let noun: String
        switch activity {
        case .running: noun = "Run"
        case .walking: noun = "Walk"
        case .cycling: noun = "Bike"
        }
        return "\(place) \(noun)"
    }

    // MARK: - Supported combinations

    public static let outdoorRun = WorkoutType(activity: .running, environment: .outdoor)
    public static let indoorRun = WorkoutType(activity: .running, environment: .indoor)
    public static let outdoorWalk = WorkoutType(activity: .walking, environment: .outdoor)
    public static let indoorWalk = WorkoutType(activity: .walking, environment: .indoor)
    public static let outdoorBike = WorkoutType(activity: .cycling, environment: .outdoor)
    public static let indoorBike = WorkoutType(activity: .cycling, environment: .indoor)

    /// Safe default used when an unrecognized raw value is decoded.
    public static let fallback = WorkoutType.outdoorRun

    public static let allCases: [WorkoutType] = [
        .outdoorRun, .indoorRun,
        .outdoorWalk, .indoorWalk,
        .outdoorBike, .indoorBike,
    ]
}

// MARK: - Codable (legacy-string-preserving, non-throwing fallback)

extension WorkoutType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Unknown raw values degrade to the fallback instead of throwing so a
        // single unrecognized field never fatals an entire WCMessage decode.
        self = WorkoutType(rawValue: raw) ?? .fallback
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
