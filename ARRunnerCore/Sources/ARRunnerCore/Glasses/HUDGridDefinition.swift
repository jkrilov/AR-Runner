// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Compile-time, fixed-slot HUD geometry for the Engo 2 raw-`txt` render
/// path (v0.6.0 — constrained-custom layouts).
///
/// **Why this exists.** `HUDLayout` says *which metric* lives in *which slot
/// index*; `HUDGridDefinition` says *where on the panel* each slot index
/// paints. Keeping geometry in code (not in the `Codable` `HUDLayout`)
/// prevents the coordinate-regression class of bugs that dominated the
/// rc11→rc16 bench cycle: the lens-flip math and bench-validated anchors are
/// validated once in unit tests and never become user-editable.
///
/// The shipped `standard4` grid reuses the exact rc16 bench-validated
/// coordinates from `RunningHUDFrame.Layout`:
///
/// ```
/// slot 0  line 1 left   (Time/primary, font 2)   text fb (243, 240)
/// slot 1  line 1 right  (HR/secondary, font 2)    text fb ( 83, 240)
/// slot 2  line 2        (font 3)                   text fb (243, 170)
/// slot 3  line 3        (font 3)                   text fb (243,  77)
/// ```
///
/// `Sendable` value type; intentionally **not** `Codable` (geometry is a
/// code constant, not synced state).
public struct HUDGridDefinition: Sendable, Equatable {
    /// Geometry for one HUD slot. All coordinates follow the rc16 lens-flip
    /// convention: text anchors are framebuffer-space under `rotation = 4`
    /// (topLR), while the icon is positioned from its wearer-space left edge
    /// and the line's wearer-space vertical centre so icons of different
    /// sizes (40×40 chrono vs. 28×28 heart/distance/pace) stay centred on
    /// the line regardless of which metric lands in the slot.
    public struct Slot: Sendable, Equatable {
        /// Framebuffer x-anchor (topLR — text grows LEFT from here).
        public let textX: Int16
        /// Framebuffer y-anchor (`y_fb = 255 − wearer_top`).
        public let textY: Int16
        /// ActiveLook stock font index for this slot's text.
        public let font: UInt8
        /// Wearer-space left edge of this slot's icon gutter.
        public let iconWearerLeft: Int16
        /// Wearer-space vertical centre of the slot's text line, used to
        /// vertically centre the (variable-height) metric icon.
        public let iconWearerCenterY: Int16

        public init(
            textX: Int16,
            textY: Int16,
            font: UInt8,
            iconWearerLeft: Int16,
            iconWearerCenterY: Int16
        ) {
            self.textX = textX
            self.textY = textY
            self.font = font
            self.iconWearerLeft = iconWearerLeft
            self.iconWearerCenterY = iconWearerCenterY
        }
    }

    /// Slots in layout-index order (slot 0 is the prominent top-left line).
    public let slots: [Slot]

    public init(slots: [Slot]) {
        self.slots = slots
    }

    /// The shipped 4-slot grid. Coordinates are the rc16 bench-validated
    /// anchors (see `RunningHUDFrame.Layout` for the full derivation):
    /// `liveLeftMargin = 243`, `liveHRX = 83`, `liveLine1Y = 240`,
    /// `liveDistanceY = 170`, `livePaceY = 77`. The icon-gutter wearer
    /// coordinates reproduce the rc16 chrono/heart/distance/pace icon
    /// positions to within ±1 px under the centre-based icon model.
    public static let standard4 = HUDGridDefinition(slots: [
        // Line 1 left — primary metric (font 2, shares the line with slot 1).
        Slot(textX: 243, textY: 240, font: 2, iconWearerLeft: 15,  iconWearerCenterY: 35),
        // Line 1 right — secondary metric (font 2).
        Slot(textX: 83,  textY: 240, font: 2, iconWearerLeft: 187, iconWearerCenterY: 34),
        // Line 2 — font 3.
        Slot(textX: 243, textY: 170, font: 3, iconWearerLeft: 27,  iconWearerCenterY: 117),
        // Line 3 — font 3.
        Slot(textX: 243, textY: 77,  font: 3, iconWearerLeft: 27,  iconWearerCenterY: 210),
    ])

    // MARK: - Variable grid factory (v0.6.5)

