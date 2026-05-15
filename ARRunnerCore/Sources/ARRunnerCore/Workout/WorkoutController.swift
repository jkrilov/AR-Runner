// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Sport-agnostic orchestrator for an `HKWorkoutSession`-backed workout.
///
/// Decisions in scope:
/// - **D2** — watchOS 11 / iOS 18 / Swift 6 strict concurrency (actor isolation).
/// - **D3** — sport-agnostic core; `start(activityType:)` defaults to `.running` for v0.1.
/// - **D4** — glasses disconnect signals are recorded but DO NOT pause the workout.
/// - **D5** — phone is optional; the controller never assumes a paired iPhone.
/// - **D7** — foreground launch from the watch app; this controller is the worker.
/// - **D8** — no `@unchecked Sendable`; all mutable state is actor-isolated.
/// - **D9** — `WorkoutSummary.healthKitWorkoutID` is the side-store join key.
///
/// HealthKit access is injected via `WorkoutHealthSubstrate` so that:
///   1. Linux SPM tests in `ARRunnerCoreTests` can run without a HealthKit linkage.
///   2. Amber's parallel integration mocks plug into a stable seam.
///   3. Future sports surfaces (cycling, walking — D3) reuse the same controller.
public actor WorkoutController {
    public enum Error: Swift.Error, Equatable {
        case notStarted
        case alreadyStarted
        case invalidTransition(from: WorkoutPhase, to: WorkoutPhase)
        case substrateFailure(reason: String)
    }

    private let substrate: any WorkoutHealthSubstrate
    private let clock: @Sendable () -> Date
    private let sessionID: UUID

    private var sport: SportType = .running
    private var phase: WorkoutPhase = .idle
    private var startedAt: Date?
    private var endedAt: Date?
    private var glassesConnected: Bool = false
    private var glassesDisconnectCount: Int = 0

    // Live aggregates fed by the metric forwarding task so `end()` can build a
    // useful summary even when the substrate doesn't populate every field.
    private var observedMetrics: [WorkoutMetric] = []
    private var heartRateSamples: [Double] = []
    private var lastDistanceMeters: Double?
    private var lastEnergyKilocalories: Double?
    private var lastCadenceStepsPerMinute: Double?
    private var lastElevationGainMeters: Double?

    private let stateContinuation: AsyncStream<WorkoutState>.Continuation
    private let metricContinuation: AsyncStream<WorkoutMetric>.Continuation

    /// Observable state stream. A fresh snapshot is emitted on every transition
    /// (and on glasses signal changes) so views and the WC bridge can subscribe
    /// with `for await state in controller.states { … }`.
    public nonisolated let states: AsyncStream<WorkoutState>

    /// Live metric stream forwarded from the substrate. Heart rate, distance,
    /// energy, cadence, elevation — exactly what the substrate produces.
    public nonisolated let metrics: AsyncStream<WorkoutMetric>

    private var forwardingTask: Task<Void, Never>?
    private var stateMirrorTask: Task<Void, Never>?

    public init(
        substrate: any WorkoutHealthSubstrate,
        sessionID: UUID = UUID(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.substrate = substrate
        self.sessionID = sessionID
        self.clock = clock

        var stateCont: AsyncStream<WorkoutState>.Continuation!
        self.states = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            stateCont = continuation
        }
        self.stateContinuation = stateCont

        var metricCont: AsyncStream<WorkoutMetric>.Continuation!
        self.metrics = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            metricCont = continuation
        }
        self.metricContinuation = metricCont
    }

    deinit {
        forwardingTask?.cancel()
        stateMirrorTask?.cancel()
        stateContinuation.finish()
        metricContinuation.finish()
    }

    // MARK: - Lifecycle

    /// Begin a workout. Activity defaults to `.running` (v0.1 surface — D3).
    @discardableResult
    public func start(activityType: SportType = .running) async throws -> WorkoutState {
        guard phase == .idle else {
            throw Error.alreadyStarted
        }

        sport = activityType
        let now = clock()
        startedAt = now
        transition(to: .preparing, at: now)

        attachSubstrateStreams()

        do {
            try await substrate.begin(sport: activityType, startedAt: now)
        } catch {
            let reason = String(describing: error)
            transition(to: .failed, at: clock(), reason: reason)
            throw Error.substrateFailure(reason: reason)
        }

        let runningAt = clock()
        transition(to: .running, at: runningAt)
        return makeState(at: runningAt)
    }

    public func pause() async throws {
        guard phase == .running else {
            throw Error.invalidTransition(from: phase, to: .paused)
        }
        let now = clock()
        try await substrate.pause(at: now)
        transition(to: .paused, at: now)
    }

    public func resume() async throws {
        guard phase == .paused else {
            throw Error.invalidTransition(from: phase, to: .running)
        }
        let now = clock()
        try await substrate.resume(at: now)
        transition(to: .running, at: now)
    }

    /// End the workout, finalize HealthKit storage, and emit a `WorkoutSummary`.
    /// The returned summary's `healthKitWorkoutID` is the D9 side-store join key.
    @discardableResult
    public func end() async throws -> WorkoutSummary {
        switch phase {
        case .idle, .ended:
            throw Error.notStarted
        case .running, .paused, .preparing, .failed:
            break
        }

        let now = clock()
        let result: WorkoutHealthResult
        do {
            result = try await substrate.end(at: now)
        } catch {
            let reason = String(describing: error)
            transition(to: .failed, at: now, reason: reason)
            throw Error.substrateFailure(reason: reason)
        }

        endedAt = result.endedAt
        transition(to: .ended, at: result.endedAt)

        forwardingTask?.cancel()
        stateMirrorTask?.cancel()
        stateContinuation.finish()
        metricContinuation.finish()

        return makeSummary(from: result)
    }

    // MARK: - Glasses signal (D4 — never pauses the workout)

    /// Record a glasses connectivity event. Per D4 the workout runs whether or
    /// not the HUD is online; this method only updates the state snapshot
    /// (`glassesConnected`) and bumps the disconnect counter for the summary.
    public func reportGlassesSignal(_ signal: GlassesConnectivitySignal) {
        switch signal {
        case .connected:
            glassesConnected = true
        case .disconnected:
            if glassesConnected {
                glassesDisconnectCount += 1
            }
            glassesConnected = false
        }
        // Emit a refreshed state snapshot so observers see the HUD status flip.
        // Phase is deliberately unchanged.
        let snapshot = makeState(at: clock())
        stateContinuation.yield(snapshot)
    }

    // MARK: - Test/inspection helpers

    public func currentPhase() -> WorkoutPhase { phase }
    public func currentSessionID() -> UUID { sessionID }
    public func recordedDisconnectCount() -> Int { glassesDisconnectCount }

    // MARK: - Internals

    private func attachSubstrateStreams() {
        let metricStream = substrate.metricEvents
        let stateStream = substrate.stateEvents

        forwardingTask = Task { [weak self] in
            for await metric in metricStream {
                guard let self else { return }
                await self.ingest(metric: metric)
            }
        }

        stateMirrorTask = Task { [weak self] in
            for await substratePhase in stateStream {
                guard let self else { return }
                await self.handleSubstratePhase(substratePhase)
            }
        }
    }

    private func ingest(metric: WorkoutMetric) {
        observedMetrics.append(metric)

        switch metric.kind {
        case .heartRate:
            heartRateSamples.append(metric.value)
        case .distance:
            lastDistanceMeters = metric.value
        case .cadence:
            lastCadenceStepsPerMinute = metric.value
        case .elevation:
            lastElevationGainMeters = metric.value
        case .pace, .duration:
            break
        }

        metricContinuation.yield(metric)
    }

    private func handleSubstratePhase(_ substratePhase: WorkoutSubstratePhase) {
        if case .failed(let reason) = substratePhase {
            transition(to: .failed, at: clock(), reason: reason)
        }
        // Other substrate phases are driven by explicit controller calls; no
        // need to mirror them here (they would race with `transition`).
    }

    private func transition(to newPhase: WorkoutPhase, at date: Date, reason: String? = nil) {
        phase = newPhase
        let snapshot = WorkoutState(
            sessionID: sessionID,
            sport: sport,
            phase: newPhase,
            startedAt: startedAt,
            endedAt: endedAt,
            glassesConnected: glassesConnected,
            timestamp: date,
            failureReason: reason
        )
        stateContinuation.yield(snapshot)
    }

    private func makeState(at date: Date) -> WorkoutState {
        WorkoutState(
            sessionID: sessionID,
            sport: sport,
            phase: phase,
            startedAt: startedAt,
            endedAt: endedAt,
            glassesConnected: glassesConnected,
            timestamp: date
        )
    }

    private func makeSummary(from result: WorkoutHealthResult) -> WorkoutSummary {
        let avgHR = heartRateSamples.isEmpty
            ? result.averageHeartRateBeatsPerMinute
            : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
        let peakHR = heartRateSamples.max() ?? result.peakHeartRateBeatsPerMinute

        let distance = result.totalDistanceMeters ?? lastDistanceMeters
        let pace: Double? = {
            guard let distance, distance > 0, result.activeDuration > 0 else { return nil }
            return result.activeDuration / (distance / 1000.0)
        }()

        return WorkoutSummary(
            id: sessionID,
            healthKitWorkoutID: result.healthKitWorkoutID,
            sport: sport,
            startedAt: startedAt ?? result.endedAt,
            endedAt: result.endedAt,
            activeDuration: result.activeDuration,
            totalDistanceMeters: distance,
            totalActiveEnergyKilocalories: result.totalActiveEnergyKilocalories ?? lastEnergyKilocalories,
            averageHeartRateBeatsPerMinute: avgHR,
            peakHeartRateBeatsPerMinute: peakHR,
            averagePaceSecondsPerKilometer: pace,
            splits: [],
            glassesDisconnectCount: glassesDisconnectCount,
            totalElevationGainMeters: result.totalElevationGainMeters ?? lastElevationGainMeters,
            averageCadenceStepsPerMinute: lastCadenceStepsPerMinute
        )
    }
}
