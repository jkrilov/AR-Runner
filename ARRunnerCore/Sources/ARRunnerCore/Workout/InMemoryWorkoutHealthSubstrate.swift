// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// In-memory substrate that fakes a `HKWorkoutSession` for unit tests, SwiftUI
/// previews, and Amber's parallel integration mocks. It records the lifecycle
/// commands the controller issues, lets a test push synthetic metrics into the
/// stream, and returns a deterministic `WorkoutHealthResult` on `end`.
///
/// Usage from a test:
/// ```swift
/// let substrate = InMemoryWorkoutHealthSubstrate()
/// let controller = WorkoutController(substrate: substrate)
/// _ = try await controller.start(activityType: .running)
/// await substrate.emit(metric: WorkoutMetric(kind: .heartRate, value: 152, unit: "count/min", timestamp: .now))
/// let summary = try await controller.end()
/// ```
public actor InMemoryWorkoutHealthSubstrate: WorkoutHealthSubstrate {
    public enum RecordedCall: Sendable, Equatable {
        case begin(sport: SportType, at: Date)
        case pause(at: Date)
        case resume(at: Date)
        case end(at: Date)
        /// rc2 (2026-05-20): user-initiated cancel terminal path. Distinct
        /// from `.end` so tests can assert no HK save happened on cancel.
        case discard(at: Date)
    }

    private let stateContinuation: AsyncStream<WorkoutSubstratePhase>.Continuation
    private let metricContinuation: AsyncStream<WorkoutMetric>.Continuation

    public nonisolated let stateEvents: AsyncStream<WorkoutSubstratePhase>
    public nonisolated let metricEvents: AsyncStream<WorkoutMetric>

    public private(set) var recordedCalls: [RecordedCall] = []
    private var currentPhase: WorkoutSubstratePhase = .notStarted

    /// HealthKit workout UUID returned from `end` (defaults to a fresh UUID
    /// per init so each test run is independently identifiable).
    private let healthKitWorkoutID: UUID

    /// Optional fixed result. When set, `end` returns this verbatim. Otherwise
    /// a default result is synthesized from the begin/end timestamps.
    private var queuedResult: WorkoutHealthResult?

    /// Optional injected error. When set, the next mutating call throws and
    /// then the slot clears.
    private var queuedError: (any Error)?

    private var beganAt: Date?

    public init(healthKitWorkoutID: UUID = UUID()) {
        self.healthKitWorkoutID = healthKitWorkoutID

        var stateCont: AsyncStream<WorkoutSubstratePhase>.Continuation!
        self.stateEvents = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            stateCont = continuation
        }
        self.stateContinuation = stateCont

        var metricCont: AsyncStream<WorkoutMetric>.Continuation!
        self.metricEvents = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            metricCont = continuation
        }
        self.metricContinuation = metricCont

        // Replay current phase to the first subscriber.
        stateContinuation.yield(.notStarted)
    }

    // MARK: - Test driver API

    /// Push a metric sample as if HealthKit emitted it.
    public func emit(metric: WorkoutMetric) {
        metricContinuation.yield(metric)
    }

    /// Force the next mutating call to throw `error` instead of succeeding.
    public func queueNextError(_ error: any Error) {
        queuedError = error
    }

    /// Override the `WorkoutHealthResult` returned from the next `end` call.
    public func queueResult(_ result: WorkoutHealthResult) {
        queuedResult = result
    }

    /// Simulate the substrate failing mid-workout (no controller call required).
    public func failSession(reason: String) {
        currentPhase = .failed(reason: reason)
        stateContinuation.yield(.failed(reason: reason))
    }

    public func currentRecordedPhase() -> WorkoutSubstratePhase {
        currentPhase
    }

    // MARK: - WorkoutHealthSubstrate

    public func begin(sport: SportType, startedAt: Date) async throws {
        if let queuedError {
            self.queuedError = nil
            throw queuedError
        }
        if case .running = currentPhase {
            throw WorkoutHealthSubstrateError.alreadyRunning
        }
        recordedCalls.append(.begin(sport: sport, at: startedAt))
        beganAt = startedAt
        currentPhase = .preparing
        stateContinuation.yield(.preparing)
        currentPhase = .running
        stateContinuation.yield(.running)
    }

    public func pause(at date: Date) async throws {
        if let queuedError {
            self.queuedError = nil
            throw queuedError
        }
        recordedCalls.append(.pause(at: date))
        currentPhase = .paused
        stateContinuation.yield(.paused)
    }

    public func resume(at date: Date) async throws {
        if let queuedError {
            self.queuedError = nil
            throw queuedError
        }
        recordedCalls.append(.resume(at: date))
        currentPhase = .running
        stateContinuation.yield(.running)
    }

    public func end(at date: Date) async throws -> WorkoutHealthResult {
        if let queuedError {
            self.queuedError = nil
            throw queuedError
        }
        recordedCalls.append(.end(at: date))
        currentPhase = .ended
        stateContinuation.yield(.ended)
        stateContinuation.finish()
        metricContinuation.finish()

        if let queuedResult {
            self.queuedResult = nil
            return queuedResult
        }

        let duration = beganAt.map { date.timeIntervalSince($0) } ?? 0
        return WorkoutHealthResult(
            healthKitWorkoutID: healthKitWorkoutID,
            endedAt: date,
            activeDuration: max(0, duration)
        )
    }

    /// rc2 — discard terminal path. NO `WorkoutHealthResult` is returned
    /// because no `HKWorkout` is created. Cleanly closes the streams so
    /// the controller's forwarding tasks unwind exactly as they do on `end`.
    public func discard(at date: Date) async throws {
        if let queuedError {
            self.queuedError = nil
            throw queuedError
        }
        recordedCalls.append(.discard(at: date))
        currentPhase = .ended
        stateContinuation.yield(.ended)
        stateContinuation.finish()
        metricContinuation.finish()
    }
}
