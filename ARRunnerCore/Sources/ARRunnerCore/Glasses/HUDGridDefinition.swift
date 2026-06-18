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
}
