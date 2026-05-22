// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(MapKit)
import MapKit
#endif

/// v0.5.15 — live, on-watch map showing the runner's current GPS position
/// and the route polyline traced from accepted CoreLocation fixes.
///
/// Design notes:
/// - Camera follows the runner via `MapCameraPosition.userLocation` so the
///   runner is always centered without us re-computing a region every tick.
/// - The polyline source is the substrate's filtered fix stream — exactly
///   the same coordinates the HKWorkoutRouteBuilder persists, so what the
///   wearer sees on the watch matches what Apple Health stores.
/// - Rendered with `.mapStyle(.standard(elevation: .flat))` and minimal
///   controls so the watch GPU spends as little as possible on chrome —
///   workout recording is the priority, the map is the secondary display.
/// - Wrapped in `#if canImport(MapKit)` so non-watch SPM linters / Linux
///   builds of `ARRunnerCore` aren't affected.
struct LiveRouteMapView: View {
    #if canImport(CoreLocation) && canImport(MapKit)
    let coordinates: [CLLocationCoordinate2D]
    let current: CLLocationCoordinate2D?

    @State private var camera: MapCameraPosition = .userLocation(
        fallback: .automatic
    )

    var body: some View {
        Map(position: $camera) {
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
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Live route map")
    }
    #else
    var body: some View { EmptyView() }
    #endif
}
