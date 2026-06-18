// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Generates Strava-style activity names from a workout start time
/// ("Morning Run", "Afternoon Run", "Evening Run", "Night Run").
///
/// This matches Strava's own default naming when uploads arrive without an
/// explicit `name` field, so AR-Runner uploads sit naturally alongside
/// activities recorded by Strava's first-party clients.
///
/// Time-of-day thresholds (local-time hour, 24h):
/// - **05:00–11:59** → Morning
/// - **12:00–16:59** → Afternoon
/// - **17:00–20:59** → Evening
/// - **21:00–04:59** → Night
public enum ActivityNaming {
    public enum TimeOfDay: String, Sendable, Equatable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case night = "Night"
    }

    /// Produce a Strava-style name like "Morning Run" for the given start
    /// date. The `sport` argument is appended verbatim ("Run", "Ride",
    /// "Walk"); v0.5 always passes "Run".
    public static func name(
        forStart startDate: Date,
        sport: String = "Run",
        calendar: Calendar = .current
    ) -> String {
        "\(timeOfDay(for: startDate, calendar: calendar).rawValue) \(sport)"
    }

    public static func timeOfDay(
        for date: Date,
        calendar: Calendar = .current
    ) -> TimeOfDay {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default:      return .night // 21..<24 and 0..<5
        }
    }

    /// The Strava-style activity noun for an `ActivityKind` — "Run", "Ride",
    /// "Walk". Used to build names like "Morning Ride" for non-running
    /// workouts (v0.6.0 multi-type support).
    public static func activityNoun(for activity: ActivityKind) -> String {
        switch activity {
        case .running: return "Run"
        case .cycling: return "Ride"
        case .walking: return "Walk"
        }
    }

    /// Strava-style name for a typed workout, e.g. "Morning Ride".
    public static func name(
        forStart startDate: Date,
        workoutType: WorkoutType,
        calendar: Calendar = .current
    ) -> String {
        name(
            forStart: startDate,
            sport: activityNoun(for: workoutType.activity),
            calendar: calendar
        )
    }
}
