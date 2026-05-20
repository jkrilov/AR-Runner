// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation

/// Thin watch-side facade over `GlassesFrameTransport`.
///
/// Routes lifecycle + per-tick metric updates from the workout pipeline into
/// whichever transport implementation is wired up (`ActiveLookGlassesAdapter`
/// in production, `StubGlassesTransport` in previews / debug). Holds no BLE
/// state of its own — that lives in the transport.
actor GlassesService {
    private let transport: any GlassesFrameTransport
    private(set) var activeLayoutID: String?
    private(set) var activeLayout: HUDLayout?
    private var throttle: HUDFieldThrottle
    private let now: @Sendable () -> Date

    init(
        transport: any GlassesFrameTransport,
        throttle: HUDFieldThrottle = HUDFieldThrottle(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.throttle = throttle
        self.now = now
    }

    var connectionState: GlassesConnectionState {
        get async { await transport.connectionState }
    }

    func connectionStates() async -> AsyncStream<GlassesConnectionState> {
        await transport.connectionStates()
    }

    func statusEvents() async -> AsyncStream<GlassesStatusEvent> {
        await transport.statusEvents()
    }

    func connect() async throws {
        try await transport.connect()
    }

    func disconnect() async throws {
        try await transport.disconnect()
    }

    /// Pick a curated D6 layout. Stores the ID so per-metric updates can be
    /// scoped to it without callers repeating the layout string everywhere.
    func selectLayout(id: String) async throws {
        try await transport.selectLayout(id: id)
        activeLayoutID = id
        activeLayout = HUDLayout.curatedPresets().first { $0.id == id }
        throttle.reset()
    }

    /// Convenience: activate the layout that backs a `RunningHUDPreset` so
    /// metric routing (`apply(metric:)`) can resolve `MetricKind → fieldIndex`
    /// against the same source of truth.
    func selectLayout(preset: RunningHUDPreset) async throws {
        try await transport.selectLayout(id: preset.layoutID)
        activeLayoutID = preset.layoutID
        activeLayout = preset.layout
        throttle.reset()
    }

    /// Fan-out entry point: map a `WorkoutMetric` into the active layout's
    /// slot index and push it as a `HUDFieldUpdate`. Silently drops when no
    /// layout is active, when the metric is not in the active layout, when
    /// the adapter is not connected, or when the throttle says wait. Never
    /// throws to the workout pipeline — BLE noise stays in BLE.
    func apply(metric: WorkoutMetric) async {
        guard let activeLayout, let activeLayoutID else { return }
        guard let slot = activeLayout.slots.firstIndex(where: { $0 == metric.kind }) else { return }
        guard let fieldIndex = UInt8(exactly: slot) else { return }
        guard await transport.connectionState == .connected else { return }
        guard throttle.shouldSend(fieldIndex: fieldIndex, now: now()) else { return }
        let update = HUDFieldUpdate(
            layoutID: activeLayoutID,
            fieldIndex: fieldIndex,
            value: Self.format(metric)
        )
        try? await transport.updateField(update)
    }

    func update(metric: WorkoutMetric, fieldIndex: UInt8, formatter: (WorkoutMetric) -> String) async throws {
        guard let activeLayoutID else { return }
        // No-op when the adapter is not connected so the workout pipeline
        // never sees BLE state. Throttle protects the link from per-tick
        // bursts: last-write-wins per fieldIndex at ~1 Hz.
        guard await transport.connectionState == .connected else { return }
        guard throttle.shouldSend(fieldIndex: fieldIndex, now: now()) else { return }
        let update = HUDFieldUpdate(
            layoutID: activeLayoutID,
            fieldIndex: fieldIndex,
            value: formatter(metric)
        )
        try await transport.updateField(update)
    }

    func update(_ update: HUDFieldUpdate) async throws {
        guard await transport.connectionState == .connected else { return }
        guard throttle.shouldSend(fieldIndex: update.fieldIndex, now: now()) else { return }
        try await transport.updateField(update)
    }

    /// Reset throttle state — called by the watch app on disconnect /
    /// reconnect so the next live update is delivered immediately.
    func resetThrottle() {
        throttle.reset()
    }

    /// Glanceable formatter for the HUD. Lives here so the watch UI's
    /// SwiftUI formatters and the glasses' field strings never drift.
    private static func format(_ metric: WorkoutMetric) -> String {
        switch metric.kind {
        case .heartRate:
            return String(Int(metric.value.rounded()))
        case .pace:
            // pace is sec/km — render as M:SS.
            let total = Int(metric.value.rounded())
            guard total > 0 else { return "--:--" }
            return String(format: "%d:%02d", total / 60, total % 60)
        case .distance:
            // metres → km, 2dp.
            return String(format: "%.2f", metric.value / 1000.0)
        case .duration:
            let total = Int(metric.value.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        case .cadence:
            return String(Int(metric.value.rounded()))
        case .elevation:
            return String(Int(metric.value.rounded()))
        case .energy:
            return String(Int(metric.value.rounded()))
        }
    }
}
