// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import ARRunnerCore

/// High-level scenario the fake substrate replays after `begin(...)`.
public enum HealthKitScenario: Sendable {
    case steadyRun(heartRate: Double, paceSecPerKm: Double, tickCount: Int)
    case intervals(highHR: Double, lowHR: Double, workTicks: Int, restTicks: Int, repeats: Int)
    case explicit([WorkoutMetric])
    case ended
}

/// Deterministic in-memory `WorkoutHealthSubstrate` for scenario-replay tests.
///
/// Why this exists alongside `InMemoryWorkoutHealthSubstrate` (Laughlin, PR #7):
///   * Laughlin's substrate is the canonical "I'll push metrics by hand"
///     test double — minimal, manually driven, ideal for unit tests.
///   * `FakeHealthKitSubstrate` is the QA-flavoured cousin: pre-cans whole
///     scenarios (steady run, intervals, explicit metric script) and replays
///     them after `begin(...)` so integration tests stay declarative.
///   * Both conform to the same `WorkoutHealthSubstrate` protocol, so they
///     plug into the canonical `WorkoutController` interchangeably.
///
/// On `end(...)` the substrate returns a `WorkoutHealthResult` whose
/// `healthKitWorkoutID` is the stable UUID provided to `init` — D9 side-store
/// metadata can then be keyed by that UUID for round-trip assertions.
public actor FakeHealthKitSubstrate: WorkoutHealthSubstrate {
    public let workoutID: UUID
    public private(set) var currentPhase: WorkoutSubstratePhase = .notStarted
    public private(set) var recordedCalls: [Call] = []

    public enum Call: Sendable, Equatable {
        case begin(sport: SportType, at: Date)
        case pause(at: Date)
        case resume(at: Date)
        case end(at: Date)
    }

    public nonisolated let stateEvents: AsyncStream<WorkoutSubstratePhase>
    public nonisolated let metricEvents: AsyncStream<WorkoutMetric>

    private let stateContinuation: AsyncStream<WorkoutSubstratePhase>.Continuation
    private let metricContinuation: AsyncStream<WorkoutMetric>.Continuation

    private let scenario: HealthKitScenario
    private let baseDate: Date
    private let tickInterval: TimeInterval

    private var beganAt: Date?
    private var replayTask: Task<Void, Never>?
    private var replayCompleted = false

    public init(
        workoutID: UUID = UUID(),
        scenario: HealthKitScenario = .steadyRun(heartRate: 150, paceSecPerKm: 300, tickCount: 10),
        baseDate: Date = Date(timeIntervalSinceReferenceDate: 0),
        tickInterval: TimeInterval = 1.0
    ) {
        self.workoutID = workoutID
        self.scenario = scenario
        self.baseDate = baseDate
        self.tickInterval = tickInterval

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

    // MARK: - WorkoutHealthSubstrate

    public func begin(sport: SportType, startedAt: Date) async throws {
        if case .running = currentPhase {
            throw WorkoutHealthSubstrateError.alreadyRunning
        }
        recordedCalls.append(.begin(sport: sport, at: startedAt))
        beganAt = startedAt
        transitionPhase(to: .preparing)
        transitionPhase(to: .running)

        let metrics = Self.expand(scenario, baseDate: baseDate, tickInterval: tickInterval)
        replayTask = Task { [weak self] in
            for metric in metrics {
                if Task.isCancelled { return }
                await self?.emit(metric)
                await Task.yield()
            }
            await self?.markReplayComplete()
        }
    }

    public func pause(at date: Date) async throws {
        recordedCalls.append(.pause(at: date))
        transitionPhase(to: .paused)
    }

    public func resume(at date: Date) async throws {
        recordedCalls.append(.resume(at: date))
        transitionPhase(to: .running)
    }

    public func end(at date: Date) async throws -> WorkoutHealthResult {
        recordedCalls.append(.end(at: date))
        replayTask?.cancel()
        replayTask = nil
        transitionPhase(to: .ended)

        let duration = beganAt.map { date.timeIntervalSince($0) } ?? 0
        let result = WorkoutHealthResult(
            healthKitWorkoutID: workoutID,
            endedAt: date,
            activeDuration: max(0, duration)
        )

        stateContinuation.finish()
        metricContinuation.finish()
        return result
    }

    // MARK: - Test affordances

    /// True once the configured scenario has finished emitting all pre-canned
    /// metrics. Tests can poll this before calling `end(...)`.
    public var isScenarioComplete: Bool { replayCompleted }

    /// Push a one-off metric outside the configured scenario.
    public func injectMetric(_ metric: WorkoutMetric) {
        emit(metric)
    }

    /// Force a phase transition directly (e.g. simulate a substrate failure).
    public func forcePhase(_ phase: WorkoutSubstratePhase) {
        transitionPhase(to: phase)
    }

    // MARK: - Private

    private func emit(_ metric: WorkoutMetric) {
        metricContinuation.yield(metric)
    }

    private func transitionPhase(to phase: WorkoutSubstratePhase) {
        currentPhase = phase
        stateContinuation.yield(phase)
    }

    private func markReplayComplete() {
        replayCompleted = true
    }

    private static func expand(
        _ scenario: HealthKitScenario,
        baseDate: Date,
        tickInterval: TimeInterval
    ) -> [WorkoutMetric] {
        switch scenario {
        case .steadyRun(let hr, let pace, let count):
            var out: [WorkoutMetric] = []
            for i in 0..<count {
                let ts = baseDate.addingTimeInterval(Double(i) * tickInterval)
                out.append(WorkoutMetric(kind: .heartRate, value: hr, unit: "count/min", timestamp: ts))
                out.append(WorkoutMetric(kind: .pace, value: pace, unit: "s/km", timestamp: ts))
                out.append(WorkoutMetric(kind: .distance, value: Double(i + 1) * 5.0, unit: "m", timestamp: ts))
            }
            return out
        case .intervals(let highHR, let lowHR, let workTicks, let restTicks, let repeats):
            var out: [WorkoutMetric] = []
            var i = 0
            for _ in 0..<repeats {
                for _ in 0..<workTicks {
                    let ts = baseDate.addingTimeInterval(Double(i) * tickInterval)
                    out.append(WorkoutMetric(kind: .heartRate, value: highHR, unit: "count/min", timestamp: ts))
                    i += 1
                }
                for _ in 0..<restTicks {
                    let ts = baseDate.addingTimeInterval(Double(i) * tickInterval)
                    out.append(WorkoutMetric(kind: .heartRate, value: lowHR, unit: "count/min", timestamp: ts))
                    i += 1
                }
            }
            return out
        case .explicit(let metrics):
            return metrics
        case .ended:
            return []
        }
    }
}

/// In-memory implementation of `ARMetadataStore` for tests — no filesystem.
/// Keyed by the HealthKit workout UUID per D9.
public actor InMemoryARMetadataStore: ARMetadataStore {
    public private(set) var saved: [UUID: ARWorkoutMetadata] = [:]

    public init() {}

    public func loadMetadata(for workoutID: UUID) async throws -> ARWorkoutMetadata? {
        saved[workoutID]
    }

    public func saveMetadata(_ metadata: ARWorkoutMetadata, for workoutID: UUID) async throws {
        saved[workoutID] = metadata
    }
}
