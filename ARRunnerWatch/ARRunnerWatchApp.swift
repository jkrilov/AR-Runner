// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
@MainActor
struct ARRunnerWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WorkoutView()
            }
        }
    }
}
