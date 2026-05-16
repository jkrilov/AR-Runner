// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

@main
@MainActor
struct ARRunnerWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WorkoutView()
            }
            .task {
                // Request HealthKit authorization on first launch so that
                // tapping Start Run does not race into `HKLiveWorkoutBuilder`'s
                // terminal `Error(7)` state. Subsequent launches are no-ops
                // once the user has answered the system prompt.
                #if canImport(HealthKit) && os(watchOS)
                try? await HealthKitWorkoutSubstrate.requestAuthorization()
                #endif
            }
        }
    }
}
