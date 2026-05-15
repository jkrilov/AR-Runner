// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

/// v0.2 #5 — backend-only HUD preset contract.
///
/// Asserts the `RunningHUDPreset` API the watch app and any future picker
/// rely on: stable `rawValue`s for persistence, a `default` we can apply on
/// connect, every preset round-trips through Codable, and the
/// `layoutDescriptor()` payload encodes correctly through the
/// `ActiveLookCommand.displayLayout(id:)` framer the BLE adapter ships.
final class RunningHUDPresetTests: XCTestCase {

    func testAllCases_HaveStableRawValuesForPersistence() {
        // Locked: changing these rawValues invalidates persisted preferences
        // (when a picker eventually ships in v0.3+). If you really need to
        // rename, also write a migration.
        XCTAssertEqual(RunningHUDPreset.standard.rawValue,  "standard")
        XCTAssertEqual(RunningHUDPreset.minimal.rawValue,   "minimal")
        XCTAssertEqual(RunningHUDPreset.dataDense.rawValue, "dataDense")
        XCTAssertEqual(RunningHUDPreset.allCases.count, 3)
    }

    func testDefaultIsStandard() {
        // Per scope decision 5b: the watch app uses `default` on connect with
        // no picker UI in v0.2. Standard is the right baseline runner's HUD.
        XCTAssertEqual(RunningHUDPreset.default, .standard)
    }

    func testDisplayNamesArePopulated() {
        for preset in RunningHUDPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty,
                           "\(preset) must expose a non-empty displayName for future picker UI")
        }
    }

    func testLayoutMappingsMatchCuratedHUDLayouts() {
        XCTAssertEqual(RunningHUDPreset.standard.layout,  .balancedRun())
        XCTAssertEqual(RunningHUDPreset.minimal.layout,   .minimalRun())
        XCTAssertEqual(RunningHUDPreset.dataDense.layout, .telemetryRun())

        XCTAssertEqual(RunningHUDPreset.standard.layoutID,  "balanced-run")
        XCTAssertEqual(RunningHUDPreset.minimal.layoutID,   "minimal-run")
        XCTAssertEqual(RunningHUDPreset.dataDense.layoutID, "telemetry-run")
    }

    func testEveryPresetResolvesToCuratedDeviceID() {
        // No silent .none holes: every preset must be in the catalog or the
        // adapter would drop the layout descriptor on connect.
        for preset in RunningHUDPreset.allCases {
            XCTAssertNotNil(preset.deviceLayoutID,
                            "\(preset) is missing a CuratedLayoutCatalog entry")
            XCTAssertNotNil(preset.layoutDescriptor(),
                            "\(preset).layoutDescriptor() must be non-nil")
        }
    }

    /// Round-trip every preset's descriptor through the same framing the
    /// `ActiveLookGlassesAdapter` uses on the wire. Asserts the exact bytes
    /// match `ActiveLookCommand.displayLayout(id:)` so we never accidentally
    /// double-frame, regress to v0.1's text-on-display bug, or misroute a
    /// preset to the wrong device slot.
    func testLayoutDescriptorRoundTripMatchesActiveLookFraming() throws {
        for preset in RunningHUDPreset.allCases {
            let id = try XCTUnwrap(preset.deviceLayoutID,
                                   "\(preset) missing device id")
            let descriptor = try XCTUnwrap(preset.layoutDescriptor())
            let expected = ActiveLookCommand.displayLayout(id: id)
            XCTAssertEqual(descriptor, expected,
                           "Preset \(preset) descriptor must match displayLayout(id: 0x\(String(id, radix: 16)))")

            // Frame envelope sanity per ActiveLook spec §3.1:
            //   start byte 0xFF, cmdID 0x62, ..., terminator 0xAA, payload [id].
            XCTAssertEqual(descriptor.first, 0xFF, "ActiveLook frames start with 0xFF")
            XCTAssertEqual(descriptor.last,  0xAA, "ActiveLook frames terminate with 0xAA")
            XCTAssertEqual(descriptor[1], ActiveLookCommand.ID.layoutDisplay.rawValue,
                           "Preset descriptor must use cmdID 0x62 (layoutDisplay)")
            XCTAssertTrue(descriptor.contains(id),
                          "Frame must carry the resolved on-device layout id")
        }
    }

    func testCodableRoundTrip() throws {
        for preset in RunningHUDPreset.allCases {
            let data = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(RunningHUDPreset.self, from: data)
            XCTAssertEqual(decoded, preset)
        }
    }
}
