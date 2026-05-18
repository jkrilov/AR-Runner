// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Errors surfaced across the `GlassesFrameTransport` boundary.
public enum GlassesTransportError: Error, Equatable, Sendable {
    case notConnected
    case unknownLayout(id: String)
    case bluetoothUnavailable
    case writeFailed(reason: String)
    case scanTimeout
}

/// In-memory, fully deterministic implementation of `GlassesFrameTransport`.
///
/// Lives in `ARRunnerCore` so:
///   * Linux CI exercises the protocol surface end-to-end
///   * Amber can compose a richer mock on top of (or alongside) this one
///   * The watch app can wire up a Stub during previews / DEBUG builds
///
/// All state lives behind the actor; streams are powered by simple
/// `AsyncStream` continuations cleared on `disconnect()`.
public actor StubGlassesTransport: GlassesFrameTransport {
    public private(set) var connectionState: GlassesConnectionState = .disconnected
    public private(set) var activeLayoutID: String?
    public private(set) var receivedUpdates: [HUDFieldUpdate] = []
    public private(set) var receivedHUDFrameBatches: [[[UInt8]]] = []
    public private(set) var connectCallCount = 0
    public private(set) var disconnectCallCount = 0

    private let knownLayoutIDs: Set<String>
    private let simulatedDeviceName: String?
    private var stateContinuations: [UUID: AsyncStream<GlassesConnectionState>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<GlassesStatusEvent>.Continuation] = [:]

    public init(
        knownLayoutIDs: Set<String> = Set(CuratedLayoutCatalog.mapping.keys),
        simulatedDeviceName: String? = "Simulated Glasses"
    ) {
        self.knownLayoutIDs = knownLayoutIDs
        self.simulatedDeviceName = simulatedDeviceName
    }

    public var connectedDeviceName: String? {
        get async {
            connectionState == .connected ? simulatedDeviceName : nil
        }
    }

    public func connectionStates() -> AsyncStream<GlassesConnectionState> {
        let id = UUID()
        let snapshot = connectionState
        return AsyncStream { continuation in
            self.register(stateContinuation: continuation, id: id, snapshot: snapshot)
        }
    }

    public func statusEvents() -> AsyncStream<GlassesStatusEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.register(statusContinuation: continuation, id: id)
        }
    }

    public func connect() async throws {
        connectCallCount += 1
        guard connectionState != .connected, connectionState != .connecting else { return }
        transition(to: .scanning)
        transition(to: .connecting)
        transition(to: .connected)
    }

    public func disconnect() async throws {
        disconnectCallCount += 1
        guard connectionState != .disconnected else { return }
        emit(.dropped(reason: .userInitiated, at: Date()))
        transition(to: .disconnected)
    }

    public func selectLayout(id: String) async throws {
        guard connectionState == .connected else {
            throw GlassesTransportError.notConnected
        }
        guard knownLayoutIDs.contains(id) else {
            throw GlassesTransportError.unknownLayout(id: id)
        }
        activeLayoutID = id
    }

    public func updateField(_ update: HUDFieldUpdate) async throws {
        guard connectionState == .connected else {
            throw GlassesTransportError.notConnected
        }
        receivedUpdates.append(update)
    }

    public func sendCommands(_ frames: [[UInt8]]) async throws {
        guard connectionState == .connected else {
            throw GlassesTransportError.notConnected
        }
        receivedHUDFrameBatches.append(frames)
    }

    // MARK: - Test affordances

    /// Simulate a link drop without user interaction (e.g. range loss).
    public func simulateDrop(reason: GlassesDisconnectReason = .linkLoss) {
        guard connectionState == .connected else { return }
        emit(.dropped(reason: reason, at: Date()))
        transition(to: .reconnecting)
    }

    /// Simulate auto-reconnect completion with a measured gap.
    public func simulateReconnect(after gap: TimeInterval) {
        emit(.reconnected(gap: gap, at: Date()))
        transition(to: .connected)
    }

    /// Simulate a one-off battery notification.
    public func simulateBattery(_ level: Int) {
        emit(.batteryLevel(level))
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
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStateContinuation(id: id) }
        }
    }

    private func register(
        statusContinuation continuation: AsyncStream<GlassesStatusEvent>.Continuation,
        id: UUID
    ) {
        statusContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusContinuation(id: id) }
        }
    }

    private func removeStateContinuation(id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }

    private func removeStatusContinuation(id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }
}
