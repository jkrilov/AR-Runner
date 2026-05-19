// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// App-scope shared services for the watch app. Held as a singleton so the
/// `WorkoutView` can construct its `WorkoutViewModel` without threading
/// dependencies through the SwiftUI scene graph.
///
/// Exposes the WCSession-backed `WatchConnectivityService` so the view-model
/// can publish `WorkoutTickMessage` snapshots to an optional iPhone live
/// mirror. Activated once at app launch — failures are silent because the
/// phone is never a requirement.
@MainActor
final class ARRunnerWatchEnvironment {
    static let shared = ARRunnerWatchEnvironment()

    let mirror: WatchConnectivityService

    private init() {
        let service = WatchConnectivityService()
        service.activate()
        self.mirror = service
    }
}
