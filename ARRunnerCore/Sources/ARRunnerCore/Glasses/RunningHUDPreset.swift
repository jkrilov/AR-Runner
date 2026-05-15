// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Curated runner-facing HUD layout presets (v0.2 #5 — backend only).
///
/// The watch app uses `default` on connect; there is intentionally no picker
/// UI in v0.2 (per Joe, scope decision 5b). This file exists so the watch
/// app, future picker, and Mirror PR can all agree on:
///
///   * The set of presets that exist (`CaseIterable`).
///   * The `default` preset to apply automatically on (re)connect.
///   * A canonical mapping from preset → curated `HUDLayout` → on-device
///     ActiveLook layout slot (via `CuratedLayoutCatalog`).
///   * A pre-encoded ActiveLook `0x62 displayLayout` frame ready to ship over
///     BLE (`layoutDescriptor()`).
///
/// Concurrency: pure value type, trivially `Sendable`.
public enum RunningHUDPreset: String, CaseIterable, Sendable, Codable, Equatable {
    /// HR + pace + distance + duration. The baseline runner's HUD.
    case standard
    /// HR + pace only. Distraction-light, useful for races / intervals.
    case minimal
    /// HR + pace + distance + duration + cadence (+ elevation). For training.
    case dataDense

    /// The preset the watch app applies automatically on connect when the
    /// caller hasn't picked one. Per scope decision 5b this is the entire UX
    /// surface for v0.2.
    public static let `default`: RunningHUDPreset = .standard

    /// Human-readable label, ready for a future picker UI without re-deriving.
    public var displayName: String {
        switch self {
        case .standard:  return "Standard"
        case .minimal:   return "Minimal"
        case .dataDense: return "Data Dense"
        }
    }

    /// The curated `HUDLayout` this preset maps to. Single source of truth for
    /// slot ordering — formatters and field-index assignments derive from this.
    public var layout: HUDLayout {
        switch self {
        case .standard:  return .balancedRun()
        case .minimal:   return .minimalRun()
        case .dataDense: return .telemetryRun()
        }
    }

    /// String layout ID consumed by `GlassesFrameTransport.selectLayout(id:)`.
    public var layoutID: String { layout.id }

    /// On-device numeric slot the ActiveLook glasses use to activate the
    /// pre-baked layout. Resolves through `CuratedLayoutCatalog` so the
    /// device-ID mapping stays in one place.
    ///
    /// Returns `nil` if the catalog has no entry for this preset's layout —
    /// callers should treat that as a configuration error (preset added but
    /// not yet baked onto the glasses).
    public var deviceLayoutID: UInt8? {
        CuratedLayoutCatalog.deviceID(for: layoutID)
    }

    /// Pre-encoded ActiveLook BLE frame (`0x62 displayLayout`) ready to write
    /// to the RX characteristic. Returns `nil` for a preset whose layout is
    /// not in the curated catalog.
    ///
    /// This is the contract the v0.2 #5 backend exposes: callers (the
    /// adapter, the future picker, Mirror) get a ready-to-ship `[UInt8]`
    /// without reaching into `ActiveLookCommand` directly.
    public func layoutDescriptor() -> [UInt8]? {
        guard let id = deviceLayoutID else { return nil }
        return ActiveLookCommand.displayLayout(id: id)
    }
}
