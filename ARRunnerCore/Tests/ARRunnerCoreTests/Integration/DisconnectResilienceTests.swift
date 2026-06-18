// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// v0.2 Workstream #4 — D4 Disconnect / Reconnect Resilience integration tests.
///
/// Anticipatory contract: this file is written BEFORE Weiss's auto-reconnect
/// loop and Laughlin's haptic-alert hook land. Each test either:
///   * Anchors the **current** D4 surface (must pass today and stay green), or
///   * Documents a **resilience-contract gap** with `XCTSkipIf(true, ...)`
///     and a `// EXPECTED-FAILING-UNTIL: v0.2 #4 implementation` marker so
///     Weiss + Laughlin know which assertion must turn green when their
///     resilience implementation lands. Skips keep CI green per the
///     greenfield-CI-stays-green rule while still encoding the contract.
///
/// Locked v0.2 decisions exercised here:
///   * **#2** — Glasses disconnect: keep recording + haptic alert; auto-reconnect
///     in background.
///   * **#5** — Post-run save flow: workout pauses on Finish; Save/Cancel/Resume.
///   * **#6** — Offline-capable: must work without phone/network. (Implicit —
///     no phone or network is wired in any test below.)
///
/// All tests build on the canonical `WorkoutController` + `MockGlassesFrame` +
/// `FakeHealthKitSubstrate` triplet; no canonical surface is modified.
final class DisconnectResilienceTests: XCTestCase {

    // MARK: - Helpers (intentionally duplicated from
    // WorkoutControllerIntegrationTests so this file is self-contained — see
    // Amber's history note on `Self`-capture region-isolation issues).

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

    private func bridgeMetrics(
        from controller: WorkoutController,
        to glasses: MockGlassesFrame,
        layoutID: String
    ) -> Task<Void, Never> {
        let stream = controller.metrics
        return Task {
            var fieldIndex: UInt8 = 0
            for await metric in stream {
                let update = HUDFieldUpdate(
                    layoutID: layoutID,
                    fieldIndex: fieldIndex,
                    value: formatMetricForResilience(metric)
                )
                fieldIndex = (fieldIndex &+ 1)
                try? await glasses.updateField(update)
            }
        }
    }

    /// Subscribe to the mock's status-event stream and tee every event into a
    /// `Collector` actor. Used to assert "exactly one `.dropped`" semantics.
    private func collectStatusEvents(
        from glasses: MockGlassesFrame
    ) async -> (collector: StatusEventCollector, task: Task<Void, Never>) {
        let collector = StatusEventCollector()
        let stream = await glasses.statusEvents()
        let task = Task {
            for await event in stream {
                await collector.append(event)
            }
        }
        return (collector, task)
    }
}

// MARK: - Free helpers (off the non-Sendable XCTestCase subclass)

