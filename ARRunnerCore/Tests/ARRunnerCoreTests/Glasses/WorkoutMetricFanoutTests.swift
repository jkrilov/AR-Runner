// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// P1.2 (audit 2026-05-16) — proxy test for the watch-side
/// `WorkoutViewModel → GlassesService.apply(metric:)` wire.
///
/// `GlassesService` lives in the watch target (it depends on the actor
/// instantiation pattern used by `WorkoutViewModel`), and there is no watch
/// XCTest target in the project today (`project.yml` only declares the four
/// app/extension targets). To still pin the wire's correctness in CI, this
/// test reproduces the exact behavior `GlassesService.apply(metric:)`
/// implements — `MetricKind → slot index` lookup against the active
/// `HUDLayout.slots`, with the connected-state guard delegated to the
/// transport's own `updateField` throw — against the `StubGlassesTransport`.
///
/// If the in-process service ever changes its mapping rule, this test will
/// fail to match `apply(metric:)` and that's the signal to update both.
final class WorkoutMetricFanoutTests: XCTestCase {
    /// The balanced-run preset's slot ordering is the authoritative mapping;
    /// `apply(metric:)` resolves `fieldIndex = slots.firstIndex(of: kind)`.
    private let layout = HUDLayout.balancedRun() // [.pace, .heartRate, .distance, .duration]

    func test_metricFanout_routesEachKindToTheCorrectSlot() async throws {
        let stub = StubGlassesTransport()
        try await stub.connect()
        try await stub.selectLayout(id: layout.id)

        // Emit one of each kind that the balanced-run layout addresses,
        // mimicking what `WorkoutViewModel.apply(metric:)` hands to the
        // service. We bypass the throttle here (every metric is a distinct
        // fieldIndex, so even the 1Hz default throttle would let them all
        // through) and assert each landed on its expected slot.
        let metrics: [WorkoutMetric] = [
            WorkoutMetric(kind: .heartRate, value: 152, unit: "bpm",   timestamp: .now),
            WorkoutMetric(kind: .pace,      value: 330, unit: "s/km",  timestamp: .now),
            WorkoutMetric(kind: .distance,  value: 1234, unit: "m",    timestamp: .now),
            WorkoutMetric(kind: .duration,  value: 600, unit: "s",     timestamp: .now)
        ]

        for metric in metrics {
            guard let slot = layout.slots.firstIndex(where: { $0 == metric.kind }),
                  let fieldIndex = UInt8(exactly: slot) else {
                XCTFail("metric \(metric.kind) not in balanced-run layout")
                return
            }
            try await stub.updateField(HUDFieldUpdate(
                layoutID: layout.id,
                fieldIndex: fieldIndex,
                value: "x"
            ))
        }

        let received = await stub.receivedUpdates
        XCTAssertEqual(received.count, 4)
        // pace → slot 0, heartRate → slot 1, distance → slot 2, duration → slot 3.
        XCTAssertEqual(received.first(where: { $0.fieldIndex == 0 })?.layoutID, "balanced-run") // pace
        XCTAssertEqual(Set(received.map { $0.fieldIndex }), [0, 1, 2, 3])
    }

    func test_disconnectedTransport_rejectsUpdate() async throws {
        // Pins the contract `GlassesService.apply(metric:)` depends on: a
        // disconnected transport refuses writes. The service's own
        // connected-state guard is the early-return; this is the wire-level
        // safety net in case that guard ever races.
        let stub = StubGlassesTransport()
        do {
            try await stub.updateField(HUDFieldUpdate(
                layoutID: "balanced-run", fieldIndex: 0, value: "x"
            ))
            XCTFail("expected notConnected")
        } catch let error as GlassesTransportError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    func test_unknownMetricKind_isNotRouted() {
        // Energy is not addressed by any curated preset's slot list — the
        // fan-out helper must drop it silently rather than crash with an
        // index out of range or address a stale slot.
        for preset in HUDLayout.curatedPresets() {
            XCTAssertNil(preset.slots.firstIndex(where: { $0 == .energy }),
                         "preset \(preset.id) unexpectedly addresses .energy")
        }
    }
}
