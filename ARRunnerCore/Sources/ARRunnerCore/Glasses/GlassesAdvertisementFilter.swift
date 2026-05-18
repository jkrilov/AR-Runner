// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure helper for filtering BLE advertising payloads down to ActiveLook /
/// Microoled glasses (Engo 2, etc.).
///
/// Lives in `ARRunnerCore` rather than the watch target so the logic is
/// exercised on the Linux CI runner without needing CoreBluetooth.
///
/// ## Why this exists
///
/// PR #42 originally scanned with `withServices: [activeLookCommandServiceUUID]`.
/// ActiveLook / Engo 2 glasses do **not** include their 128-bit command
/// service UUID in the connectable advertising packet — it is only exposed
/// in the GATT table after connection. CoreBluetooth's service-UUID scan
/// filter matches against the advertising payload, so `didDiscover` was
/// never invoked and the watch hung on "Scanning…" forever.
///
/// ActiveLook's own iOS SDK (`Sources/Classes/Public/ActiveLookSDK.swift`)
/// scans with `withServices: nil` and filters in `didDiscover` by
/// **manufacturer data** prefix `0xFA 0xDA` (little-endian Bluetooth SIG
/// company identifier 0xDAFA — Microoled). That source carries a literal
/// `// Scanning with services list not working` comment next to the scan
/// call. This helper mirrors that filter.
public enum GlassesAdvertisementFilter {
    /// The Bluetooth SIG company identifier for Microoled, encoded in
    /// little-endian order as it appears on the wire (and in
    /// `CBAdvertisementDataManufacturerDataKey` payloads).
    public static let microoledManufacturerPrefix: [UInt8] = [0xFA, 0xDA]

    /// Returns `true` when the supplied manufacturer-data blob carries the
    /// Microoled / ActiveLook company-ID prefix. Returns `false` for nil,
    /// short, or differently-prefixed data.
    ///
    /// - Parameter manufacturerData: Raw bytes pulled from
    ///   `advertisementData[CBAdvertisementDataManufacturerDataKey]` in the
    ///   `centralManager(_:didDiscover:advertisementData:rssi:)` delegate.
    public static func isActiveLookPeripheral(manufacturerData: Data?) -> Bool {
        guard let manufacturerData, manufacturerData.count >= microoledManufacturerPrefix.count else {
            return false
        }
        for (i, expected) in microoledManufacturerPrefix.enumerated() {
            if manufacturerData[manufacturerData.startIndex + i] != expected {
                return false
            }
        }
        return true
    }
}
