// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One slot-update inside a curated D6 layout.
///
/// Encoding into the ActiveLook wire frame happens at the adapter boundary;
/// this type stays vendor-agnostic so Amber's mock and any future transport
/// (e.g. simulator overlay) can consume it directly.
public struct HUDFieldUpdate: Sendable, Equatable, Codable {
    /// String ID of the layout this field belongs to (e.g. `"balanced-run"`).
    /// The adapter is responsible for resolving this to the numeric layout
    /// slot baked onto the glasses.
    public let layoutID: String
    /// Slot index within the layout. Matches `HUDLayout.slots` ordering.
    public let fieldIndex: UInt8
    /// Pre-formatted display string ("5:42", "142", "3.1mi"). The adapter
    /// does not reformat — formatting decisions live with the metric source.
    public let value: String

    public init(layoutID: String, fieldIndex: UInt8, value: String) {
        self.layoutID = layoutID
        self.fieldIndex = fieldIndex
        self.value = value
    }
}
