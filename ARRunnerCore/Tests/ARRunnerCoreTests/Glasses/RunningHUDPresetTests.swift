// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// v0.2 Workstream #5 — `RunningHUDPreset` contract tests (ANTICIPATORY).
///
/// This file is written BEFORE Weiss's `RunningHUDPreset` enum lands in
/// `ARRunnerCore/Sources/ARRunnerCore/Glasses/RunningHUDPreset.swift`. Each
/// test below encodes one bullet of the public contract Weiss is
/// implementing against; every one of them is currently
/// `XCTSkipIf(true, "EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — ...")`
/// with the body kept as a `// commented-out` sketch so the Swift target
/// continues to compile while `RunningHUDPreset` does not exist.
///
/// **How to "turn this file on" when v0.2 #5 lands** (Weiss / reviewer):
///   1. In each test, delete the `try XCTSkipIf(true, ...)` line.
///   2. Uncomment the `// CONTRACT-BODY:` block immediately below it.
///   3. If Weiss picked different case names, do a search/replace inside
///      this file ONLY (`.standard` → final name, etc.). The contract
///      *shape* (3+ cases, sensible default, distinct descriptors,
///      ActiveLook-shippable) is what matters; the names are flex.
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
///   This is the SECOND independent application of the pattern after
///   `DisconnectResilienceTests` (v0.2 #4).
final class RunningHUDPresetTests: XCTestCase {

    // MARK: - 1. Existence + cases

    /// Locks: `RunningHUDPreset` exists, is `CaseIterable`, has at least
    /// 3 cases. The "≥ 3" floor matches D6 (curated set) and the spawn
    /// prompt's `.standard` / `.minimal` / `.dataDense` trio.
    func testPresetTypeExistsWithAtLeastThreeCases() throws {
        // EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss.
        try XCTSkipIf(
            true,
            "EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss."
        )

        // CONTRACT-BODY (uncomment when Weiss's PR lands):
        // let cases = RunningHUDPreset.allCases
        // XCTAssertGreaterThanOrEqual(
        //     cases.count, 3,
        //     "Curated D6 set requires at least 3 presets (standard / minimal / dataDense)."
        // )
        // // Sendable + RawRepresentable<String> are part of the public contract.
        // for preset in cases {
        //     XCTAssertFalse(preset.rawValue.isEmpty, "Each case must have a non-empty stable rawValue for storage.")
        // }
    }

    // MARK: - 2. Sensible default

    /// Locks: `RunningHUDPreset.default` returns a member of `allCases`,
    /// and it is the *general-running* preset — NOT `.minimal`
    /// (distraction-light, intentionally sparse) and NOT `.dataDense`
    /// (training-specific, cognitively heavy). For most runners on first
    /// connect, the default should land on the balanced middle option.
    func testDefaultIsSensibleGeneralRunningPreset() throws {
        // EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss.
        try XCTSkipIf(
            true,
            "EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss."
        )

        // CONTRACT-BODY (uncomment when Weiss's PR lands):
        // let chosen = RunningHUDPreset.default
        // XCTAssertTrue(
        //     RunningHUDPreset.allCases.contains(chosen),
        //     "default must be one of the named cases (no synthesized 'unknown')."
        // )
        // XCTAssertNotEqual(
        //     chosen, .minimal,
        //     "default must not be .minimal — too sparse for first-connect general running."
        // )
        // XCTAssertNotEqual(
        //     chosen, .dataDense,
        //     "default must not be .dataDense — that's training-specific (intervals/coaching)."
        // )
        // // Implicitly: default == .standard (or whichever balanced case Weiss picks).
    }

    // MARK: - 3. Layout descriptor round-trip

    /// Locks: `layoutDescriptor()` returns a non-empty/non-default value
    /// for every case, AND each case returns a *distinct* descriptor.
    /// Without this, presets could silently collapse into aliases of one
    /// another and the user-visible "I picked dataDense" would be a lie.
    func testEachPresetHasDistinctNonEmptyLayoutDescriptor() throws {
        // EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss.
        try XCTSkipIf(
            true,
            "EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss."
        )

        // CONTRACT-BODY (uncomment when Weiss's PR lands):
        // let descriptors = RunningHUDPreset.allCases.map { ($0, $0.layoutDescriptor()) }
        //
        // // (a) Non-empty / non-default for every preset.
        // // The descriptor type is Weiss's call (HUDLayout, [UInt8], a struct, ...).
        // // The contract is: it carries enough bytes/fields to ship a layout.
        // // For the common candidates, "non-empty" maps to:
        // //   * HUDLayout  → !slots.allSatisfy { $0 == nil }
        // //   * [UInt8]    → !isEmpty
        // //   * struct     → at least one field populated (Equatable != .init())
        // for (preset, descriptor) in descriptors {
        //     XCTAssertFalse(
        //         describedAsEmpty(descriptor),
        //         "\(preset).layoutDescriptor() returned an empty/default value — preset has no content to ship."
        //     )
        // }
        //
        // // (b) Distinct across all presets.
        // let unique = Set(descriptors.map { hashableForm($0.1) })
        // XCTAssertEqual(
        //     unique.count, descriptors.count,
        //     "Each RunningHUDPreset must produce a distinct layoutDescriptor — presets must not be aliases."
        // )
    }

