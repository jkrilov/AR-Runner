// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Platform-neutral seam between `WorkoutController` and the underlying
/// HealthKit workout machinery (`HKWorkoutSession` + `HKLiveWorkoutBuilder`).
///
/// Why this exists:
/// - Linux SPM tests cannot import HealthKit, so the controller must stay in
///   `ARRunnerCore` and reach the system layer through this protocol.
/// - Amber's integration mocks (parallel work) need a stable seam to drive
///   metric and state events into the controller without a live watch.
/// - Future sports surfaces (cycling, walking — D3) plug in by mapping
///   different HealthKit configurations onto the same protocol surface.
///
/// All conforming types must be `Sendable`. Implementations are free to be
/// actors, value types backed by classes, or `@MainActor`-isolated wrappers
/// over delegate-style HealthKit APIs.
public protocol WorkoutHealthSubstrate: Sendable {
    /// The current substrate-level lifecycle state. Implementations should
    /// emit a value on subscription so late observers see the latest phase.
    var stateEvents: AsyncStream<WorkoutSubstratePhase> { get }

    /// Live metric samples (heart rate, distance, energy, cadence, …) emitted
    /// by `HKLiveWorkoutBuilder` (or a mock).
    var metricEvents: AsyncStream<WorkoutMetric> { get }

    /// Begin the underlying workout collection. Returns once the session has
    /// transitioned to a running-equivalent state (or throws on failure).
    func begin(sport: SportType, startedAt: Date) async throws

    /// Pause the underlying collection. Idempotent if already paused.
    func pause(at date: Date) async throws

    /// Resume the underlying collection. Idempotent if already running.
    func resume(at date: Date) async throws

    /// End the workout and finalize HealthKit storage. Returns the resulting
    /// HealthKit workout UUID (D9 side-store key) and aggregate tallies.
    func end(at date: Date) async throws -> WorkoutHealthResult
}

/// Substrate-level lifecycle phase. Maps onto `HKWorkoutSessionState` but is
/// platform-agnostic so it can cross strict-concurrency boundaries safely.
public enum WorkoutSubstratePhase: Sendable, Equatable {
    case notStarted
    case preparing
    case running
    case paused
    case ended
    case failed(reason: String)
}

/// Aggregate result returned by the substrate when a workout ends. The
/// controller fuses this with its own observed metrics into a `WorkoutSummary`.
public struct WorkoutHealthResult: Sendable, Equatable {
    public let healthKitWorkoutID: UUID
    public let endedAt: Date
    public let activeDuration: TimeInterval
    public let totalDistanceMeters: Double?
    public let totalActiveEnergyKilocalories: Double?
    public let averageHeartRateBeatsPerMinute: Double?
    public let peakHeartRateBeatsPerMinute: Double?
    public let totalElevationGainMeters: Double?

    public init(
        healthKitWorkoutID: UUID,
        endedAt: Date,
        activeDuration: TimeInterval,
        totalDistanceMeters: Double? = nil,
        totalActiveEnergyKilocalories: Double? = nil,
        averageHeartRateBeatsPerMinute: Double? = nil,
        peakHeartRateBeatsPerMinute: Double? = nil,
        totalElevationGainMeters: Double? = nil
    ) {
        self.healthKitWorkoutID = healthKitWorkoutID
        self.endedAt = endedAt
        self.activeDuration = activeDuration
        self.totalDistanceMeters = totalDistanceMeters
        self.totalActiveEnergyKilocalories = totalActiveEnergyKilocalories
        self.averageHeartRateBeatsPerMinute = averageHeartRateBeatsPerMinute
        self.peakHeartRateBeatsPerMinute = peakHeartRateBeatsPerMinute
        self.totalElevationGainMeters = totalElevationGainMeters
    }
}

/// Errors a substrate can surface. Concrete implementations may throw their
/// own typed errors as well; the controller only needs `Error` conformance.
public enum WorkoutHealthSubstrateError: Error, Equatable {
    case notAuthorized
    case alreadyRunning
    case notRunning
    case sessionFailed(reason: String)
}
