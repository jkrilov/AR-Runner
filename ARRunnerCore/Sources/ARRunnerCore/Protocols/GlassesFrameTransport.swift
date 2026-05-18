// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Abstraction over the AR-glasses HUD link, per ADR-007 (`GlassesFrameProtocol`).
///
/// The protocol intentionally hides BLE / vendor specifics so that:
///   * Amber can mock it for the workout-metrics simulator
///   * Laughlin can drive it from `WorkoutSessionManager` without importing CoreBluetooth
///   * Weiss owns the only real implementation (`ActiveLookGlassesAdapter`, watch target)
///
/// Concurrency contract (per D8): every method is `async` and every type that
/// crosses the protocol surface is `Sendable`. Implementations are expected to
/// be actors or otherwise thread-safe.
public protocol GlassesFrameTransport: Sendable {
    /// Most-recent observed connection state (snapshot).
    var connectionState: GlassesConnectionState { get async }

    /// Hot stream of every connection-state transition, including the current
    /// value as the first element. Multiple subscribers are supported; each gets
    /// an independent backlog-replayed stream.
    func connectionStates() async -> AsyncStream<GlassesConnectionState>

    /// Hot stream of side-channel status events (battery, RSSI, drop reasons).
    /// Implementations must not block; events are best-effort and may coalesce.
    func statusEvents() async -> AsyncStream<GlassesStatusEvent>

    /// Begin scanning + connecting. Idempotent: a no-op while already
    /// `connected` or `connecting`.
    func connect() async throws

    /// Tear down the active link without affecting the workout.
    /// Idempotent.
    func disconnect() async throws

    /// Activate one of the curated D6 layouts that is already baked onto the
    /// glasses. The implementation is responsible for translating the string
    /// ID into the on-device numeric layout slot.
    func selectLayout(id: String) async throws

    /// Runtime hot path: push a single field-value update into the active
    /// layout. Per D6 this is a ~20–40 byte BLE write per call.
    func updateField(_ update: HUDFieldUpdate) async throws

    /// Convenience bulk variant. Default implementation issues calls serially;
    /// adapters may override to coalesce into a single BLE write.
    func updateFields(_ updates: [HUDFieldUpdate]) async throws

    /// v0.3 raw-text HUD path: write a sequence of pre-encoded ActiveLook
    /// command frames straight to the RX characteristic. Sidesteps the
    /// curated-layout machinery, which is unusable until Config-Generator
    /// bakes real layout slots onto the glasses
    /// (`CuratedLayoutCatalog` ships placeholder IDs in v0.2/v0.3).
    ///
    /// Built for `RunningHUDFrame.frames(for:)` output: `[clear, txt, txt,
    /// txt]`. Implementations should write frames in order; per-frame BLE
    /// failures may abort the rest of the sequence (the next tick will
    /// retry from the start).
    ///
    /// Default impl is a silent no-op so stubs / previews don't have to
    /// model BLE state. Real adapters override.
    func sendCommands(_ frames: [[UInt8]]) async throws

    /// Human-readable name of the currently-connected peripheral, if any.
    /// Returns `nil` when no link is established (or the underlying transport
    /// cannot supply a name — e.g. test stubs that don't model one). Used by
    /// the pre-run "Connect Glasses" UI to surface `Glasses: {Device Name}`
    /// once a pairing succeeds.
    var connectedDeviceName: String? { get async }
}

extension GlassesFrameTransport {
    public func updateFields(_ updates: [HUDFieldUpdate]) async throws {
        for update in updates {
            try await updateField(update)
        }
    }

    /// Default: no-op. Adapters that talk to real glasses override; test
    /// stubs that want to assert on the frame sequence also override.
    public func sendCommands(_ frames: [[UInt8]]) async throws {}

    /// Default: transports that don't model a device name (Linux test stubs,
    /// fakes) return `nil`. Real adapters override.
    public var connectedDeviceName: String? {
        get async { nil }
    }
}
