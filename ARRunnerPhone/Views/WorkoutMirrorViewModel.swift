// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import SwiftUI

/// Read-only view-model for the iPhone live mirror (v0.2 #3). Subscribes to
/// the inbound WCSession message stream and republishes the latest workout
/// snapshot + lifecycle state for `WorkoutMirrorView`.
///
/// Decision #3 — watch-first: this view-model has no fallback strategy when
/// nothing arrives. It simply stays in `.idle`. Settings, configuration, and
/// any phone-initiated control are explicitly out of scope for v0.2.
@MainActor
@Observable
final class WorkoutMirrorViewModel {
    enum Status: Equatable {
        case idle
        case live(WorkoutTickMessage)
        case stale(WorkoutTickMessage, since: Date)
        case ended(WorkoutTickMessage?)
    }

    private(set) var status: Status = .idle
    private(set) var lastReceivedAt: Date?
    /// Last glasses battery level (0–100) reported by the watch over the
    /// WC link. `nil` until the first notification arrives — v0.4 the watch
    /// triggers an initial read on subscription so the value lands within
    /// seconds of pairing, not 30 s later when the next notify fires.
    private(set) var glassesBatteryLevel: Int?
    private(set) var glassesBatteryUpdatedAt: Date?

    /// Snapshots older than this without a refresh are surfaced as `.stale`
    /// so the dashboard can dim or annotate the metrics.
    private let staleThreshold: TimeInterval

    private let service: WatchConnectivityService
    private var ingestTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?

    init(service: WatchConnectivityService, staleThreshold: TimeInterval = 8) {
        self.service = service
        self.staleThreshold = staleThreshold
    }

    func start() {
        ingestTask?.cancel()
        ingestTask = Task { [weak self, service] in
            for await message in service.incomingMessages {
                self?.apply(message: message)
            }
        }
        staleTask?.cancel()
        staleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.markStaleIfNeeded()
            }
        }
    }

    func stop() {
        ingestTask?.cancel(); ingestTask = nil
        staleTask?.cancel(); staleTask = nil
    }

    private func apply(message: WCMessage) {
        switch message {
        case .workoutSnapshot(let snapshot):
            lastReceivedAt = Date()
            switch snapshot.phase {
            case .ended, .failed:
                status = .ended(snapshot)
            default:
                status = .live(snapshot)
            }
        case .workoutLifecycle(let event):
            switch event {
            case .ended:
                if case .live(let last) = status {
                    status = .ended(last)
                } else if case .stale(let last, _) = status {
                    status = .ended(last)
                } else {
                    status = .ended(nil)
                }
            case .started:
                // A fresh start clears any stale "ended" state so the
                // dashboard reverts to "waiting for first tick".
                status = .idle
            case .paused, .resumed:
                break
            }
        case .layoutConfig, .workoutTick:
            break
        case .glassesBattery(let level):
            // Clamp defensively — the spec is 0–100 but we never want a
            // bogus value (e.g. firmware quirk) to fail the SF Symbol
            // selection downstream.
            glassesBatteryLevel = max(0, min(100, level))
            glassesBatteryUpdatedAt = Date()
        }
    }

    private func markStaleIfNeeded() {
        guard case .live(let snapshot) = status,
              let lastReceivedAt,
              Date().timeIntervalSince(lastReceivedAt) > staleThreshold
        else { return }
        status = .stale(snapshot, since: lastReceivedAt)
    }
}