private func formatMetricForResilience(_ metric: WorkoutMetric) -> String {
    switch metric.kind {
    case .heartRate, .cadence:
        return String(Int(metric.value.rounded()))
    case .distance, .elevation:
        return String(format: "%.1f", metric.value)
    case .speed:
        return String(format: "%.1f", metric.value)
    case .pace, .duration:
        let total = Int(metric.value.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    case .energy:
        return String(Int(metric.value.rounded()))
    }
}

/// Sendable accumulator for status-event tap.
private actor StatusEventCollector {
    private(set) var events: [GlassesStatusEvent] = []
    func append(_ event: GlassesStatusEvent) { events.append(event) }
    func snapshot() -> [GlassesStatusEvent] { events }
    var droppedCount: Int {
        events.filter {
            if case .dropped = $0 { return true }
            return false
        }.count
    }
    var reconnectedCount: Int {
        events.filter {
            if case .reconnected = $0 { return true }
            return false
        }.count
    }
}

// MARK: - Tests

extension DisconnectResilienceTests {

    // MARK: 1. Disconnect mid-workout — recording continues into substrate.
    //
    // D4 contract: while glasses are offline the workout MUST keep collecting
    // HR/pace/distance into the `WorkoutHealthSubstrate`. The HKWorkout
    // aggregates returned from `end(at:)` are unaffected by the HUD outage.
    func test_DisconnectMidWorkout_KeepsRecordingIntoSubstrate() async throws {
        let workoutID = UUID()
        // 8 ticks × 3 metrics each (HR + pace + distance) = 24 metrics total.
        let substrate = FakeHealthKitSubstrate(
            workoutID: workoutID,
            scenario: .steadyRun(heartRate: 152, paceSecPerKm: 305, tickCount: 8)
        )
        let glasses = MockGlassesFrame()
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        let metricBridge = bridgeMetrics(from: controller, to: glasses, layoutID: "balanced-run")
        defer {
            glassesBridge.cancel()
            metricBridge.cancel()
        }

        _ = try await controller.start(activityType: .outdoorRun)
        try await glasses.connect()
        try await glasses.selectLayout(id: "balanced-run")

        // Wait for at least 2 metric ticks (6 metrics) before yanking the link.
        let sawEarlyMetrics = await waitUntil {
            await glasses.receivedUpdates.count >= 6
        }
        XCTAssertTrue(sawEarlyMetrics, "Pre-disconnect HUD writes did not arrive")

        let updatesBeforeDrop = await glasses.receivedUpdates.count
        await glasses.simulateDisconnect(reason: .linkLoss)

        // Wait for the bridge task to forward the disconnect into the controller.
        let dropObserved = await waitUntil {
            await controller.recordedDisconnectCount() >= 1
        }
        XCTAssertTrue(dropObserved, "Bridge must forward disconnect to controller")

        // Substrate keeps emitting metrics regardless of HUD state.
        let scenarioFinished = await waitUntil(timeoutNanos: 3_000_000_000) {
            await substrate.isScenarioComplete
        }
        XCTAssertTrue(scenarioFinished, "Substrate replay must complete despite HUD outage")

        // Phase stays running across the outage.
        let phase = await controller.currentPhase()
        XCTAssertEqual(phase, .running,
                       "D4: phase MUST remain .running for the duration of an HUD outage")

        let summary = try await controller.end()
        XCTAssertEqual(summary.healthKitWorkoutID, workoutID)
        XCTAssertGreaterThanOrEqual(summary.glassesDisconnectCount, 1,
                                    "Disconnect must be reflected in summary count")

        // No NEW HUD writes once the link dropped — the workout kept
        // recording into the substrate, but BLE writes are a no-op until
        // reconnect (they throw `.notConnected` and are swallowed by the
        // bridge per D4).
        let updatesAfterDrop = await glasses.receivedUpdates.count
        XCTAssertEqual(updatesAfterDrop, updatesBeforeDrop,
                       "HUD writes during outage must not silently buffer onto the mock")
    }

    // MARK: 2. Disconnect emits `.dropped` exactly once.
    //
    // Drives Laughlin's haptic-trigger point: one disconnect → one alert.
    // Drives Laughlin's "HUD offline" UI indicator (`WorkoutState.glassesConnected`).
    func test_Disconnect_EmitsDroppedExactlyOnce() async throws {
        let substrate = FakeHealthKitSubstrate(scenario: .ended)
        let glasses = MockGlassesFrame()
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        defer { glassesBridge.cancel() }

        let (statusCollector, statusTask) = await collectStatusEvents(from: glasses)
        defer { statusTask.cancel() }

        _ = try await controller.start(activityType: .outdoorRun)
        try await glasses.connect()

        // Repeated `simulateDisconnect` while already disconnected must be a
        // no-op — the mock guards on `connectionState == .connected`.
        await glasses.simulateDisconnect(reason: .linkLoss)
        await glasses.simulateDisconnect(reason: .linkLoss)
        await glasses.simulateDisconnect(reason: .peerPoweredOff)

        // Give the status stream a moment to drain.
        let observed = await waitUntil {
            await statusCollector.droppedCount >= 1
        }
        XCTAssertTrue(observed)

        let dropCount = await statusCollector.droppedCount
        XCTAssertEqual(dropCount, 1,
                       "Exactly one `.dropped` must surface for a single outage — guards 1:1 haptic trigger")

        // Controller-side: `glassesDisconnectCount` should also be exactly 1.
        let controllerCount = await controller.recordedDisconnectCount()
        XCTAssertEqual(controllerCount, 1,
                       "Controller-side disconnect count must match status-event count")

        _ = try await controller.end()
    }

    // MARK: 3. Reconnect — `.reconnected` event + seamless workout state.
    //
    // Documents what the controller sees when the auto-reconnect (Weiss) lands.
    // Today this is exercised by the manual `simulateReconnect` driver.
    func test_Reconnect_EmitsReconnectedAndContinuesWorkoutSeamlessly() async throws {
        let substrate = FakeHealthKitSubstrate(
            scenario: .steadyRun(heartRate: 148, paceSecPerKm: 310, tickCount: 4)
        )
        let glasses = MockGlassesFrame()
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        let metricBridge = bridgeMetrics(from: controller, to: glasses, layoutID: "balanced-run")
        defer {
            glassesBridge.cancel()
            metricBridge.cancel()
        }

        let (statusCollector, statusTask) = await collectStatusEvents(from: glasses)
        defer { statusTask.cancel() }

        _ = try await controller.start(activityType: .outdoorRun)
        try await glasses.connect()
        try await glasses.selectLayout(id: "balanced-run")

        await glasses.simulateDisconnect(reason: .linkLoss)
        await glasses.simulateReconnect(after: 1.25)

        // After manual reconnect, transport must be `.connected`, the
        // controller's `glassesConnected` flag must flip back to true, and
        // the disconnect must have been counted.
        let reconnected = await waitUntil {
            let stateOK = await glasses.connectionState == .connected
            let phaseOK = await controller.currentPhase() == .running
            let countOK = await controller.recordedDisconnectCount() >= 1
            return stateOK && phaseOK && countOK
        }
        XCTAssertTrue(reconnected)

        // Wait for the status stream to drain both events.
        let statusObserved = await waitUntil {
            let drops = await statusCollector.droppedCount
            let recons = await statusCollector.reconnectedCount
            return drops == 1 && recons == 1
        }
        XCTAssertTrue(statusObserved)

        let reconnectCount = await statusCollector.reconnectedCount
        XCTAssertEqual(reconnectCount, 1,
                       "Exactly one `.reconnected` per disconnect/reconnect cycle")

        // GAP: The transport surface does NOT auto-re-apply the previously
        // active layout after reconnect. Tests must manually re-`selectLayout`.
        // See `test_Reconnect_AutoReappliesPreviousLayout_ExpectedFailing`
        // below for the contract Weiss/Laughlin must close.
        try await glasses.selectLayout(id: "balanced-run")

        let scenarioDone = await waitUntil { await substrate.isScenarioComplete }
        XCTAssertTrue(scenarioDone)

        let summary = try await controller.end()
        XCTAssertEqual(summary.glassesDisconnectCount, 1)
    }

    // MARK: 4a. Disconnect at boundaries — pre-begin (before `start`).
    //
    // Documents an observed contract gap: `reportGlassesSignal` does NOT gate
    // on workout phase. A pre-begin disconnect WILL bump `glassesConnected`
    // and emit a state snapshot with `phase == .idle`. Phase itself is never
    // perturbed — only the HUD flag is. Captured here so Weiss/Laughlin know
    // exactly what the surface does pre-`start`.
    func test_DisconnectBoundary_PreBegin_DoesNotPerturbPhase() async throws {
        let substrate = FakeHealthKitSubstrate(scenario: .ended)
        let glasses = MockGlassesFrame()
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        defer { glassesBridge.cancel() }

        // Connect glasses BEFORE starting the workout.
        try await glasses.connect()
        let connectedSeen = await waitUntil {
            // `connect()` cycles through scanning → connecting → connected;
            // each maps via `GlassesConnectivitySignal.from(_:)`.
            await glasses.connectionState == .connected
        }
        XCTAssertTrue(connectedSeen)

        await glasses.simulateDisconnect(reason: .hostUnavailable)

        // Phase stayed `.idle` because `reportGlassesSignal` never touches it.
        let phase = await controller.currentPhase()
        XCTAssertEqual(phase, .idle,
                       "Pre-begin disconnect must NOT mutate phase")

        // Now start: `start` must succeed, and the post-begin disconnect
        // counter starts fresh from whatever the pre-begin signal traffic
        // accumulated. (Documented surface: counter is global, not
        // session-scoped — see contract-gap finding #G3.)
        _ = try await controller.start(activityType: .outdoorRun)
        let postStartPhase = await controller.currentPhase()
        XCTAssertEqual(postStartPhase, .running)

        _ = try await controller.end()
    }

    // MARK: 4b. Disconnect at boundaries — during paused workout (decision #5).
    //
    // Per decision #5 the workout pauses when the user opens the Finish menu.
    // A drop while the menu is open must (a) not resume the workout, (b) not
    // change the phase to `.running`, (c) still increment the disconnect
    // counter, (d) leave the workout end-able cleanly via Save.
    func test_DisconnectBoundary_DuringPaused_KeepsPausedAndCounts() async throws {
        let substrate = FakeHealthKitSubstrate(
            scenario: .steadyRun(heartRate: 150, paceSecPerKm: 300, tickCount: 3)
        )
        let glasses = MockGlassesFrame()
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        defer { glassesBridge.cancel() }

        _ = try await controller.start(activityType: .outdoorRun)
        try await glasses.connect()

        try await controller.pause()
        let pausedPhase = await controller.currentPhase()
        XCTAssertEqual(pausedPhase, .paused)

        await glasses.simulateDisconnect(reason: .linkLoss)

        // Phase stays paused, count increments.
        let stillPaused = await waitUntil {
            let phaseOK = await controller.currentPhase() == .paused
            let countOK = await controller.recordedDisconnectCount() >= 1
            return phaseOK && countOK
        }
        XCTAssertTrue(stillPaused, "Phase must remain .paused and disconnect count must increment")

        // Save → end while paused (decision #5: workout pauses on Finish; Save).
        let summary = try await controller.end()
        XCTAssertEqual(summary.sport, .outdoorRun)
        XCTAssertGreaterThanOrEqual(summary.glassesDisconnectCount, 1)
    }

    // MARK: 4c. Disconnect at boundaries — during the finish flow.
    //
    // Decision #5 finish menu: the workout is paused; user picks Save → end()
    // is called. A drop arriving in the narrow window AFTER end() begins must
    // not crash and must not leave the substrate in a half-ended state.
    func test_DisconnectBoundary_DuringFinish_DoesNotCorruptEnd() async throws {
        let substrate = FakeHealthKitSubstrate(scenario: .ended)
        let glasses = MockGlassesFrame()
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        defer { glassesBridge.cancel() }

        _ = try await controller.start(activityType: .outdoorRun)
        try await glasses.connect()
        try await controller.pause()

        // Race a disconnect against the end() call.
        async let endResult = controller.end()
        await glasses.simulateDisconnect(reason: .userInitiated)
        let summary = try await endResult

        XCTAssertEqual(summary.sport, .outdoorRun)
        let finalPhase = await controller.currentPhase()
        XCTAssertEqual(finalPhase, .ended,
                       "Drop racing end() must not leave the controller in a non-terminal phase")
    }

    // MARK: 5. Multiple disconnect/reconnect cycles in one workout.
    //
    // Asserts no state leak: `glassesDisconnectCount` increments by exactly
    // one per cycle, status events stay 1:1, and the workout never aborts.
    func test_MultipleDisconnectReconnectCycles_NoStateDrift() async throws {
        let substrate = FakeHealthKitSubstrate(
            scenario: .steadyRun(heartRate: 150, paceSecPerKm: 300, tickCount: 12)
        )
        let glasses = MockGlassesFrame()
        let controller = WorkoutController(substrate: substrate)

        let glassesBridge = await bridgeGlasses(glasses, into: controller)
        let metricBridge = bridgeMetrics(from: controller, to: glasses, layoutID: "balanced-run")
        defer {
            glassesBridge.cancel()
            metricBridge.cancel()
        }

        let (statusCollector, statusTask) = await collectStatusEvents(from: glasses)
        defer { statusTask.cancel() }

        _ = try await controller.start(activityType: .outdoorRun)
        try await glasses.connect()
        try await glasses.selectLayout(id: "balanced-run")

        let cycles = 4
        for cycle in 0..<cycles {
            await glasses.simulateDisconnect(reason: .linkLoss)
            await glasses.simulateReconnect(after: 0.25)
            // Re-apply layout because the transport doesn't auto-reapply
            // (contract gap — see expected-failing test below).
            try await glasses.selectLayout(id: "balanced-run")

            // Phase stays .running across every cycle.
            let phase = await controller.currentPhase()
            XCTAssertEqual(phase, .running, "Phase drift detected at cycle \(cycle)")
        }

        // Wait for status events to drain AND the bridge to forward all
        // disconnect signals into the controller's count.
        let saw = await waitUntil(timeoutNanos: 3_000_000_000) {
            let drops = await statusCollector.droppedCount
            let recons = await statusCollector.reconnectedCount
            let controllerDrops = await controller.recordedDisconnectCount()
            return drops == cycles && recons == cycles && controllerDrops == cycles
        }
        XCTAssertTrue(saw, "Expected \(cycles) drops + \(cycles) reconnects in status stream and controller count")

        let dropCount = await statusCollector.droppedCount
        let reconCount = await statusCollector.reconnectedCount
        XCTAssertEqual(dropCount, cycles)
        XCTAssertEqual(reconCount, cycles)

        let summary = try await controller.end()
        XCTAssertEqual(summary.glassesDisconnectCount, cycles,
                       "Exactly one count increment per disconnect cycle — no double-counting, no drops")

        // No leak: per-cycle layout writes accumulated linearly (1 initial + cycles re-applies).
        let layouts = await glasses.selectedLayouts
        XCTAssertEqual(layouts.count, 1 + cycles)
        XCTAssertTrue(layouts.allSatisfy { $0 == "balanced-run" })
    }

    // MARK: - EXPECTED-FAILING contract anticipation tests
    //
    // The three tests below encode resilience contracts that are NOT yet
    // implemented. They are skipped to keep CI green; when Weiss / Laughlin
    // ship the implementation, the reviewer must:
    //   1. Delete the `try XCTSkipIf(...)` line.
    //   2. Run the test — it should pass.
    // If a test still fails after removing the skip, the implementation does
    // not satisfy the contract this file pins down.

    // CONTRACT GREEN (v0.2 #4 — Weiss): a transport-level disconnect (no
    // manual `simulateReconnect`) must trigger an auto-reconnect attempt
    // that lands within the configured backoff window. The transport-level
    // contract is: opt into auto-reconnect at construction time
    // (`MockGlassesFrame(autoReconnect: true, ...)`); the real
    // `ActiveLookGlassesAdapter` does this unconditionally on every CB
    // disconnect callback (see `scheduleReconnect()` /`runReconnectLoop()`
    // in `ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift`).
    func test_AutoReconnectAfterTransportDrop() async throws {
        let substrate = FakeHealthKitSubstrate(scenario: .ended)
        let glasses = MockGlassesFrame(autoReconnect: true, autoReconnectDelay: 0.05)
        let controller = WorkoutController(substrate: substrate)
        let bridge = await bridgeGlasses(glasses, into: controller)
        defer { bridge.cancel() }

        _ = try await controller.start(activityType: .outdoorRun)
        try await glasses.connect()

        // Drop the link and then DO NOT manually call `simulateReconnect`.
        await glasses.simulateDisconnect(reason: .linkLoss)

        // The transport's auto-reconnect loop must restore `.connected`
        // within a generous 5s window.
        let recovered = await waitUntil(timeoutNanos: 5_000_000_000) {
            await glasses.connectionState == .connected
        }
        XCTAssertTrue(recovered, "Transport must auto-reconnect after a link-loss drop")

        _ = try await controller.end()
    }

    // CONTRACT GREEN (v0.2 #4 — Weiss): after a reconnect, the previously-
    // active layout must be re-applied automatically. The real adapter does
    // this off `activeLayoutDeviceID` in `handleCharacteristicsDiscovered`;
    // the mock mirrors it via `autoReapplyLayout: true`.
    func test_Reconnect_AutoReappliesPreviousLayout() async throws {
        let substrate = FakeHealthKitSubstrate(scenario: .ended)
        let glasses = MockGlassesFrame(autoReapplyLayout: true)

        try await glasses.connect()
        try await glasses.selectLayout(id: "balanced-run")

        await glasses.simulateDisconnect(reason: .linkLoss)
        await glasses.simulateReconnect(after: 0.5)

        // Post-reconnect, the transport should have re-issued `selectLayout`
        // for "balanced-run" without the caller asking.
        let layouts = await glasses.selectedLayouts
        XCTAssertEqual(layouts.count, 2,
                       "Auto-re-apply: one initial select + one post-reconnect replay")
        XCTAssertEqual(layouts.last, "balanced-run")

        _ = substrate // keep symmetry with sibling tests
    }

    // EXPECTED-FAILING-UNTIL: deferred — architectural pivot in v0.2 #4.
    // Resolution: the watch view-model (`WorkoutViewModel.handle(statusEvent:)`
    // in `ARRunnerWatch/Workout/WorkoutViewModel.swift`) consumes
    // `transport.statusEvents()` directly and fires the haptic on `.dropped`
    // with a 10s debounce. No `controller.alerts` stream was added — the
    // 1:1 haptic-per-outage contract is already pinned by
    // `test_Disconnect_EmitsDroppedExactlyOnce` above (one `.dropped` per
    // outage → one haptic). If a Core-level alerts stream is desired in a
    // future slice, this skip can be lifted and the test body fleshed out.
    func test_HapticAlertHook_OnDisconnect_ExpectedFailing() async throws {
        try XCTSkipIf(
            true,
            "DEFERRED — v0.2 #4 ships haptics in the watch view-model off transport.statusEvents(); no controller.alerts stream. 1:1 contract is covered by test_Disconnect_EmitsDroppedExactlyOnce."
        )

        // When implemented, the test will look approximately like this
        // (commented out so the file compiles today; uncomment + delete the
        // skip when the API lands):
        //
        // let controller = WorkoutController(substrate: ...)
        // var alertCount = 0
        // let alertTask = Task {
        //     for await alert in controller.alerts where alert == .glassesDropped {
        //         alertCount += 1
        //     }
        // }
        // _ = try await controller.start(activityType: .outdoorRun)
        // try await glasses.connect()
        // await glasses.simulateDisconnect(reason: .linkLoss)
        // _ = await waitUntil { alertCount >= 1 }
        // XCTAssertEqual(alertCount, 1)
        // alertTask.cancel()
    }
}
