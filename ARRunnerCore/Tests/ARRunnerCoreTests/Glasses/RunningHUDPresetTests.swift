// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// v0.2 Workstream #5 — `RunningHUDPreset` contract tests.
///
/// This file is the **post-merge union** of two parallel PRs:
///
///   * Amber's anticipatory contract tests from PR #14
///     (`feat/v02-preset-contract-tests`) — 5 tests written *before* the
///     `RunningHUDPreset` enum existed, originally guarded with
///     `XCTSkipIf(true, "EXPECTED-FAILING-UNTIL: v0.2 #5 implementation")`
///     and a commented-out `// CONTRACT-BODY:` sketch. The skip gates have
///     been removed and the bodies activated/adapted now that the real
///     implementation is in scope (PR #15).
///   * Weiss's implementation-side contract tests from PR #15
///     (`feat/v02-reconnect-and-presets`) — 7 tests covering the surface
///     Amber's bullets implied (rawValue stability, displayName, curated
///     `HUDLayout` mapping, deviceLayoutID resolution, on-the-wire frame
///     bytes, Codable round-trip).
///
/// The two sets are complementary: Amber's express the *intent* (≥3 cases,
/// sensible default, distinct descriptors, ships through ActiveLook,
/// running-domain field semantics); Weiss's lock the *concrete* shape
/// (`.standard`/`.minimal`/`.dataDense`, balanced/minimal/telemetry layouts,
/// 0x62 displayLayout framing, persistence-grade rawValues).
///
/// Locked v0.2 decisions exercised here:
///   * **v0.2 #5 (BACKEND ONLY)** — `RunningHUDPreset` constants live in
///     `ARRunnerCore`. Watch picks `default` on connect. **No picker UI**
///     in v0.2; preset selection plumbing arrives in v0.3.
///   * **D6** — Curated baked layouts only; no on-device editor.
///   * **D5 / Offline** — Presets must be pure-Swift, allocation-light, and
///     resolvable without phone or network.
///
/// Anticipatory pattern reference:
///   `.squad/skills/anticipatory-contract-tests/SKILL.md` (Amber).
final class RunningHUDPresetTests: XCTestCase {

    // MARK: - Implementation contract (Weiss, PR #15)

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
            //   start byte 0xFF, cmdID 0x62, ..., terminator 0xAA, payload
            //   [id, text, 0x00] (text empty for a bare activation frame).
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

    // MARK: - Anticipatory contract (Amber, PR #14 — gates flipped on)

    // MARK: - 1. Existence + cases

    /// Locks: `RunningHUDPreset` exists, is `CaseIterable`, has at least
    /// 3 cases. The "≥ 3" floor matches D6 (curated set) and the
    /// `.standard` / `.minimal` / `.dataDense` trio.
    func testPresetTypeExistsWithAtLeastThreeCases() throws {
        let cases = RunningHUDPreset.allCases
        XCTAssertGreaterThanOrEqual(
            cases.count, 3,
            "Curated D6 set requires at least 3 presets (standard / minimal / dataDense)."
        )
        // Sendable + RawRepresentable<String> are part of the public contract.
        for preset in cases {
            XCTAssertFalse(preset.rawValue.isEmpty,
                           "Each case must have a non-empty stable rawValue for storage.")
        }
    }

    // MARK: - 2. Sensible default

    /// Locks: `RunningHUDPreset.default` returns a member of `allCases`,
    /// and it is the *general-running* preset — NOT `.minimal`
    /// (distraction-light, intentionally sparse) and NOT `.dataDense`
    /// (training-specific, cognitively heavy).
    func testDefaultIsSensibleGeneralRunningPreset() throws {
        let chosen = RunningHUDPreset.default
        XCTAssertTrue(
            RunningHUDPreset.allCases.contains(chosen),
            "default must be one of the named cases (no synthesized 'unknown')."
        )
        XCTAssertNotEqual(
            chosen, .minimal,
            "default must not be .minimal — too sparse for first-connect general running."
        )
        XCTAssertNotEqual(
            chosen, .dataDense,
            "default must not be .dataDense — that's training-specific (intervals/coaching)."
        )
    }

    // MARK: - 3. Layout descriptor round-trip

