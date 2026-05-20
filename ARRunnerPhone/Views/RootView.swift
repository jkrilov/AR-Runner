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
                ContentPlaceholderView(
                    title: "History",
                    subtitle: "Saved HealthKit workouts and AR metadata summaries land here."
                )
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

private struct ContentPlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(subtitle)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle(title)
    }
}

#Preview {
    RootView()
}