    // MARK: - 4. ActiveLook frame compatibility

    /// Locks: each preset descriptor can be shipped via the existing
    /// `ActiveLookCommand.displayLayout(id:)` encoder without throwing,
    /// and the resulting wire frame is a structurally valid ActiveLook
    /// frame (starts 0xFF, ends 0xAA, length-byte matches actual length).
    /// This is the integration assertion that Weiss's preset descriptors
    /// actually round-trip through the frame layer Amber's mock captures.
    func testEachPresetShipsThroughActiveLookFrameWithoutThrowing() async throws {
        // EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss.
        try XCTSkipIf(
            true,
            "EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss."
        )

        // CONTRACT-BODY (uncomment when Weiss's PR lands):
        // let glasses = MockGlassesFrame()
        // try await glasses.connect()
        //
        // for preset in RunningHUDPreset.allCases {
        //     // Each preset must declare *some* on-device layout slot ID it maps to.
        //     // Weiss's PR will expose either preset.layoutSlotID (UInt8) or
        //     // include it inside the descriptor — adapt this line accordingly.
        //     let slotID: UInt8 = preset.activeLookLayoutSlotID
        //
        //     // The wire frame produced by ActiveLookCommand must be valid:
        //     let frame = ActiveLookCommand.displayLayout(id: slotID)
        //     XCTAssertEqual(frame.first, 0xFF, "\(preset): frame must start with ActiveLook start byte 0xFF.")
        //     XCTAssertEqual(frame.last,  0xAA, "\(preset): frame must end with ActiveLook footer 0xAA.")
        //     XCTAssertGreaterThanOrEqual(frame.count, 6, "\(preset): minimum frame size is 6 bytes.")
        //
        //     // And the canonical transport accepts the layout selection without throwing.
        //     try await glasses.selectLayout(id: preset.rawValue)
        // }
        //
        // let recorded = await glasses.selectedLayouts
        // XCTAssertEqual(
        //     recorded.count, RunningHUDPreset.allCases.count,
        //     "Every preset should have been shipped to glasses.selectLayout exactly once."
        // )
    }

    // MARK: - 5. Per-preset field selection (running-domain semantics)

    /// Locks the *fitness-domain* contract, not just the technical surface:
    ///   * `.minimal` includes HR (the safety-relevant metric runners check
    ///     mid-stride) but EXCLUDES cadence (a coaching/training metric
    ///     that's noise for casual runs).
    ///   * `.dataDense` includes cadence (training mode wants it).
    ///   * `.standard` sits between — has HR, but cadence is optional
    ///     (we only assert HR presence, not cadence absence).
    ///
    /// This is the assertion that catches a future refactor that
    /// "simplifies" the presets into identical field sets. Without it,
    /// the only thing distinguishing presets would be the rawValue string.
    func testPresetsExposeRunningDomainAppropriateFields() throws {
        // EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss.
        try XCTSkipIf(
            true,
            "EXPECTED-FAILING-UNTIL: v0.2 #5 implementation — RunningHUDPreset not yet defined. Owner: Weiss."
        )

        // CONTRACT-BODY (uncomment when Weiss's PR lands):
        // // Weiss's descriptor exposes a queryable field-set. Most likely shapes:
        // //   * descriptor.metricKinds: Set<MetricKind>
        // //   * descriptor.slots: [MetricKind?]  (HUDLayout-compatible)
        // // Either way, fold to a Set<MetricKind> for the assertions below.
        //
        // func metrics(of preset: RunningHUDPreset) -> Set<MetricKind> {
        //     // adapt one line to whichever accessor Weiss ships:
        //     return Set(preset.layoutDescriptor().slots.compactMap { $0 })
        // }
        //
        // let minimal     = metrics(of: .minimal)
        // let standard    = metrics(of: .standard)
        // let dataDense   = metrics(of: .dataDense)
        //
        // XCTAssertTrue(minimal.contains(.heartRate),
        //     ".minimal must surface heartRate — safety-relevant during running.")
        // XCTAssertFalse(minimal.contains(.cadence),
        //     ".minimal must NOT surface cadence — training-specific noise for casual runs.")
        //
        // XCTAssertTrue(standard.contains(.heartRate),
        //     ".standard must surface heartRate.")
        //
        // XCTAssertTrue(dataDense.contains(.cadence),
        //     ".dataDense must surface cadence — training/coaching mode.")
        // XCTAssertTrue(dataDense.contains(.heartRate),
        //     ".dataDense must surface heartRate.")
        //
        // // Soft monotonic guard: dataDense should be the richest preset.
        // XCTAssertGreaterThanOrEqual(dataDense.count, standard.count,
        //     ".dataDense must expose at least as many metrics as .standard.")
        // XCTAssertGreaterThanOrEqual(standard.count, minimal.count,
        //     ".standard must expose at least as many metrics as .minimal.")
    }
}