    /// Locks: `layoutDescriptor()` returns a non-empty value for every
    /// case, AND each case returns a *distinct* descriptor. Without this,
    /// presets could silently collapse into aliases of one another.
    func testEachPresetHasDistinctNonEmptyLayoutDescriptor() throws {
        var seen: [[UInt8]] = []
        for preset in RunningHUDPreset.allCases {
            let descriptor = try XCTUnwrap(
                preset.layoutDescriptor(),
                "\(preset).layoutDescriptor() returned nil — preset has no content to ship."
            )
            XCTAssertFalse(
                descriptor.isEmpty,
                "\(preset).layoutDescriptor() returned an empty value."
            )
            XCTAssertFalse(
                seen.contains(descriptor),
                "\(preset) produced a duplicate layoutDescriptor — presets must not be aliases."
            )
            seen.append(descriptor)
        }
        XCTAssertEqual(seen.count, RunningHUDPreset.allCases.count)
    }

    // MARK: - 4. ActiveLook frame compatibility

    /// Locks: each preset descriptor can be shipped via the existing
    /// `ActiveLookCommand.displayLayout(id:)` encoder without throwing,
    /// and the resulting wire frame is a structurally valid ActiveLook
    /// frame (starts 0xFF, ends 0xAA, ≥ 6 bytes). Plus an integration
    /// assertion that `MockGlassesFrame.selectLayout` accepts every
    /// preset's `layoutID`.
    func testEachPresetShipsThroughActiveLookFrameWithoutThrowing() async throws {
        let glasses = MockGlassesFrame()
        try await glasses.connect()

        for preset in RunningHUDPreset.allCases {
            let slotID = try XCTUnwrap(
                preset.deviceLayoutID,
                "\(preset) missing on-device layout slot ID"
            )

            let frame = ActiveLookCommand.displayLayout(id: slotID)
            XCTAssertEqual(frame.first, 0xFF, "\(preset): frame must start with ActiveLook start byte 0xFF.")
            XCTAssertEqual(frame.last,  0xAA, "\(preset): frame must end with ActiveLook footer 0xAA.")
            XCTAssertGreaterThanOrEqual(frame.count, 6, "\(preset): minimum frame size is 6 bytes.")

            try await glasses.selectLayout(id: preset.layoutID)
        }

        let recorded = await glasses.selectedLayouts
        XCTAssertEqual(
            recorded.count, RunningHUDPreset.allCases.count,
            "Every preset should have been shipped to glasses.selectLayout exactly once."
        )
        XCTAssertEqual(
            Set(recorded), Set(RunningHUDPreset.allCases.map(\.layoutID)),
            "Recorded layout IDs must match every preset's layoutID."
        )
    }

    // MARK: - 5. Per-preset field selection (running-domain semantics)

    /// Locks the *fitness-domain* contract:
    ///   * `.minimal` includes HR (safety-relevant) but EXCLUDES cadence
    ///     (training noise for casual runs).
    ///   * `.dataDense` includes both HR and cadence (training mode).
    ///   * `.standard` includes HR.
    /// Plus a soft monotonic guard so a future "simplify" refactor can't
    /// silently collapse the presets into identical field sets.
    func testPresetsExposeRunningDomainAppropriateFields() throws {
        func metrics(of preset: RunningHUDPreset) -> Set<MetricKind> {
            Set(preset.layout.slots.compactMap { $0 })
        }

        let minimal   = metrics(of: .minimal)
        let standard  = metrics(of: .standard)
        let dataDense = metrics(of: .dataDense)

        XCTAssertTrue(minimal.contains(.heartRate),
            ".minimal must surface heartRate — safety-relevant during running.")
        XCTAssertFalse(minimal.contains(.cadence),
            ".minimal must NOT surface cadence — training-specific noise for casual runs.")

        XCTAssertTrue(standard.contains(.heartRate),
            ".standard must surface heartRate.")

        XCTAssertTrue(dataDense.contains(.cadence),
            ".dataDense must surface cadence — training/coaching mode.")
        XCTAssertTrue(dataDense.contains(.heartRate),
            ".dataDense must surface heartRate.")

        // Soft monotonic guard: dataDense should be the richest preset.
        XCTAssertGreaterThanOrEqual(dataDense.count, standard.count,
            ".dataDense must expose at least as many metrics as .standard.")
        XCTAssertGreaterThanOrEqual(standard.count, minimal.count,
            ".standard must expose at least as many metrics as .minimal.")
    }
}
