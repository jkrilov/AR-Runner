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
    /// Explicit height in points, or `nil` to fill the parent (used by the
    /// watch's secondary swipe-page so the map is full-screen and the
    /// phone could also fill a full-screen detail view in the future).
    let height: CGFloat?

    init(
        coordinates: [CLLocationCoordinate2D],
        current: CLLocationCoordinate2D?,
        height: CGFloat? = 160
    ) {
        self.coordinates = coordinates
        self.current = current
        self.height = height
    }

    @State private var camera: MapCameraPosition = .userLocation(
        fallback: .automatic
    )

    var body: some View {
        let map = Map(position: $camera) {
            UserAnnotation()

            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.green, lineWidth: 3)
            }

            if let current {
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
