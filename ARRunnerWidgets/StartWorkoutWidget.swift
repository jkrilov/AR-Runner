// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import SwiftUI
import WidgetKit

struct StartWorkoutEntry: TimelineEntry {
    let date: Date
}

struct StartWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartWorkoutEntry {
        StartWorkoutEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (StartWorkoutEntry) -> Void) {
        completion(StartWorkoutEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StartWorkoutEntry>) -> Void) {
        let entry = StartWorkoutEntry(date: .now)
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
            Text("Ready for your next run")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(intent: StartWorkoutIntent()) {
                Label("Start Run", systemImage: "figure.run")
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
