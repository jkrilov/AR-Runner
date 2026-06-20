// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Per-workout-type assignment of a custom `HUDLayout` to display.
///
/// Maps `WorkoutType.rawValue` (the legacy-preserving wire strings —
/// `"running"`, `"indoor_cycling"`, …) to a custom `HUDLayout.id`. Using the
/// `rawValue` string as the key keeps the structure JSON/`Codable`-clean and
/// stable on the WCSession wire and in the App Group store. A workout type
/// with no entry resolves to its code-defined built-in default.
///
/// Versioned independently of `WCMessage` (`schemaVersion`) so the stored
/// blob can migrate without an envelope bump. Pure value type (Foundation
/// only) so it stays Linux-testable.
public struct WorkoutLayoutDefaults: Sendable, Codable, Equatable {
    /// The defaults format version stamped on freshly-created instances.
    public static let currentVersion = 1

    public var schemaVersion: Int
    public var assignments: [String: String]

    public init(
        schemaVersion: Int = WorkoutLayoutDefaults.currentVersion,
        assignments: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.assignments = assignments
    }

    /// The custom `HUDLayout.id` assigned to the given workout type, or `nil`
    /// when the user hasn't picked a custom layout for it (resolve to the
    /// built-in default).
    public func layoutID(for type: WorkoutType) -> String? {
        assignments[type.rawValue]
    }
}
