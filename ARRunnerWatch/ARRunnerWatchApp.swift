// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

@main
@MainActor
struct ARRunnerWatchApp: App {
    init() {
        // v0.5.11 (build 41) — request HealthKit authorization as early
        // as possible (App.init runs before any view appears). Per
        // Apple's Action Button docs: "If your app has never requested
        // authorization for any HealthKit data types, the system just
        // launches your app when someone presses the Action button. It
        // doesn't call your intent's `perform()` method." Requesting in
        // `init()` (rather than only `.task` on the root view) means the
        // auth prompt fires on the very first manual launch, so every
        // *subsequent* Action Button press correctly invokes
        // `ARRunnerStartWorkoutIntent.perform()`. The kickoff Task is
        // unstructured so `init()` returns immediately and SwiftUI's
        // scene graph isn't blocked.
        #if canImport(HealthKit) && os(watchOS)
        Task {
            try? await HealthKitWorkoutSubstrate.requestAuthorization()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WorkoutView()
            }
            .task {
                // Defensive re-request — HealthKit treats a re-request as
                // a no-op once the user has answered, so this is cheap
                // and guards against the (unlikely) case where the
                // `init()` Task races a hard-launch foreground transition.
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
