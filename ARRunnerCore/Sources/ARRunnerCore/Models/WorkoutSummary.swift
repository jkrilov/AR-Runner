// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Final tallies emitted by `WorkoutController.end()` once the underlying
/// `HKWorkoutSession` has finished and the workout has been persisted to
/// HealthKit (D9 — HealthKit is the primary store).
///
/// The `healthKitWorkoutID` is the join key against the AR side store
/// (`ARMetadataStore`) so post-run UIs can fetch glasses-specific metadata
/// (layout used, BLE drop count, glasses battery at end).
///
/// Sport-agnostic per D3: running fields are populated for v0.1; cycling and
/// walking specific aggregates are carried as nullable stubs so the contract
/// is stable across sports.
public struct WorkoutSummary: Sendable, Codable, Equatable {
    public let id: UUID
    public let healthKitWorkoutID: UUID
    public let sport: SportType
    public let startedAt: Date
    public let endedAt: Date
    public let activeDuration: TimeInterval
    public let totalDistanceMeters: Double?
    public let totalActiveEnergyKilocalories: Double?
    public let averageHeartRateBeatsPerMinute: Double?
    public let peakHeartRateBeatsPerMinute: Double?
    public let averagePaceSecondsPerKilometer: Double?
    public let splits: [WorkoutSplit]
    public let glassesDisconnectCount: Int

    // Sport-agnostic stubs (populated when cycling/walking surfaces land — D3).
    public let totalElevationGainMeters: Double?
    public let averageCadenceStepsPerMinute: Double?

    public init(
        id: UUID,
        healthKitWorkoutID: UUID,
        sport: SportType,
        startedAt: Date,
        endedAt: Date,
        activeDuration: TimeInterval,
        totalDistanceMeters: Double?,
        totalActiveEnergyKilocalories: Double?,
        averageHeartRateBeatsPerMinute: Double?,
        peakHeartRateBeatsPerMinute: Double?,
        averagePaceSecondsPerKilometer: Double?,
        splits: [WorkoutSplit] = [],
        glassesDisconnectCount: Int = 0,
        totalElevationGainMeters: Double? = nil,
        averageCadenceStepsPerMinute: Double? = nil
    ) {
        self.id = id
        self.healthKitWorkoutID = healthKitWorkoutID
        self.sport = sport
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeDuration = activeDuration
        self.totalDistanceMeters = totalDistanceMeters
        self.totalActiveEnergyKilocalories = totalActiveEnergyKilocalories
        self.averageHeartRateBeatsPerMinute = averageHeartRateBeatsPerMinute
        self.peakHeartRateBeatsPerMinute = peakHeartRateBeatsPerMinute
        self.averagePaceSecondsPerKilometer = averagePaceSecondsPerKilometer
        self.splits = splits
        self.glassesDisconnectCount = glassesDisconnectCount
        self.totalElevationGainMeters = totalElevationGainMeters
        self.averageCadenceStepsPerMinute = averageCadenceStepsPerMinute
    }
}

/// A single split (typically a kilometer or mile boundary). Sport-agnostic;
/// `paceSecondsPerKilometer` is omitted for non-distance sports.
public struct WorkoutSplit: Sendable, Codable, Equatable {
    public let index: Int
    public let distanceMeters: Double
    public let duration: TimeInterval
    public let paceSecondsPerKilometer: Double?

    public init(
        index: Int,
        distanceMeters: Double,
        duration: TimeInterval,
        paceSecondsPerKilometer: Double?
    ) {
        self.index = index
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.paceSecondsPerKilometer = paceSecondsPerKilometer
    }
}
