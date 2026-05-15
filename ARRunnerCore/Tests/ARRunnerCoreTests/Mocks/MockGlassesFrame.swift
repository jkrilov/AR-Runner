// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import ARRunnerCore

/// Errors the mock can be configured to throw on next call.
public enum MockGlassesError: Error, Equatable, Sendable {
    case writeFailed
    case connectFailed
    case selectLayoutFailed
}

/// One-shot failure-injection slots. Each populated slot fires on the next
/// matching call and is then cleared automatically.
public struct MockGlassesFailureConfig: Sendable {
    public var failNextConnect: MockGlassesError?
    public var failNextSelectLayout: MockGlassesError?
    public var failNextUpdateField: MockGlassesError?

    public init(
        failNextConnect: MockGlassesError? = nil,
        failNextSelectLayout: MockGlassesError? = nil,
        failNextUpdateField: MockGlassesError? = nil
    ) {
        self.failNextConnect = failNextConnect
        self.failNextSelectLayout = failNextSelectLayout
        self.failNextUpdateField = failNextUpdateField
    }
}

/// Richer in-memory test double for `GlassesFrameTransport`.
///
/// Why this exists alongside `StubGlassesTransport` (Weiss, PR #5):
///   * `StubGlassesTransport` is the canonical happy-path stub for unit tests.
///   * `MockGlassesFrame` adds the scenario controls QA needs to exercise
///     ADR-007 / D4 corner cases without real BLE:
///       - On-demand `simulateDisconnect` / `simulateReconnect` (with paired
///         `GlassesStatusEvent` emission so observers see drop reasons).
///       - One-shot failure injection on `connect`, `selectLayout`, and
///         `updateField`, so error-recovery paths get coverage.
///       - Multi-subscriber connection-state stream that replays current
///         state to late observers (matches Weiss's contract).
///       - Recorded `selectLayout` IDs and `updateField` payloads for
///         post-hoc assertions about D6 BLE traffic shape.
///
/// All state is actor-isolated; concurrency follows D8 (no `@unchecked`).
public actor MockGlassesFrame: GlassesFrameTransport {
    public private(set) var connectionState: GlassesConnectionState = .disconnected
    public private(set) var receivedUpdates: [HUDFieldUpdate] = []
    public private(set) var selectedLayouts: [String] = []
    public private(set) var connectCallCount = 0
    public private(set) var disconnectCallCount = 0

    private var failures: MockGlassesFailureConfig
    private var stateContinuations: [UUID: AsyncStream<GlassesConnectionState>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<GlassesStatusEvent>.Continuation] = [:]
    private let clock: @Sendable () -> Date

    public init(
        failures: MockGlassesFailureConfig = MockGlassesFailureConfig(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.failures = failures
        self.clock = clock
    }

    // MARK: - GlassesFrameTransport

    public func connectionStates() async -> AsyncStream<GlassesConnectionState> {
        let id = UUID()
        let snapshot = connectionState
        return AsyncStream { continuation in
            self.register(stateContinuation: continuation, id: id, snapshot: snapshot)
        }
    }

    public func statusEvents() async -> AsyncStream<GlassesStatusEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.register(statusContinuation: continuation, id: id)
        }
    }

    public func connect() async throws {
        connectCallCount += 1
        if let error = failures.failNextConnect {
            failures.failNextConnect = nil
            transition(to: .failed)
            throw error
        }
        guard connectionState != .connected, connectionState != .connecting else { return }
        transition(to: .scanning)
        transition(to: .connecting)
        transition(to: .connected)
    }

    public func disconnect() async throws {
        disconnectCallCount += 1
        guard connectionState != .disconnected else { return }
        emit(.dropped(reason: .userInitiated, at: clock()))
        transition(to: .disconnected)
    }

    public func selectLayout(id: String) async throws {
        if let error = failures.failNextSelectLayout {
            failures.failNextSelectLayout = nil
            throw error
        }
        guard connectionState == .connected else {
            throw GlassesTransportError.notConnected
        }
        selectedLayouts.append(id)
    }

    public func updateField(_ update: HUDFieldUpdate) async throws {
        if let error = failures.failNextUpdateField {
            failures.failNextUpdateField = nil
            throw error
        }
        guard connectionState == .connected else {
            throw GlassesTransportError.notConnected
        }
        receivedUpdates.append(update)
    }

    // MARK: - Test affordances

    /// Inject a disconnect mid-run. Per D4 the workout MUST keep running; the
    /// orchestrator just records the drop. Emits a `dropped` status event so
    /// observers can attribute the gap.
    public func simulateDisconnect(reason: GlassesDisconnectReason = .linkLoss) {
        guard connectionState == .connected else { return }
        emit(.dropped(reason: reason, at: clock()))
        transition(to: .reconnecting)
    }

    /// Drive a `reconnecting → connected` cycle with a measured offline gap.
    public func simulateReconnect(after gap: TimeInterval = 0) {
        emit(.reconnected(gap: gap, at: clock()))
        transition(to: .connected)
    }

    /// Push a one-off battery notification (useful for D9 metadata).
    public func simulateBattery(_ level: Int) {
        emit(.batteryLevel(level))
    }

    public func setFailures(_ config: MockGlassesFailureConfig) {
        failures = config
    }

    // MARK: - Private

    private func transition(to newState: GlassesConnectionState) {
        connectionState = newState
        for continuation in stateContinuations.values {
            continuation.yield(newState)
        }
    }

    private func emit(_ event: GlassesStatusEvent) {
        for continuation in statusContinuations.values {
            continuation.yield(event)
        }
    }

    private func register(
        stateContinuation continuation: AsyncStream<GlassesConnectionState>.Continuation,
        id: UUID,
        snapshot: GlassesConnectionState
    ) {
        stateContinuations[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeStateContinuation(id) }
        }
    }

    private func register(
        statusContinuation continuation: AsyncStream<GlassesStatusEvent>.Continuation,
        id: UUID
    ) {
        statusContinuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeStatusContinuation(id) }
        }
    }

    private func removeStateContinuation(_ id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }
}
