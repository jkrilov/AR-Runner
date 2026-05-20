// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pixel metrics for the stock ALooK preloaded fonts shipped on Engo 2.
///
/// **Why this exists.** Heights and widths for ALooK fonts were spread as
/// inline magic numbers across `RunningHUDFrame.Layout` (heights in the
/// doc block, widths only documented in prose like "~28 px/char"). Richards's
/// rc13→rc16 review flagged the heights-as-typed-code pattern as a
/// readability risk; rc2's right-justified pace on the new finish-screen
/// line 3 (`summaryPaceXFB(for:)`) needs **width** measurements as well,
/// which finally justifies extracting a one-stop metric table.
///
/// **Source of truth.** Heights come from the ActiveLook-Visual-Assets repo
/// README (per the same reference Richards used in rc16):
///   Font 1 = 24 px, Font 2 = 38 px, Font 3 = 64 px, Font 4 = 75 px,
///   Font 5 = 82 px.
/// Widths are empirical estimates per font (the ALooK preloaded fonts are
/// proportional but the digits/colons/slashes used in the HUD are close
/// enough to monospace that a single per-font width yields a usable
/// bounding box). The HUD strings are short (≤ 10 chars) so a few pixels
/// of slack on either end is fine — right-justify just needs to stay on
/// panel, not pixel-perfect.
public enum ALookFontMetrics {
    /// Heights of the stock ALooK preloaded fonts in pixels.
    /// Indexed by ALooK font ID (1..5). Returns 0 for unknown IDs.
    public static func height(_ fontSize: UInt8) -> Int {
        switch fontSize {
        case 1: return 24
        case 2: return 38
        case 3: return 64
        case 4: return 75
        case 5: return 82
        default: return 0
        }
    }

    /// Empirical per-glyph average width for HUD strings (digits, colons,
    /// slashes, letters). Conservative — slightly over-estimates so a
    /// right-justified column has a safe margin instead of clipping.
    public static func averageGlyphWidth(_ fontSize: UInt8) -> Int {
        switch fontSize {
        case 1: return 10
        case 2: return 18
        case 3: return 28
        case 4: return 33
        case 5: return 36
        default: return 0
        }
    }

    /// Estimated pixel width of `string` rendered at `fontSize`. ASCII
    /// glyphs only (the HUD never renders multi-codepoint clusters); each
    /// counts as one glyph at the per-font average width.
    public static func width(of string: String, fontSize: UInt8) -> Int {
        string.count * averageGlyphWidth(fontSize)
    }
}
