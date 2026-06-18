// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation

/// Cross-process store for the user's measurement-system preference
/// (`metric` vs `imperial`). The pure `UnitSystem` enum lives in
/// `ARRunnerCore`; this is the persistence + locale-default wrapper around
/// it, kept in `Shared/` so both the watch and phone targets bind to the
/// identical key and the WCSession `.unitPreference` sync stays
/// binary-compatible.
///
/// Default derives from the device locale on first read
/// (`Locale.current.measurementSystem`): `.metric` → metric, anything else
/// (`.us` / `.uk`) → imperial. Once the user (on either device) picks a
/// value it is persisted to the App Group suite and mirrored across the
/// WCSession link last-writer-wins.
enum UnitPreference {
    private static let appGroupIdentifier = "group.com.arrunner.shared"

    /// `UserDefaults` / `@AppStorage` key. Matches the `WCMessage`
    /// `.unitPreference` sync semantics described in the v6 schema notes.
    static let storageKey = "unitSystem"

    nonisolated(unsafe) static let sharedDefaults: UserDefaults = {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }()

    /// Locale-derived default applied when nothing is persisted yet.
    static var defaultValue: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    /// The current measurement system. Reads/writes the shared suite;
    /// unrecognized stored strings degrade to the locale default.
    static var current: UnitSystem {
        get {
            guard let raw = sharedDefaults.string(forKey: storageKey),
                  let system = UnitSystem(rawValue: raw) else {
                return defaultValue
            }
            return system
        }
        set {
            sharedDefaults.set(newValue.rawValue, forKey: storageKey)
        }
    }

    /// Persist a received value (e.g. from a WCSession sync) only when it
    /// actually changes. Last-writer-wins.
    static func store(_ system: UnitSystem) {
        if sharedDefaults.string(forKey: storageKey) != system.rawValue {
            sharedDefaults.set(system.rawValue, forKey: storageKey)
        }
    }

    /// Human-readable label for settings rows / pickers.
    static func title(for system: UnitSystem) -> String {
        switch system {
        case .metric:   return "Metric"
        case .imperial: return "Imperial"
        }
    }
}
