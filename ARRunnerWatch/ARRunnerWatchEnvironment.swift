// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// App-scope shared services for the watch app. Held as a singleton so the
/// `WorkoutView` can construct its `WorkoutViewModel` without threading
/// dependencies through the SwiftUI scene graph.
///
/// Currently exposes the WCSession-backed `WatchConnectivityService` so the
/// view-model can publish `WorkoutTickMessage` snapshots to the iPhone live
/// mirror (v0.2 #3). The service is activated once at app launch — failures
/// are silent per decision #3 (watch-first; phone is opportunistic).
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
