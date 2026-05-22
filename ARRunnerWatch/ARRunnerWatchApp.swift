// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif
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

                // Force the system to (re)index our AppShortcuts so the
                // Action Button picker (Settings → Action Button →
                // Shortcut) reliably shows "AR-Runner Action Button" on
                // every install / update. Without this call the picker
                // can keep serving a stale snapshot from a prior build,
                // which presented as "the app doesn't appear in Action
                // Button settings" in v0.5.4. Cheap and idempotent — safe
                // to fire every cold launch.
                #if canImport(AppIntents)
                if #available(watchOS 10.0, *) {
                    ARRunnerAppShortcuts.updateAppShortcutParameters()
                }
                #endif
            }
        }
    }
}
