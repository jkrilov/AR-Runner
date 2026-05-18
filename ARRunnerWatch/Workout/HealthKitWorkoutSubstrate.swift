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

    // MARK: - Authorization

    /// Types this substrate writes to HealthKit. Workouts are the canonical
    /// share target; the rest are the per-sample types `HKLiveWorkoutBuilder`
    /// persists onto the resulting `HKWorkout`.
    public static var sharedTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let cycling = HKQuantityType.quantityType(forIdentifier: .distanceCycling) { types.insert(cycling) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    /// Types this substrate reads back from HealthKit (statistics off the
    /// live builder, plus the workout objects themselves on end).
    public static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let cycling = HKQuantityType.quantityType(forIdentifier: .distanceCycling) { types.insert(cycling) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    /// Request HealthKit authorization for every type this substrate produces
    /// or consumes. Must complete successfully **before** `begin(...)` —
    /// without it, `HKLiveWorkoutBuilder` enters its terminal `Error(7)` state
    /// the moment `beginCollection` is invoked and refuses all transitions.
    /// Safe to call repeatedly: HealthKit treats a re-request as a no-op once
    /// the user has answered, so the watch app calls this on launch *and* the
    /// substrate calls it again defensively from `begin(...)`.
    public static func requestAuthorization(healthStore: HKHealthStore = HKHealthStore()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutHealthSubstrateError.notAuthorized
        }
        try await healthStore.requestAuthorization(toShare: sharedTypes, read: readTypes)
    }

    // MARK: - WorkoutHealthSubstrate

    public func begin(sport: SportType, startedAt: Date) async throws {
        // Defensive: HK Error(7) on `beginCollection` is almost always a
        // pre-flight failure (missing entitlement / usage-string / un-granted
        // auth). Re-requesting here is cheap once the user has answered, and
        // surfaces a clean `notAuthorized` if HealthKit is unavailable.
        try await Self.requestAuthorization(healthStore: healthStore)

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
                  let stats = workoutBuilder.statistics(for: quantityType) else { continue }

            // v0.2.0 device feedback (Joe): distance was jumping per sample
            // instead of monotonically increasing because we used
            // `mostRecentQuantity()`, which is a single per-sample reading.
            // Cumulative HK types (distance, active energy) must source
            // from `sumQuantity()`; instantaneous types (heart rate) still
            // want the most-recent reading. See
            // `.squad/skills/healthkit-derived-metrics-watchos`.
            let quantity: HKQuantity?
            switch quantityType {
            case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
                 HKQuantityType.quantityType(forIdentifier: .distanceCycling),
                 HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                quantity = stats.sumQuantity()
            default:
                quantity = stats.mostRecentQuantity()
            }
            guard let quantity else { continue }

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
            // v0.2 audit P1.3: previously routed to `.duration`, which
            // downstream consumers default-cased to nothing — live HK
            // kcal was silently dropped. Now uses the dedicated
            // `.energy` case (Amber's Core change, commit 9571e23) via
            // the Core-side mapping helper so the contract is testable
            // without a watchOS test host.
            return HealthKitMetricMapping.activeEnergy(
                kilocalories: quantity.doubleValue(for: .kilocalorie()),
                timestamp: timestamp
            )
        default:
            return nil
        }
    }
}
#endif

#endif
