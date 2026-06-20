// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The user's catalog of *custom* HUD layouts.
///
/// Holds only user-authored layouts — the curated presets
/// (`HUDLayout.curatedPresets()`) and the per-workout-type built-ins
/// (`HUDLayout.default(for:)`) stay code-defined and are never serialised
/// here. Versioned independently of `WCMessage` so the on-disk/App-Group blob
/// can evolve without touching the wire envelope; `schemaVersion` lets a
/// future reader migrate older catalogs.
///
/// Pure value type (Foundation only) so it stays exercisable from the Linux
/// `ARRunnerCoreTests` suite.
public struct HUDLayoutCatalog: Sendable, Codable, Equatable {
    /// The catalog format version stamped on freshly-created instances.
    public static let currentVersion = 1

    public var schemaVersion: Int
    public var layouts: [HUDLayout]

    public init(
        schemaVersion: Int = HUDLayoutCatalog.currentVersion,
        layouts: [HUDLayout] = []
    ) {
        self.schemaVersion = schemaVersion
        self.layouts = layouts
    }

    /// The custom layout with the given `id`, or `nil` if no such layout
    /// exists (e.g. it was deleted but an assignment still references it —
    /// see `HUDLayoutResolver` for the dangling-reference fallback).
    public func layout(id: String) -> HUDLayout? {
        layouts.first { $0.id == id }
    }
}
