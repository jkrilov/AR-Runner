// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class WorkoutControllerTests: XCTestCase {

    // MARK: - Lifecycle

    func testStartTransitionsThroughPreparingToRunning() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())

        let phases = try await Self.collectStates(from: controller, while: {
            _ = try await controller.start()
        })

        XCTAssertEqual(phases.map(\.phase), [.preparing, .running])
        let running = try XCTUnwrap(phases.last)
        XCTAssertEqual(running.sport, .running)
        XCTAssertNotNil(running.startedAt)
        XCTAssertFalse(running.glassesConnected)

        let recorded = await substrate.recordedCalls
        XCTAssertEqual(recorded.count, 1)
        if case .begin(let sport, _) = recorded[0] {
            XCTAssertEqual(sport, .running)
        } else {
            XCTFail("Expected begin call, got \(recorded)")
        }
    }

    func testStartDefaultsToRunningPerD3() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())

        let state = try await controller.start()

        XCTAssertEqual(state.sport, .running)
        XCTAssertEqual(state.phase, .running)
    }

    func testStartTwiceThrowsAlreadyStarted() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())
        _ = try await controller.start()

        do {
            _ = try await controller.start()
            XCTFail("Expected alreadyStarted")
        } catch let error as WorkoutController.Error {
            XCTAssertEqual(error, .alreadyStarted)
        }
    }

    func testPauseAndResumeFlow() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())
        _ = try await controller.start()

        try await controller.pause()
        let paused = await controller.currentPhase()
        XCTAssertEqual(paused, .paused)

        try await controller.resume()
        let running = await controller.currentPhase()
        XCTAssertEqual(running, .running)

        let recorded = await substrate.recordedCalls
        // Expect: begin, pause, resume.
        XCTAssertEqual(recorded.count, 3)
    }

    func testPauseFromIdleThrowsInvalidTransition() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())

        do {
            try await controller.pause()
            XCTFail("Expected invalidTransition")
        } catch let error as WorkoutController.Error {
            if case .invalidTransition(let from, let to) = error {
                XCTAssertEqual(from, .idle)
                XCTAssertEqual(to, .paused)
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testEndProducesSummaryWithHealthKitWorkoutID() async throws {
        let workoutID = UUID()
        let substrate = InMemoryWorkoutHealthSubstrate(healthKitWorkoutID: workoutID)
        let clock = Self.steppingClock(start: 1_000, stepSeconds: 10)
        let sessionID = UUID()
        let controller = WorkoutController(
            substrate: substrate,
            sessionID: sessionID,
            clock: clock
        )

        _ = try await controller.start()
        let summary = try await controller.end()

        XCTAssertEqual(summary.id, sessionID)
        XCTAssertEqual(summary.healthKitWorkoutID, workoutID, "D9: HealthKit workout UUID is the side-store key")
        XCTAssertEqual(summary.sport, .running)
        XCTAssertGreaterThan(summary.activeDuration, 0)
        XCTAssertEqual(summary.glassesDisconnectCount, 0)
    }

    func testEndBeforeStartThrowsNotStarted() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())

        do {
            _ = try await controller.end()
            XCTFail("Expected notStarted")
        } catch let error as WorkoutController.Error {
            XCTAssertEqual(error, .notStarted)
        }
    }

    func testEndAfterEndThrowsNotStarted() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())
        _ = try await controller.start()
        _ = try await controller.end()

        do {
            _ = try await controller.end()
            XCTFail("Expected notStarted")
        } catch let error as WorkoutController.Error {
            XCTAssertEqual(error, .notStarted)
        }
    }

    // MARK: - Substrate failure surfaces

    func testStartFailureSurfacesAsSubstrateFailureAndEntersFailedPhase() async throws {
        struct OopsError: Error {}
        let substrate = InMemoryWorkoutHealthSubstrate()
        await substrate.queueNextError(OopsError())
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())

        do {
            _ = try await controller.start()
            XCTFail("Expected substrateFailure")
        } catch let error as WorkoutController.Error {
            if case .substrateFailure = error {
                // expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }

        let phase = await controller.currentPhase()
        XCTAssertEqual(phase, .failed)
    }

    // MARK: - Glasses signal (D4)

    func testGlassesDisconnectDoesNotPauseWorkout() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())
        _ = try await controller.start()

        await controller.reportGlassesSignal(.connected)
        await controller.reportGlassesSignal(.disconnected(reason: "ble timeout"))

        let phase = await controller.currentPhase()
        XCTAssertEqual(phase, .running, "D4: glasses dropping must NOT pause the workout")

        let drops = await controller.recordedDisconnectCount()
        XCTAssertEqual(drops, 1)

        // Substrate received only the begin call — no pause was forwarded.
        let recorded = await substrate.recordedCalls
        XCTAssertEqual(recorded.count, 1)
    }

    func testGlassesDisconnectCountFlowsIntoSummary() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())
        _ = try await controller.start()

        await controller.reportGlassesSignal(.connected)
        await controller.reportGlassesSignal(.disconnected(reason: nil))
        await controller.reportGlassesSignal(.connected)
        await controller.reportGlassesSignal(.disconnected(reason: "rssi"))

        let summary = try await controller.end()
        XCTAssertEqual(summary.glassesDisconnectCount, 2)
    }

    // MARK: - Metric stream

    func testMetricStreamForwardsSubstrateEmissions() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())
        _ = try await controller.start()

        let collector = Task<[WorkoutMetric], Never> { [controller] in
            var out: [WorkoutMetric] = []
            for await metric in controller.metrics {
                out.append(metric)
                if out.count == 3 { break }
            }
            return out
        }

        let now = Date(timeIntervalSinceReferenceDate: 0)
        await substrate.emit(metric: WorkoutMetric(kind: .heartRate, value: 140, unit: "count/min", timestamp: now))
        await substrate.emit(metric: WorkoutMetric(kind: .distance, value: 250.0, unit: "m", timestamp: now.addingTimeInterval(10)))
        await substrate.emit(metric: WorkoutMetric(kind: .heartRate, value: 160, unit: "count/min", timestamp: now.addingTimeInterval(20)))

        let received = await collector.value
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(received.map(\.kind), [.heartRate, .distance, .heartRate])
    }

    func testHeartRateAggregatesIntoSummary() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())
        _ = try await controller.start()

        let now = Date(timeIntervalSinceReferenceDate: 0)
        await substrate.emit(metric: WorkoutMetric(kind: .heartRate, value: 140, unit: "count/min", timestamp: now))
        await substrate.emit(metric: WorkoutMetric(kind: .heartRate, value: 160, unit: "count/min", timestamp: now))
        await substrate.emit(metric: WorkoutMetric(kind: .distance, value: 1000, unit: "m", timestamp: now))

        // Drain the controller's metric stream so all three samples are
        // ingested before we end the workout.
        try await Self.drainAtLeast(3, from: controller.metrics)

        let summary = try await controller.end()
        XCTAssertEqual(summary.averageHeartRateBeatsPerMinute, 150)
        XCTAssertEqual(summary.peakHeartRateBeatsPerMinute, 160)
        XCTAssertEqual(summary.totalDistanceMeters, 1000)
    }

    // MARK: - State stream

    func testStateStreamEmitsOnGlassesSignalChange() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate, clock: Self.fixedClock())
        _ = try await controller.start()

        let collector = Task<WorkoutState?, Never> { [controller] in
            for await state in controller.states {
                if state.glassesConnected { return state }
            }
            return nil
        }

        await controller.reportGlassesSignal(.connected)
        let state = await collector.value
        XCTAssertEqual(state?.glassesConnected, true)
        XCTAssertEqual(state?.phase, .running)
    }

    // MARK: - Test helpers

    private static func fixedClock(at instant: TimeInterval = 0) -> @Sendable () -> Date {
        let date = Date(timeIntervalSinceReferenceDate: instant)
        return { date }
    }

    private static func steppingClock(start: TimeInterval, stepSeconds: TimeInterval) -> @Sendable () -> Date {
        let counter = StepCounter(start: start, step: stepSeconds)
        return { counter.next() }
    }

    private final class StepCounter: @unchecked Sendable {
        private var current: TimeInterval
        private let step: TimeInterval
        private let lock = NSLock()
        init(start: TimeInterval, step: TimeInterval) {
            self.current = start
            self.step = step
        }
        func next() -> Date {
            lock.lock()
            defer { lock.unlock() }
            let value = current
            current += step
            return Date(timeIntervalSinceReferenceDate: value)
        }
    }

    /// Collect `WorkoutState` snapshots emitted while `body` runs. Returns once
    /// `body` finishes; collector task is cancelled afterward.
    private static func collectStates(
        from controller: WorkoutController,
        while body: @Sendable () async throws -> Void
    ) async rethrows -> [WorkoutState] {
        let stateBox = StateBox()
        let collector = Task { [controller] in
            for await state in controller.states {
                await stateBox.append(state)
            }
        }
        try await body()
        // Give the collector a tick to drain.
        try? await Task.sleep(nanoseconds: 50_000_000)
        collector.cancel()
        return await stateBox.snapshot()
    }

    private actor StateBox {
        private var values: [WorkoutState] = []
        func append(_ value: WorkoutState) { values.append(value) }
        func snapshot() -> [WorkoutState] { values }
    }

    private static func drainAtLeast(
        _ count: Int,
        from stream: AsyncStream<WorkoutMetric>
    ) async throws {
        var seen = 0
        for await _ in stream {
            seen += 1
            if seen >= count { return }
        }
    }
}
