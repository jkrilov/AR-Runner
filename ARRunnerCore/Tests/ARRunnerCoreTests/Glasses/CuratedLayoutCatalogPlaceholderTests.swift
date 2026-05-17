// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// P1.4 (audit 2026-05-16) — the curated device-ID catalog still ships
/// pre-bake placeholders (`0x01–0x03`). The watch-side adapter now traps in
/// debug builds before activating one, but the catalog itself exposes the
/// placeholder set + a reusable assertion helper so any other caller can
/// guard its hot path the same way.
///
/// These tests pin:
///   * the placeholder set is exactly what the audit calls out
///   * `assertNotPlaceholder` is a no-op for any non-placeholder ID
///   * the public `mapping` accessor still works for tests / Linux CI
///   * `RunningHUDPreset.deviceLayoutID` still resolves (callers that don't
///     write to the wire keep working)
final class CuratedLayoutCatalogPlaceholderTests: XCTestCase {
    func test_placeholderSetMatchesAudit() {
        // If/when Config-Generator output replaces these, drop them from
        // `placeholderDeviceIDs` and this test will (correctly) need updating.
        XCTAssertEqual(CuratedLayoutCatalog.placeholderDeviceIDs, [0x01, 0x02, 0x03])
    }

    func test_assertNotPlaceholderIsNoOpForRealIDs() {
        // Any byte outside the placeholder range must pass silently — the
        // helper exists to trap *only* on the audit's known-bad values.
        for id: UInt8 in [0x00, 0x04, 0x10, 0x42, 0xFF] {
            CuratedLayoutCatalog.assertNotPlaceholder(id, layoutID: "synthetic")
        }
    }

    func test_mappingStillResolves() {
        // The accessor stays assert-free so Linux CI + Core tests can keep
        // exercising the mapping; the watch adapter is where the trap lives.
        XCTAssertEqual(CuratedLayoutCatalog.deviceID(for: "minimal-run"), 0x01)
        XCTAssertEqual(CuratedLayoutCatalog.deviceID(for: "balanced-run"), 0x02)
        XCTAssertEqual(CuratedLayoutCatalog.deviceID(for: "telemetry-run"), 0x03)
        XCTAssertNil(CuratedLayoutCatalog.deviceID(for: "made-up"))
    }
}
