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
    /// Display context for unit-aware field formatting. Set by the workout
    /// pipeline at start (and whenever the unit preference changes) so the
    /// glasses' field strings match the watch UI's metric/imperial choice.
    private var unitSystem: UnitSystem = .metric
    private var activity: ActivityKind = .running

    init(
        transport: any GlassesFrameTransport,
        throttle: HUDFieldThrottle = HUDFieldThrottle(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.throttle = throttle
        self.now = now
    }

    /// Update the unit system + activity used to format per-field HUD values.
    /// Called on workout start and on unit-preference changes so the glasses
    /// never drift from the wrist display (km/h vs mph, min/km vs min/mi).
    func configure(unitSystem: UnitSystem, activity: ActivityKind) {
        self.unitSystem = unitSystem
        self.activity = activity
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
            value: format(metric)
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
    /// SwiftUI formatters and the glasses' field strings never drift —
    /// every metric is rendered through the shared `RunMetricFormatting`
    /// (and `RunningHUDFrame`) Core helpers using the active `unitSystem`
    /// and `activity`, so km/h↔mph, min/km↔min/mi, km↔mi and m↔ft all
    /// follow the user's measurement-system choice.
    private func format(_ metric: WorkoutMetric) -> String {
        switch metric.kind {
        case .heartRate:
            return RunningHUDFrame.formatHeartRate(metric.value)
        case .pace:
            // pace metric value is sec/km — unit-aware to min/km or min/mi.
            return RunMetricFormatting.formatPace(
                secondsPerKilometer: metric.value, unitSystem: unitSystem
            )
        case .speed:
            // speed metric value is m/s — unit-aware to km/h or mph.
            return RunMetricFormatting.formatSpeed(
                metersPerSecond: metric.value, unitSystem: unitSystem
            )
        case .distance:
            return RunMetricFormatting.formatDistance(
                meters: metric.value, unitSystem: unitSystem
            )
        case .duration:
            return RunningHUDFrame.formatElapsed(metric.value)
        case .cadence:
            return RunningHUDFrame.formatCadence(metric.value, activity: activity)
        case .elevation:
            return RunMetricFormatting.formatElevation(
                meters: metric.value, unitSystem: unitSystem
            )
        case .energy:
            return String(format: "%.0f kcal", metric.value)
        }
    }
}
