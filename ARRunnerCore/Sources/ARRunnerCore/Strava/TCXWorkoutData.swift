// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Input model for `TCXEncoder`. Carries everything required to emit a single
/// Strava-uploadable TCX file for one workout.
///
/// Per **D-Strava-2** (TCX format for v0.5), this struct intentionally mirrors
/// only the slice of TCX 2.0 that maps cleanly to `HKWorkout` +
/// `HKWorkoutRoute` + HR samples — no developer fields, no per-mile splits
/// (v0.6), no cadence (not currently captured).
///
/// `workoutID` is the join key Strava uses for idempotency: it is sent as the
/// `external_id` multipart field at upload time so repeated uploads of the
/// same workout collapse to one activity (D-Strava-4 — workout save is
/// independent of upload, so retries are expected).
public struct TCXWorkoutData: Sendable, Equatable {
    /// `HKWorkout.uuid` — also the Strava `external_id`.
    public let workoutID: UUID
    public let startDate: Date
    public let endDate: Date
    public let totalDistanceMeters: Double
    public let totalDurationSeconds: TimeInterval
    /// TCX `<Activity Sport=…>` value. Defaults to "Running" for v0.5.
    /// Strava-accepted values: "Running", "Biking", "Other".
    public let sport: String
    /// All recorded trackpoints in chronological order. May be empty for an
    /// HR-only workout (still emits a valid TCX with no `<Track>` children).
    public let trackpoints: [TCXTrackpoint]
    /// Lap aggregates. v0.5 always emits exactly one lap covering the whole
    /// workout; per-mile splits are deferred to v0.6.
    public let laps: [TCXLap]

    public init(
        workoutID: UUID,
        startDate: Date,
        endDate: Date,
        totalDistanceMeters: Double,
        totalDurationSeconds: TimeInterval,
        sport: String = "Running",
        trackpoints: [TCXTrackpoint] = [],
        laps: [TCXLap] = []
    ) {
        self.workoutID = workoutID
        self.startDate = startDate
        self.endDate = endDate
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.sport = sport
        self.trackpoints = trackpoints
        self.laps = laps
    }

    /// Map an `ActivityKind` to the TCX `<Activity Sport=…>` value Strava
    /// accepts. Strava only recognizes "Running", "Biking", and "Other", so
    /// walking maps to "Other" (Strava re-classifies it as a Walk from the
    /// activity name / GPS profile). Environment (indoor/outdoor) does not
    /// change the TCX sport string.
    public static func tcxSport(for activity: ActivityKind) -> String {
        switch activity {
        case .running: return "Running"
        case .cycling: return "Biking"
        case .walking: return "Other"
        }
    }

    /// Convenience: the TCX sport string for a full `WorkoutType`.
    public static func tcxSport(for type: WorkoutType) -> String {
        tcxSport(for: type.activity)
    }
}

/// A single TCX `<Trackpoint>`. All position/HR/altitude fields are optional
/// so the same struct represents:
/// - a GPS sample with HR (full data)
/// - a GPS sample without HR (route only)
/// - an HR sample without GPS (HR-only workout)
public struct TCXTrackpoint: Sendable, Equatable {
    public let timestamp: Date
    public let latitude: Double?
    public let longitude: Double?
    public let altitudeMeters: Double?
    public let heartRateBPM: Int?

    public init(
        timestamp: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitudeMeters: Double? = nil,
        heartRateBPM: Int? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.heartRateBPM = heartRateBPM
    }
}

/// A single TCX `<Lap>`. For v0.5 each `TCXWorkoutData` carries exactly one
/// of these covering the whole workout.
public struct TCXLap: Sendable, Equatable {
    public let startTime: Date
    public let totalTimeSeconds: TimeInterval
    public let distanceMeters: Double
    public let calories: Int?
    public let averageHeartRate: Int?
    public let maximumHeartRate: Int?
    public let trackpoints: [TCXTrackpoint]

    public init(
        startTime: Date,
        totalTimeSeconds: TimeInterval,
        distanceMeters: Double,
        calories: Int? = nil,
        averageHeartRate: Int? = nil,
        maximumHeartRate: Int? = nil,
        trackpoints: [TCXTrackpoint] = []
    ) {
        self.startTime = startTime
        self.totalTimeSeconds = totalTimeSeconds
        self.distanceMeters = distanceMeters
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.trackpoints = trackpoints
    }
}
