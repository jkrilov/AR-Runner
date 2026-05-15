// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// End-to-end integration tests wiring the QA mocks (`MockGlassesFrame` +
/// `FakeHealthKitSubstrate` + `InMemoryARMetadataStore`) into the canonical
/// `WorkoutController` shipped in PR #7.
///
/// Targets:
/// - **D4** workout continues across glasses disconnect/reconnect; drops are
///   logged but never abort the run.
/// - **D6** runtime BLE traffic is just `HUDFieldUpdate` writes; the mock
///   records each one for after-the-fact assertions.
/// - **D9** the post-run `WorkoutSummary.healthKitWorkoutID` is the stable
///   UUID returned by the substrate, and the metadata side-store can be
///   keyed by it.
final class WorkoutControllerIntegrationTests: XCTestCase {

    // MARK: - Helpers

    /// Spin until `condition()` is true or `timeoutNanos` elapses.
    private func waitUntil(
        timeoutNanos: UInt64 = 2_000_000_000,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanos
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return await condition()
    }

    /// Bridge the mock glasses' connection-state stream into the canonical
    /// controller via `GlassesConnectivitySignal.from(_:)`. Returns the task
    /// so the test can cancel it during teardown.
    private func bridgeGlasses(
        _ glasses: MockGlassesFrame,
        into controller: WorkoutController
    ) async -> Task<Void, Never> {
        let stream = await glasses.connectionStates()
        return Task {
            for await state in stream {
                let signal = GlassesConnectivitySignal.from(state)
                await controller.reportGlassesSignal(signal)
            }
        }
    }

    /// Forward substrate metric emissions into the glasses as `HUDFieldUpdate`s
    /// so D6 traffic is observable on the mock. Returns the task for teardown.
    private func bridgeMetrics(
        from substrate: FakeHealthKitSubstrate,
        to glasses: MockGlassesFrame,
        layoutID: String
    ) -> Task<Void, Never> {
        let stream = substrate.metricEvents
        return Task {
            var fieldIndex: UInt8 = 0
            for await metric in stream {
                let update = HUDFieldUpdate(
                    layoutID: layoutID,
                    fieldIndex: fieldIndex,
                    value: formatMetricImpl(metric)
                )
                fieldIndex = (fieldIndex &+ 1)
                // Best-effort write; per D4 a glasses error must not abort the run.
                try? await glasses.updateField(update)
            }
        }
    }

    // formatMetric is defined as a free function below to keep it out of the
    // non-`Sendable` XCTestCase subclass — see note on `formatMetricImpl`.
}

