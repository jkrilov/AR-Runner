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

    init(transport: any GlassesFrameTransport) {
        self.transport = transport
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
    }

    func update(metric: WorkoutMetric, fieldIndex: UInt8, formatter: (WorkoutMetric) -> String) async throws {
        guard let activeLayoutID else { return }
        let update = HUDFieldUpdate(
            layoutID: activeLayoutID,
            fieldIndex: fieldIndex,
            value: formatter(metric)
        )
        try await transport.updateField(update)
    }

    func update(_ update: HUDFieldUpdate) async throws {
        try await transport.updateField(update)
    }
}
