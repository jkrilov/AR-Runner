// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import ARRunnerCore
import SwiftUI
import WidgetKit

struct StartWorkoutEntry: TimelineEntry {
    let date: Date
    /// v0.6.0 — the user's persisted default workout type, read from the
    /// shared App Group store so the Smart Stack tile shows the right
    /// label + icon (and launches that activity via the host).
    let workoutType: WorkoutType
}

struct StartWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartWorkoutEntry {
        StartWorkoutEntry(date: .now, workoutType: .outdoorRun)
    }

    func getSnapshot(in context: Context, completion: @escaping (StartWorkoutEntry) -> Void) {
        completion(StartWorkoutEntry(date: .now, workoutType: WorkoutTypePreference.current))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StartWorkoutEntry>) -> Void) {
        let entry = StartWorkoutEntry(date: .now, workoutType: WorkoutTypePreference.current)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct StartWorkoutWidgetEntryView: View {
    let entry: StartWorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AR-Runner")
                .font(.headline)
            Text("Ready for your next \(entry.workoutType.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(intent: StartWorkoutIntent()) {
                Label(
                    "Start \(entry.workoutType.displayName)",
                    systemImage: WorkoutTypePreference.symbolName(for: entry.workoutType)
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StartWorkoutWidget: Widget {
    let kind = "StartWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StartWorkoutProvider()) { entry in
            StartWorkoutWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Start AR Run")
        .description("Launch AR-Runner into the workout flow from Smart Stack or the iPhone widget gallery.")
        .supportedFamilies(StartWorkoutWidget.supportedFamilies)
    }

    static var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryRectangular]
        #else
        [.systemSmall, .accessoryRectangular]
        #endif
    }
}

@main
struct ARRunnerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StartWorkoutWidget()
    }
}
