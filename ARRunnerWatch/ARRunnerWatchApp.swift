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

                // Note: we intentionally do NOT call
                // `AppShortcutsProvider.updateAppShortcutParameters()`
                // here. The Apple Watch Ultra Action Button "Workout"
                // category (where Strava / Nike Run Club appear) is
                // populated from apps that ship an
                // `AppIntents.StartWorkoutIntent` conformance, not from
                // AppShortcuts. See
                // `ARRunnerWatch/ActionButton/ActionButtonIntent.swift`
                // (`ARRunnerStartWorkoutIntent`) for the registration
                // surface. The previous AppShortcuts approach put us
                // under Settings → Action Button → Shortcut instead,
                // which is why AR-Runner never appeared in the Workout
                // picker through v0.5.5.
            }
        }
    }
}
