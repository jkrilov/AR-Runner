// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation

/// Cross-process store for the user's default `WorkoutType` (the type a fresh
/// run starts as when launched from the Action Button, the Smart Stack
/// widget, or the pre-run picker's pre-selected row).
///
/// Mirrors the `ActionButtonMode` pattern: the canonical value lives in the
/// App Group `UserDefaults` suite so every process that can kick off a
/// workout — the watch host, the Action Button intent (which may execute in
/// the system Shortcuts process), and the WidgetKit extension — reads the
/// same selection. Falls back to `.standard` when the App Group entitlement
/// isn't available (previews, unit tests) so `@AppStorage(_, store:)` always
/// has a non-nil store.
///
/// The persisted format is the `WorkoutType.rawValue` string ("running",
/// "indoor_cycling", …) so the on-disk value round-trips through the same
/// legacy-string-preserving encoding the WCSession wire uses.
enum WorkoutTypePreference {
    /// Shared App Group identifier — duplicated from
    /// `ARRunnerCore.arRunnerSharedAppGroupIdentifier` so `Shared/` stays
    /// importable from targets that pull in only the value, not Core's
    /// constant surface (same rationale as `ActionButtonMode`).
    private static let appGroupIdentifier = "group.com.arrunner.shared"

    /// `UserDefaults` / `@AppStorage` key. Matches the `WCMessage`
    /// `.defaultWorkoutType` sync semantics described in the v6 schema notes.
    static let storageKey = "defaultWorkoutType"

    /// Applied when nothing is persisted yet. Outdoor run is the historical
    /// v0.5.x behaviour, so existing users see no change on upgrade.
    static let defaultValue: WorkoutType = .outdoorRun

    /// Shared App Group `UserDefaults` used as the canonical persistence
    /// store. See `ActionButtonMode.sharedDefaults` for the full rationale
    /// on why this is not `UserDefaults.standard`.
    nonisolated(unsafe) static let sharedDefaults: UserDefaults = {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }()

    /// The current default workout type. Reads/writes the shared suite.
    /// Unrecognized stored strings degrade to `defaultValue` rather than
    /// trapping, matching `WorkoutType`'s non-throwing decode contract.
    static var current: WorkoutType {
        get {
            guard let raw = sharedDefaults.string(forKey: storageKey),
                  let type = WorkoutType(rawValue: raw) else {
                return defaultValue
            }
            return type
        }
        set {
            sharedDefaults.set(newValue.rawValue, forKey: storageKey)
        }
    }

    /// Persist a received value (e.g. from a WCSession sync) only when it
    /// actually changes, avoiding an idle write tick. Last-writer-wins.
    static func store(_ type: WorkoutType) {
        if sharedDefaults.string(forKey: storageKey) != type.rawValue {
            sharedDefaults.set(type.rawValue, forKey: storageKey)
        }
    }

    /// SF Symbol used to represent a workout type in pickers, the Smart
    /// Stack tile, and settings rows. Lives here (not Core) because symbol
    /// names are a UI concern, but is shared so watch/phone/widget agree.
    static func symbolName(for type: WorkoutType) -> String {
        switch (type.activity, type.environment) {
        case (.running, _):          return "figure.run"
        case (.walking, _):          return "figure.walk"
        case (.cycling, .outdoor):   return "figure.outdoor.cycle"
        case (.cycling, .indoor):    return "figure.indoor.cycle"
        }
    }

    /// The workout types offered in user-facing pickers, in display order.
    /// Driven by `WorkoutType.allCases` so a new supported combo surfaces
    /// everywhere automatically.
    static let selectable: [WorkoutType] = WorkoutType.allCases
}
