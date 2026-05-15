// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Real `WorkoutHealthSubstrate` backed by `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder`. Only compiled on platforms that ship HealthKit
/// (watchOS in production). Mocks are used in `ARRunnerCoreTests` so this file
/// can stay thin.
///
/// Authorization is the caller's responsibility — request HealthKit access
/// during onboarding and only construct this substrate after the user has
/// granted both share and read permissions for the relevant workout types.
#if canImport(HealthKit)
import os

public final class HealthKitWorkoutSubstrate: NSObject, WorkoutHealthSubstrate, @unchecked Sendable {

    private struct MutableState {
        var session: HKWorkoutSession?
        var builder: HKLiveWorkoutBuilder?
        var startedAt: Date?
    }

    private let healthStore: HKHealthStore
    private let stateContinuation: AsyncStream<WorkoutSubstratePhase>.Continuation
    private let metricContinuation: AsyncStream<WorkoutMetric>.Continuation

    public let stateEvents: AsyncStream<WorkoutSubstratePhase>
    public let metricEvents: AsyncStream<WorkoutMetric>

    private let state = OSAllocatedUnfairLock<MutableState>(initialState: MutableState())

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore

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

        super.init()
        stateContinuation.yield(.notStarted)
    }

    deinit {
        stateContinuation.finish()
        metricContinuation.finish()
    }

    // MARK: - WorkoutHealthSubstrate

    public func begin(sport: SportType, startedAt: Date) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: sport)
        configuration.locationType = .outdoor

        #if os(watchOS)
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        session.delegate = self
        builder.delegate = self

        state.withLock { mutable in
            mutable.session = session
            mutable.builder = builder
            mutable.startedAt = startedAt
        }

        stateContinuation.yield(.preparing)
        session.startActivity(with: startedAt)
        try await builder.beginCollection(at: startedAt)
        stateContinuation.yield(.running)
        #else
        // Non-watchOS HealthKit (iOS) does not own workout sessions. The watch
        // is the canonical D5 owner; if this ever lands on iOS it should error.
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "HKWorkoutSession is watchOS-only")
        #endif
    }

    public func pause(at date: Date) async throws {
        #if os(watchOS)
        let session = state.withLock { $0.session }
        guard let session else {
            throw WorkoutHealthSubstrateError.notRunning
        }
        session.pause()
        stateContinuation.yield(.paused)
        #else
        _ = date
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "watchOS-only")
        #endif
    }

    public func resume(at date: Date) async throws {
        #if os(watchOS)
        let session = state.withLock { $0.session }
        guard let session else {
            throw WorkoutHealthSubstrateError.notRunning
        }
        session.resume()
        stateContinuation.yield(.running)
        #else
        _ = date
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "watchOS-only")
        #endif
    }

    public func end(at date: Date) async throws -> WorkoutHealthResult {
        #if os(watchOS)
        let snapshot = state.withLock { current -> (HKWorkoutSession?, HKLiveWorkoutBuilder?, Date?) in
            (current.session, current.builder, current.startedAt)
        }
        let (session, builder, startedAt) = snapshot

        guard let session, let builder else {
            throw WorkoutHealthSubstrateError.notRunning
        }

        session.end()
        try await builder.endCollection(at: date)
        let workout = try await builder.finishWorkout()
        stateContinuation.yield(.ended)
        stateContinuation.finish()
        metricContinuation.finish()

        let duration = startedAt.map { date.timeIntervalSince($0) } ?? 0
        return WorkoutHealthResult(
            healthKitWorkoutID: workout?.uuid ?? UUID(),
            endedAt: date,
            activeDuration: max(0, duration),
            totalDistanceMeters: workout?.totalDistance?.doubleValue(for: .meter()),
            totalActiveEnergyKilocalories: workout?.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        )
        #else
        _ = date
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "watchOS-only")
        #endif
    }

    // MARK: - Mapping

    private static func activityType(for sport: SportType) -> HKWorkoutActivityType {
        switch sport {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        }
    }
}

#if os(watchOS)
extension HealthKitWorkoutSubstrate: HKWorkoutSessionDelegate {
    public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let phase: WorkoutSubstratePhase
        switch toState {
        case .notStarted, .prepared: phase = .preparing
        case .running: phase = .running
        case .paused: phase = .paused
        case .ended, .stopped: phase = .ended
        @unknown default: phase = .running
        }
        stateContinuation.yield(phase)
    }

    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        stateContinuation.yield(.failed(reason: String(describing: error)))
    }
}

extension HealthKitWorkoutSubstrate: HKLiveWorkoutBuilderDelegate {
    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Events (pause/resume markers) are reflected via the session delegate.
    }

    public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: quantityType),
                  let quantity = stats.mostRecentQuantity() else { continue }

            let sample = Self.metric(for: quantityType, quantity: quantity, timestamp: stats.endDate)
            if let sample {
                metricContinuation.yield(sample)
            }
        }
    }

    private static func metric(
        for type: HKQuantityType,
        quantity: HKQuantity,
        timestamp: Date
    ) -> WorkoutMetric? {
        switch type {
        case HKQuantityType.quantityType(forIdentifier: .heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            return WorkoutMetric(kind: .heartRate, value: quantity.doubleValue(for: unit), unit: "count/min", timestamp: timestamp)
        case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
            return WorkoutMetric(kind: .distance, value: quantity.doubleValue(for: .meter()), unit: "m", timestamp: timestamp)
        case HKQuantityType.quantityType(forIdentifier: .distanceCycling):
            return WorkoutMetric(kind: .distance, value: quantity.doubleValue(for: .meter()), unit: "m", timestamp: timestamp)
        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
            return WorkoutMetric(kind: .duration, value: quantity.doubleValue(for: .kilocalorie()), unit: "kcal", timestamp: timestamp)
        default:
            return nil
        }
    }
}
#endif

#endif