    /// Build the flat, code-only `[Slot]` geometry for a `HUDGridConfig`
    /// *shape* (line count + items-per-line). The slot order is row-major and
    /// matches the flattened `HUDLayout.slots`, so the existing renderer
    /// consumes the result with zero changes.
    ///
    /// **Provenance.** The `[2, 1, 1]` default returns the bench-validated
    /// `standard4` byte-for-byte (zero regression for the shipped outdoor-run
    /// HUD). Every other shape is derived by the same lens-flip budgeting
    /// method documented in Weiss's variable-grid plan but is **EXTRAP** — not
    /// yet validated on glass. Those coordinates carry `// TODO(bench)`
    /// markers and must be calibrated on an Engo 2 before being trusted.
    public static func make(for config: HUDGridConfig) -> HUDGridDefinition {
        let valid = config.validated()

        // Byte-identical fast path for the shipped default shape.
        if valid.lines == HUDGridConfig.standard.lines {
            return standard4
        }

        let lineCount = valid.lines.count
        // TODO(bench): calibrate band-top skeletons on Engo 2 — only the
        // 3-line `[2,1,1]` path (handled above) is bench-proven today.
        let bandTops = bandTops(forLineCount: lineCount)
        let font1 = oneItemFont(forLineCount: lineCount)
        let font2 = twoItemFont(forLineCount: lineCount)

        var slots: [Slot] = []
        for (rowIndex, items) in valid.lines.enumerated() {
            let baseTop = bandTops[rowIndex]
            if items == 1 {
                // Proven left-aligned icon+value form (standard4 lines 2/3).
                let centerY = baseTop + Int16(ALookFontMetrics.height(font1) / 2)
                slots.append(Slot(
                    textX: 243, textY: 255 - baseTop, font: font1,
                    iconWearerLeft: 27, iconWearerCenterY: centerY
                ))
            } else {
                // Two metrics share the line. Drop the band top so the smaller
                // 2-item glyphs sit centred against the line's 1-item height.
                let offset = twoItemDropOffset(forLineCount: lineCount, rowIndex: rowIndex)
                let top = baseTop + offset
                let textY = 255 - top
                let centerY = top + Int16(ALookFontMetrics.height(font2) / 2)
                // Left slot — anchored at the line's right margin, grows left.
                slots.append(Slot(
                    textX: 243, textY: textY, font: font2,
                    iconWearerLeft: 15, iconWearerCenterY: centerY
                ))
                // Right slot — the historically tight horizontal budget.
                slots.append(Slot(
                    textX: 83, textY: textY, font: font2,
                    iconWearerLeft: 187, iconWearerCenterY: centerY
                ))
            }
        }
        return HUDGridDefinition(slots: slots)
    }

    /// Band-top `T` (wearer-space top-of-glyph) per row for a given line count.
    /// `textY_fb = 255 − T`. Values copied from Weiss's variable-grid plan.
    /// TODO(bench): all non-`[2,1,1]` skeletons are EXTRAP — calibrate on glass.
    private static func bandTops(forLineCount lineCount: Int) -> [Int16] {
        switch lineCount {
        case 2: return [28, 153]              // TODO(bench): 2-line big-font, never benched
        case 4: return [13, 77, 141, 205]     // TODO(bench): 4-line font-2 skeleton
        default: return [15, 85, 178]         // 3-line — anchored to standard4
        }
    }

    /// 1-item-line font for a given line count (fewer lines → taller font).
    private static func oneItemFont(forLineCount lineCount: Int) -> UInt8 {
        switch lineCount {
        case 2: return 4   // TODO(bench): font 4 (75px) — EXTRAP
        case 4: return 2
        default: return 3
        }
    }

    /// 2-item-line font for a given line count. A 2-item line never exceeds
    /// font 3 (two wide metrics collide horizontally — the rc15 lesson).
    private static func twoItemFont(forLineCount lineCount: Int) -> UInt8 {
        switch lineCount {
        case 2: return 3   // TODO(bench): 2-item @ font 3 — EXTRAP
        default: return 2
        }
    }

    /// Vertical offset added to a 2-item line's band top so the smaller glyphs
    /// centre against the line's 1-item height. Per-(lineCount,row) lookup —
    /// the shipped 3-line L1 is proven at offset 0; the rest are EXTRAP.
    /// TODO(bench): calibrate the drop offsets on glass.
    private static func twoItemDropOffset(forLineCount lineCount: Int, rowIndex: Int) -> Int16 {
        switch lineCount {
        case 2: return 6                       // TODO(bench): 2-line drop, EXTRAP
        case 3: return rowIndex == 0 ? 0 : 13  // L1 proven (0); L2/L3 EXTRAP (+13)
        default: return 0                      // 4-line: 2-item font == 1-item font
        }
    }
}
