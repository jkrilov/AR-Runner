// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(MapKit)
import MapKit
#endif

/// v0.5.15 — live map showing the runner's current GPS position and the
/// route polyline traced from accepted CoreLocation fixes.
///
/// v0.5.16 — promoted from a watch-only view into `Shared/Views` so the
/// iPhone live-mirror can render the same map below its metrics grid. The
/// `height` parameter lets callers size it: the watch's secondary map page
/// passes `nil` to fill the available swipe page, the phone passes ~280pt
/// to claim a generous slab below the metrics, and the original inline
/// watch usage (legacy) keeps the 160pt default.
///
/// Design notes:
/// - Camera follows the runner via `MapCameraPosition.userLocation` so the
///   runner is always centered without us re-computing a region every tick.
/// - On the watch the polyline source is the substrate's filtered fix
///   stream — the same coordinates `HKWorkoutRouteBuilder` persists, so
///   what the wearer sees matches what Apple Health stores. On the phone
///   the coordinates are accumulated from `WorkoutTickMessage.latitude` /
///   `.longitude` arriving over WCSession at ~1 Hz (v0.5.16 / schema v5).
/// - Rendered with `.mapStyle(.standard(elevation: .flat))` and minimal
///   controls so the watch GPU spends as little as possible on chrome —
///   workout recording is the priority, the map is the secondary display.
/// - Wrapped in `#if canImport(MapKit)` so non-watch SPM linters / Linux
///   builds of `ARRunnerCore` aren't affected.
struct LiveRouteMapView: View {
    #if canImport(CoreLocation) && canImport(MapKit)
    let coordinates: [CLLocationCoordinate2D]
    let current: CLLocationCoordinate2D?
    /// v0.5.17 — coordinate of each split press (in order). Rendered as
    /// small numbered amber dots on the polyline so the wearer can see
    /// where each lap was banked.
    let splitCoordinates: [CLLocationCoordinate2D]
    /// v0.5.17 — true once the workout has ended; surfaces a checkered
    /// finish marker at the runner's last known coordinate.
    let showFinish: Bool
    /// v0.5.17 — enables pan/zoom and the 5-second auto-recenter behavior.
    /// Phone passes `true`; watch passes `false` so the Digital Crown is
    /// free to drive the parent TabView page navigation instead of being
    /// captured by the map's zoom gesture.
    let interactive: Bool
    /// Explicit height in points, or `nil` to fill the parent (used by the
    /// watch's secondary swipe-page so the map is full-screen and the
    /// phone could also fill a full-screen detail view in the future).
    let height: CGFloat?

    init(
        coordinates: [CLLocationCoordinate2D],
        current: CLLocationCoordinate2D?,
        splitCoordinates: [CLLocationCoordinate2D] = [],
        showFinish: Bool = false,
        interactive: Bool = true,
        height: CGFloat? = 160
    ) {
        self.coordinates = coordinates
        self.current = current
        self.splitCoordinates = splitCoordinates
        self.showFinish = showFinish
        self.interactive = interactive
        self.height = height
    }

    @State private var camera: MapCameraPosition = .userLocation(
        fallback: .automatic
    )
    /// v0.5.17 — drives the 5-second auto-recenter on the phone. Replaced
    /// on every camera change so only the *last* pan starts a countdown.
    @State private var recenterTask: Task<Void, Never>?

    /// First accepted GPS fix; anchors the green start marker.
    private var startCoordinate: CLLocationCoordinate2D? { coordinates.first }

    /// Last known position when the workout ended; anchors the checkered
    /// finish marker. Prefer `current` (kept up to date by the watch view-
    /// model) and fall back to the polyline's tail in case `current` was
    /// nil at end-of-run.
    private var finishCoordinate: CLLocationCoordinate2D? {
        current ?? coordinates.last
    }

    var body: some View {
        // Watch: empty interaction modes so the Digital Crown is free for
        // the parent `TabView(.verticalPage)`. Phone: full interactivity,
        // with a 5s auto-recenter (below) so the runner can briefly inspect
        // the route and the map snaps back to following them.
        let modes: MapInteractionModes = interactive ? .all : []

        let map = Map(position: $camera, interactionModes: modes) {
            UserAnnotation()

            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.green, lineWidth: 3)
            }

            if let startCoordinate {
                Annotation("Start", coordinate: startCoordinate) {
                    ZStack {
                        Circle().fill(Color.green).frame(width: 18, height: 18)
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Start")
                }
            }

            ForEach(Array(splitCoordinates.enumerated()), id: \.offset) { idx, coord in
                Annotation("Split \(idx + 1)", coordinate: coord) {
                    ZStack {
                        Circle().fill(Color.orange).frame(width: 14, height: 14)
                        Text("\(idx + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Split \(idx + 1)")
                }
            }

            if showFinish, let finishCoordinate {
                Annotation("Finish", coordinate: finishCoordinate) {
                    ZStack {
                        Circle().fill(Color.black).frame(width: 20, height: 20)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Finish")
                }
            } else if let current, !showFinish {
                // Live runner pin — hidden once the finish marker is up
                // so the two don't stack.
                Annotation("", coordinate: current) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.25))
                            .frame(width: 18, height: 18)
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(.hidden)
        .accessibilityLabel("Live route map")
        .onMapCameraChange(frequency: .onEnd) { _ in
            // v0.5.17 — phone-only auto-recenter. Cancel any pending snap-
            // back and schedule a fresh 5s timer; if the camera is still
            // user-controlled when the timer fires, jump back to follow
            // the runner. Resetting to `.userLocation` itself will fire
            // another change event but the resulting reset is a no-op so
            // we don't get a loop.
            guard interactive else { return }
            recenterTask?.cancel()
            recenterTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                camera = .userLocation(fallback: .automatic)
            }
        }

        if let height {
            map
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            map.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #else
    var body: some View { EmptyView() }
    #endif
}
