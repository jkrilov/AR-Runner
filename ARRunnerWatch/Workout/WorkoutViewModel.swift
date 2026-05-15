// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import SwiftUI

/// `@MainActor` view model that owns a `WorkoutController` and republishes its
/// state + metrics for SwiftUI consumption. The controller itself is the
/// authoritative actor — this layer only mirrors observable state.
@MainActor
@Observable
final class WorkoutViewModel {
    enum LaunchState: Equatable {
        case idle
        case starting
        case running
        case paused
        case ending
        case ended(WorkoutSummary)
        case failed(String)
    }

    private(set) var launchState: LaunchState = .idle
    private(set) var heartRate: Double?
    private(set) var distanceMeters: Double?
    private(set) var elapsed: TimeInterval = 0
    private(set) var glassesConnected: Bool = false

    private var controller: WorkoutController?
    private var transport: (any GlassesFrameTransport)?
    private var stateTask: Task<Void, Never>?
    private var metricTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var glassesStateTask: Task<Void, Never>?
    private var glassesStatusTask: Task<Void, Never>?
    private var startedAt: Date?

    private let substrateFactory: @Sendable () -> any WorkoutHealthSubstrate
    private let transportFactory: (@Sendable () -> any GlassesFrameTransport)?

    init(
        substrateFactory: @escaping @Sendable () -> any WorkoutHealthSubstrate,
        transportFactory: (@Sendable () -> any GlassesFrameTransport)? = nil
    ) {
        self.substrateFactory = substrateFactory
        self.transportFactory = transportFactory
    }

    func start(activity: SportType = .running) async {
        guard launchState == .idle || (try? endedSummary()) != nil else { return }
        launchState = .starting

        let controller = WorkoutController(substrate: substrateFactory())
        self.controller = controller
        attachStreams(to: controller)

        // v0.2 #1: bring up the glasses link alongside the workout. Per D4
        // the connect attempt is opportunistic — we never block the workout
        // start on its outcome.
        if let transportFactory {
            let transport = transportFactory()
            self.transport = transport
            attachGlasses(transport: transport)
            Task.detached { [transport] in
                try? await transport.connect()
            }
        }

        do {
            let state = try await controller.start(activityType: activity)
            startedAt = state.startedAt
            launchState = .running
            startElapsedTicker()
        } catch {
            launchState = .failed(String(describing: error))
        }
    }

    func pause() async {
        guard let controller else { return }
        do {
            try await controller.pause()
            launchState = .paused
        } catch {
            launchState = .failed(String(describing: error))
        }
    }

    func resume() async {
        guard let controller else { return }
        do {
            try await controller.resume()
            launchState = .running
        } catch {
            launchState = .failed(String(describing: error))
        }
    }

    func end() async {
        guard let controller else { return }
        launchState = .ending
        do {
            let summary = try await controller.end()
            launchState = .ended(summary)
            stopTasks()
            await teardownTransport()
        } catch {
            launchState = .failed(String(describing: error))
            stopTasks()
            await teardownTransport()
        }
    }

    func reportGlasses(_ signal: GlassesConnectivitySignal) async {
        guard let controller else { return }
        await controller.reportGlassesSignal(signal)
    }

    /// Subscribe to Weiss's canonical `GlassesFrameTransport` and forward
    /// every connection-state transition + drop event into the controller as
    /// a `GlassesConnectivitySignal`. Per D4 the workout keeps running
    /// regardless — this only updates the HUD-online indicator and bumps
    /// the disconnect counter for the summary.
    func attachGlasses(transport: any GlassesFrameTransport) {
        glassesStateTask?.cancel()
        glassesStatusTask?.cancel()

        glassesStateTask = Task { [weak self] in
            let stream = await transport.connectionStates()
            for await state in stream {
                await self?.reportGlasses(.from(state))
            }
        }
        glassesStatusTask = Task { [weak self] in
            let stream = await transport.statusEvents()
            for await event in stream {
                if case .dropped(let reason, _) = event {
                    await self?.reportGlasses(.from(droppedReason: reason))
                }
            }
        }
    }

    private func endedSummary() throws -> WorkoutSummary? {
        if case .ended(let summary) = launchState { return summary }
        return nil
    }

    private func attachStreams(to controller: WorkoutController) {
        stateTask?.cancel()
        metricTask?.cancel()

        stateTask = Task { [weak self] in
            for await state in controller.states {
                await self?.apply(state: state)
            }
        }
        metricTask = Task { [weak self] in
            for await metric in controller.metrics {
                await self?.apply(metric: metric)
            }
        }
    }

    private func apply(state: WorkoutState) {
        glassesConnected = state.glassesConnected
        switch state.phase {
        case .running: launchState = .running
        case .paused: launchState = .paused
        case .failed:
            launchState = .failed(state.failureReason ?? "Unknown failure")
        default: break
        }
    }

    private func apply(metric: WorkoutMetric) {
        switch metric.kind {
        case .heartRate: heartRate = metric.value
        case .distance: distanceMeters = metric.value
        default: break
        }
    }

    private func startElapsedTicker() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickElapsed()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tickElapsed() {
        guard let startedAt, case .running = launchState else { return }
        elapsed = Date().timeIntervalSince(startedAt)
    }

    private func stopTasks() {
        stateTask?.cancel(); stateTask = nil
        metricTask?.cancel(); metricTask = nil
        elapsedTask?.cancel(); elapsedTask = nil
        glassesStateTask?.cancel(); glassesStateTask = nil
        glassesStatusTask?.cancel(); glassesStatusTask = nil
    }

    private func teardownTransport() async {
        guard let transport else { return }
        try? await transport.disconnect()
        self.transport = nil
    }
}