/// Free function (not on the non-`Sendable` XCTestCase subclass) so the
/// region-based isolation checker doesn't choke on the cross-actor closure
/// capture in `bridgeMetrics`.
private func formatMetricImpl(_ metric: WorkoutMetric) -> String {
    switch metric.kind {
    case .heartRate, .cadence:
        return String(Int(metric.value.rounded()))
    case .distance, .elevation:
        return String(format: "%.1f", metric.value)
    case .pace, .duration:
        let total = Int(metric.value.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

extension WorkoutControllerIntegrationTests {

    // MARK: - D4 happy path: disconnect mid-run, reconnect, finish

    func testD4HappyPath_DisconnectMidRun_ReconnectAndEndsWithStableSummaryUUID() async throws {
        let workoutID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let substrate = FakeHealthKitSubstrate(
            workoutID: workoutID,
            scenario: .steadyRun(heartRate: 150, paceSecPerKm: 300, tickCount: 6)
        )
        let glasses = MockGlassesFrame()
        let metadataStore = InMemoryARMetadataStore()
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        let metricBridge = bridgeMetrics(from: substrate, to: glasses, layoutID: "balanced-run")
        defer {
            glassesBridge.cancel()
            metricBridge.cancel()
        }

        // 1. Workout starts.
        _ = try await controller.start(activityType: .running)

        // 2. Glasses connect.
        try await glasses.connect()
        try await glasses.selectLayout(id: "balanced-run")

        // Wait until at least a couple of metric writes have flowed to the
        // glasses before injecting the disconnect — otherwise we test nothing.
        let sawEarlyTraffic = await waitUntil {
            await glasses.receivedUpdates.count >= 2
        }
        XCTAssertTrue(sawEarlyTraffic, "Expected metric updates to reach glasses before disconnect")

        // 3. D4 disconnect mid-run. Workout MUST continue.
        await glasses.simulateDisconnect(reason: .linkLoss)

        // Drain the rest of the scenario; controller must not throw.
        let scenarioFinished = await waitUntil {
            await substrate.isScenarioComplete
        }
        XCTAssertTrue(scenarioFinished, "Scenario replay did not finish in time")

        // Workout phase must still be `.running` despite the HUD being offline.
        let phaseDuringOutage = await controller.currentPhase()
        XCTAssertEqual(phaseDuringOutage, .running, "D4: workout MUST stay running while glasses are offline")

        // 4. Glasses reconnect.
        await glasses.simulateReconnect(after: 0.5)
        try await glasses.selectLayout(id: "balanced-run")

        // Wait for the controller to observe the reconnect and flip
        // `glassesConnected` back to true.
        let saw_HUD_reconnect = await waitUntil {
            let phase = await controller.currentPhase()
            let drops = await controller.recordedDisconnectCount()
            return phase == .running && drops >= 1
        }
        XCTAssertTrue(saw_HUD_reconnect)

        // 5. End workout — summary must be keyed by the stable HK UUID (D9).
        let summary = try await controller.end()

        XCTAssertEqual(summary.healthKitWorkoutID, workoutID,
                       "D9: summary.healthKitWorkoutID must equal substrate's HK UUID")
        XCTAssertEqual(summary.sport, .running)
        XCTAssertGreaterThanOrEqual(summary.glassesDisconnectCount, 1,
                                    "D4: at least one disconnect must be recorded on the summary")

        // 6. D9 side-store round-trip: write metadata keyed by HK UUID and
        // read it back. Proves the join key is stable across substrate + store.
        let metadata = ARWorkoutMetadata(
            layoutID: "balanced-run",
            bleDropCount: summary.glassesDisconnectCount,
            glassesBatteryAtEnd: 78
        )
        try await metadataStore.saveMetadata(metadata, for: summary.healthKitWorkoutID)
        let loaded = try await metadataStore.loadMetadata(for: summary.healthKitWorkoutID)
        XCTAssertEqual(loaded, metadata)

        // D6 sanity: every recorded BLE write is a `HUDFieldUpdate` against
        // the active layout. No surprise payloads.
        let updates = await glasses.receivedUpdates
        XCTAssertFalse(updates.isEmpty)
        XCTAssertTrue(updates.allSatisfy { $0.layoutID == "balanced-run" })
    }

    // MARK: - D4: connect failure at start does not abort the workout

    func testConnectFailureAtStartDoesNotAbortWorkout() async throws {
        let substrate = FakeHealthKitSubstrate(
            scenario: .steadyRun(heartRate: 145, paceSecPerKm: 320, tickCount: 3)
        )
        let glasses = MockGlassesFrame(
            failures: MockGlassesFailureConfig(failNextConnect: .connectFailed)
        )
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        defer { glassesBridge.cancel() }

        _ = try await controller.start(activityType: .running)

        // Glasses connect attempt fails — controller MUST NOT abort.
        do {
            try await glasses.connect()
            XCTFail("Expected mock glasses connect() to throw")
        } catch {
            // Expected.
        }

        // Workout must still be running.
        let phase = await controller.currentPhase()
        XCTAssertEqual(phase, .running, "D4: connect failure must not abort the workout")

        let done = await waitUntil { await substrate.isScenarioComplete }
        XCTAssertTrue(done)

        let summary = try await controller.end()
        XCTAssertEqual(summary.sport, .running)

        // No metric updates ever reached the glasses since we never connected.
        let updates = await glasses.receivedUpdates
        XCTAssertTrue(updates.isEmpty, "No field updates should reach glasses while disconnected")
    }

    // MARK: - Mock self-tests (cheap sanity coverage on the doubles themselves)

    func testMockGlassesRecordsLayoutsAndFieldUpdates() async throws {
        let glasses = MockGlassesFrame()
        try await glasses.connect()
        try await glasses.selectLayout(id: "minimal-run")
        try await glasses.updateField(HUDFieldUpdate(layoutID: "minimal-run", fieldIndex: 0, value: "150"))
        try await glasses.updateField(HUDFieldUpdate(layoutID: "minimal-run", fieldIndex: 1, value: "5:00"))

        let layouts = await glasses.selectedLayouts
        let updates = await glasses.receivedUpdates
        XCTAssertEqual(layouts, ["minimal-run"])
        XCTAssertEqual(updates.map(\.value), ["150", "5:00"])

        let state = await glasses.connectionState
        XCTAssertEqual(state, .connected)
    }

    func testMockGlassesOneShotConnectFailureClearsAfterFiring() async {
        let glasses = MockGlassesFrame(
            failures: MockGlassesFailureConfig(failNextConnect: .connectFailed)
        )
        do {
            try await glasses.connect()
            XCTFail("Expected connect() to throw")
        } catch {
            // Expected.
        }
        // Failure is one-shot — second attempt succeeds.
        do {
            try await glasses.connect()
        } catch {
            XCTFail("Second connect() should succeed once failure is consumed")
        }
    }

    func testFakeSubstrateProducesExpectedMetricCounts() async throws {
        let substrate = FakeHealthKitSubstrate(
            scenario: .intervals(highHR: 170, lowHR: 130, workTicks: 2, restTicks: 1, repeats: 2)
        )

        actor Collector {
            var items: [WorkoutMetric] = []
            func append(_ m: WorkoutMetric) { items.append(m) }
            func snapshot() -> [WorkoutMetric] { items }
        }
        let collector = Collector()

        let collectorTask = Task {
            for await metric in substrate.metricEvents {
                await collector.append(metric)
            }
        }

        try await substrate.begin(sport: .running, startedAt: Date())
        let done = await waitUntil { await substrate.isScenarioComplete }
        XCTAssertTrue(done)
        _ = try await substrate.end(at: Date())
        _ = await collectorTask.value

        let collected = await collector.snapshot()
        // 2 work + 1 rest = 3 ticks per repeat * 2 = 6 metrics.
        XCTAssertEqual(collected.count, 6)
        XCTAssertTrue(collected.allSatisfy { $0.kind == .heartRate })
    }

    func testFakeSubstrateEndReturnsResultKeyedByConfiguredUUID() async throws {
        let id = UUID(uuidString: "ABCDEF12-1234-1234-1234-1234567890AB")!
        let substrate = FakeHealthKitSubstrate(workoutID: id, scenario: .ended)

        let start = Date(timeIntervalSinceReferenceDate: 0)
        try await substrate.begin(sport: .running, startedAt: start)
        let result = try await substrate.end(at: start.addingTimeInterval(60))

        XCTAssertEqual(result.healthKitWorkoutID, id)
        XCTAssertEqual(result.activeDuration, 60, accuracy: 0.001)
    }
}
