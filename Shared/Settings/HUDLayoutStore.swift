// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation

/// Cross-process store for the user's custom HUD layouts and per-workout-type
/// layout assignments.
///
/// Mirrors the `WorkoutTypePreference` / `UnitPreference` pattern: the
/// canonical values live in the App Group `UserDefaults` suite so every
/// process that renders the live HUD — the watch host and (later) the phone
/// editor — reads the same selection, and so the watch resolves customs at the
/// start of a run **with no phone present**. Falls back to `UserDefaults`
/// standard when the App Group entitlement isn't available (previews, unit
/// tests).
///
/// Two keys, each holding JSON-encoded `Data`:
///   * `"hudLayoutCatalog"`  → `HUDLayoutCatalog` (custom layouts only)
///   * `"hudLayoutDefaults"` → `WorkoutLayoutDefaults` (per-type assignments)
///
/// Sensible empty defaults (empty catalog, empty assignments) keep behaviour
/// byte-identical for a user with no custom layouts: the resolver falls
/// through to `HUDLayout.default(for:)`.
enum HUDLayoutStore {
    /// Shared App Group identifier — duplicated from
    /// `ARRunnerCore.arRunnerSharedAppGroupIdentifier` for the same reason as
    /// `WorkoutTypePreference`: `Shared/` stays importable from targets that
    /// only pull in the value, not Core's constant surface.
    private static let appGroupIdentifier = "group.com.arrunner.shared"

    /// `UserDefaults` key for the JSON-encoded `HUDLayoutCatalog`.
    static let catalogKey = "hudLayoutCatalog"

    /// `UserDefaults` key for the JSON-encoded `WorkoutLayoutDefaults`.
    static let defaultsKey = "hudLayoutDefaults"

    /// Shared App Group `UserDefaults` used as the canonical persistence
    /// store. See `WorkoutTypePreference.sharedDefaults` for the rationale on
    /// why this is not `UserDefaults.standard`.
    nonisolated(unsafe) static let sharedDefaults: UserDefaults = {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }()

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// The user's custom-layout catalog. Reads/writes the shared suite.
    /// A missing or undecodable value degrades to an empty catalog rather
    /// than trapping.
    static var currentCatalog: HUDLayoutCatalog {
        get {
            guard let data = sharedDefaults.data(forKey: catalogKey),
                  let catalog = try? decoder.decode(HUDLayoutCatalog.self, from: data) else {
                return HUDLayoutCatalog()
            }
            return catalog
        }
        set {
            guard let data = try? encoder.encode(newValue) else { return }
            sharedDefaults.set(data, forKey: catalogKey)
        }
    }

    /// The user's per-workout-type layout assignments. Reads/writes the
    /// shared suite. Missing or undecodable → empty assignments.
    static var currentDefaults: WorkoutLayoutDefaults {
        get {
            guard let data = sharedDefaults.data(forKey: defaultsKey),
                  let defaults = try? decoder.decode(WorkoutLayoutDefaults.self, from: data) else {
                return WorkoutLayoutDefaults()
            }
            return defaults
        }
        set {
            guard let data = try? encoder.encode(newValue) else { return }
            sharedDefaults.set(data, forKey: defaultsKey)
        }
    }

    /// Persist a received catalog (e.g. from a WCSession sync) only when its
    /// encoded form actually changes, avoiding an idle write tick.
    /// Last-writer-wins.
    static func store(catalog: HUDLayoutCatalog) {
        guard let data = try? encoder.encode(catalog) else { return }
        if sharedDefaults.data(forKey: catalogKey) != data {
            sharedDefaults.set(data, forKey: catalogKey)
        }
    }

    /// Persist received assignments (e.g. from a WCSession sync) only when the
    /// encoded form actually changes. Last-writer-wins.
    static func store(defaults: WorkoutLayoutDefaults) {
        guard let data = try? encoder.encode(defaults) else { return }
        if sharedDefaults.data(forKey: defaultsKey) != data {
            sharedDefaults.set(data, forKey: defaultsKey)
        }
    }
}
