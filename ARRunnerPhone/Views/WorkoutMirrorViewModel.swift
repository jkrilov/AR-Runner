// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import SwiftUI
#if canImport(CoreLocation)
import CoreLocation
#endif

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

    #if canImport(CoreLocation)
    /// v0.5.16 — route polyline accumulated from `WorkoutTickMessage`
    /// lat/lon (WC schema v5). The phone is downstream of the watch's
    /// filtered GPS pipeline, so what shows up here is the same set of
    /// coordinates `HKWorkoutRouteBuilder` is persisting on the watch.
    /// Cleared on lifecycle `.started` and on `.ended` so a brand-new run
    /// doesn't inherit the previous route's polyline.
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    /// Most recent fix from the latest tick — drives the runner pin and
    /// the user-location follow camera on `LiveRouteMapView`.
    private(set) var currentLocation: CLLocationCoordinate2D?
    #endif

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
            #if canImport(CoreLocation)
            ingestLocation(from: snapshot)
            #endif
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
                #if canImport(CoreLocation)
                // Keep the final polyline visible alongside the ended-state
                // header so the user sees their finished route. Cleared on
                // the next `.started`.
                #endif
            case .started:
                // A fresh start clears any stale "ended" state so the
                // dashboard reverts to "waiting for first tick".
                status = .idle
                #if canImport(CoreLocation)
                routeCoordinates.removeAll(keepingCapacity: true)
                currentLocation = nil
                #endif
            case .paused, .resumed:
                break
            }
        case .layoutConfig, .workoutTick, .defaultWorkoutType, .unitPreference, .layoutCatalog, .layoutDefaults, .unknown:
            break
        case .glassesBattery(let level):
            // Clamp defensively — the spec is 0–100 but we never want a
            // bogus value (e.g. firmware quirk) to fail the SF Symbol
            // selection downstream.
            glassesBatteryLevel = max(0, min(100, level))
            glassesBatteryUpdatedAt = Date()
        }
    }

    #if canImport(CoreLocation)
    /// v0.5.16 — fold the per-tick GPS fix into the live polyline. Skips
    /// duplicate coordinates (same lat AND lon as the last one) so a
    /// stationary runner doesn't bloat the array with redundant points.
    /// Also defends against bogus 0/0 fixes that some test mocks emit.
    private func ingestLocation(from snapshot: WorkoutTickMessage) {
        guard let lat = snapshot.latitude, let lon = snapshot.longitude else { return }
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else { return }
        if let last = routeCoordinates.last, last.latitude == lat, last.longitude == lon {
            currentLocation = last
            return
        }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        routeCoordinates.append(coord)
        currentLocation = coord
    }
    #endif

    private func markStaleIfNeeded() {
        guard case .live(let snapshot) = status,
              let lastReceivedAt,
              Date().timeIntervalSince(lastReceivedAt) > staleThreshold
        else { return }
        status = .stale(snapshot, since: lastReceivedAt)
    }
}
