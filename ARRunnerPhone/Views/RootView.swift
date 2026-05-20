// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@MainActor
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WorkoutMirrorView(service: ARRunnerPhoneEnvironment.shared.mirror)
            }
            .tabItem {
                Label("Live", systemImage: "figure.run")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    RootView()
}
