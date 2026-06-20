// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The *shape* of a custom HUD layout: how many lines it has (2…4) and how
/// many metrics share each line (1 or 2). This is the only geometry-adjacent
/// state that is `Codable`/synced — the actual pixel coordinates and fonts
/// stay in code (`HUDGridDefinition`), the firewall against the rc11→rc16
/// coordinate-regression class of bugs.
///
/// `lines` is row-major: `[2, 1, 1]` is the shipped 3-line "standard4" shape
/// (line 1 holds two metrics side-by-side, lines 2 and 3 each hold one). The
/// flattened `HUDLayout.slots` array carries one entry per item in row order,
/// so `slotCount` must equal `slots.count` for a well-formed layout.
public struct HUDGridConfig: Sendable, Codable, Equatable, Hashable {
    /// Per-line item counts, row-major. Count is 2…4; each element is 1 or 2.
    public let lines: [Int]

    public init(lines: [Int]) {
        self.lines = lines
    }

    /// The shipped default shape — three lines, the first holding two metrics
    /// (`[2, 1, 1]`), identical to the legacy fixed `standard4` grid. A `nil`
    /// `HUDLayout.grid` is interpreted as this, so pre-v0.6.5 layouts render
    /// byte-identically.
    public static let standard = HUDGridConfig(lines: [2, 1, 1])

    /// Total number of metric slots this shape contains (the sum of all
    /// per-line item counts).
    public var slotCount: Int { lines.reduce(0, +) }

    /// Whether this config is within the supported ranges: 2…4 lines, each
    /// holding 1 or 2 items.
    public var isValid: Bool {
        (2...4).contains(lines.count) && lines.allSatisfy { $0 == 1 || $0 == 2 }
    }

    /// A sanitised copy: out-of-range line counts and per-line item counts are
    /// clamped into the supported ranges. A fully invalid config (e.g. empty)
    /// falls back to ``standard`` so the render path always has a usable shape
    /// (mirrors the dangling-id resolver fallback).
    public func validated() -> HUDGridConfig {
        guard !lines.isEmpty else { return .standard }
        let clampedLines = lines.map { min(2, max(1, $0)) }
        let trimmed: [Int]
        if clampedLines.count < 2 {
            // Pad single-line configs up to the 2-line minimum.
            trimmed = clampedLines + Array(repeating: 1, count: 2 - clampedLines.count)
        } else if clampedLines.count > 4 {
            trimmed = Array(clampedLines.prefix(4))
        } else {
            trimmed = clampedLines
        }
        return HUDGridConfig(lines: trimmed)
    }
}
