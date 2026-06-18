// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

/// Bridge tests: prove that Weiss's canonical `GlassesFrameTransport` can drive
/// the `WorkoutController.reportGlassesSignal` input via the
/// `GlassesConnectivitySignal.from(_:)` adapter without violating D4
/// (workout MUST NOT pause on glasses disconnect).
final class GlassesTransportBridgeTests: XCTestCase {

    func testConnectionStateMappingCoversAllCases() {
        XCTAssertEqual(GlassesConnectivitySignal.from(.connected), .connected)
        for state in [GlassesConnectionState.disconnected, .scanning, .connecting, .reconnecting, .failed] {
            if case .disconnected(let reason) = GlassesConnectivitySignal.from(state) {
                XCTAssertEqual(reason, state.rawValue)
            } else {
                XCTFail("Expected .disconnected for \(state)")
            }
        }
    }

    func testDropReasonMappingProducesStableLabels() {
        XCTAssertEqual(
            GlassesConnectivitySignal.from(droppedReason: .userInitiated),
            .disconnected(reason: "userInitiated")
        )
        XCTAssertEqual(
            GlassesConnectivitySignal.from(droppedReason: .linkLoss),
            .disconnected(reason: "linkLoss")
        )
        XCTAssertEqual(
            GlassesConnectivitySignal.from(droppedReason: .unknown(code: 42)),
            .disconnected(reason: "unknown(42)")
        )
    }

    func testStubTransportDropDoesNotPauseWorkoutPerD4() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate)
        _ = try await controller.start(activityType: .outdoorRun)

        let transport = StubGlassesTransport()
        try await transport.connect()

        // Drive the controller from the transport's connection-state stream
        // exactly as the watch view-model does in production.
        let bridge = Task {
            let stream = await transport.connectionStates()
            for await state in stream {
                await controller.reportGlassesSignal(.from(state))
            }
        }
        // Let the bridge see the initial `.connected` snapshot.
        try await Task.sleep(nanoseconds: 100_000_000)

        var phase = await controller.currentPhase()
        XCTAssertEqual(phase, .running)

        // Simulate a real link-loss drop. D4: workout MUST keep running.
        await transport.simulateDrop(reason: .linkLoss)
        try await Task.sleep(nanoseconds: 100_000_000)

        phase = await controller.currentPhase()
        XCTAssertEqual(phase, .running, "D4 violated: workout paused on glasses drop")
        let drops = await controller.recordedDisconnectCount()
        XCTAssertGreaterThanOrEqual(drops, 1)

        bridge.cancel()
        let summary = try await controller.end()
        XCTAssertGreaterThanOrEqual(summary.glassesDisconnectCount, 1)
    }
}
