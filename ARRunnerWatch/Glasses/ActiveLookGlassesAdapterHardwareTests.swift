// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0
//
// Hardware-gated integration scaffold for the ActiveLook BLE adapter.
//
// **Compiled only when `AR_RUNNER_HARDWARE_TESTS` is set.** Default CI runs
// (Linux SPM + macOS xcodebuild + CodeQL) skip this file so the matrix stays
// green without a paired pair of glasses on the bench.
//
// To run locally on Joe's Watch SE + ActiveLook hardware once a watch test
// target is added to project.yml:
//
//     xcodebuild test \
//       -scheme ARRunnerWatch \
//       -destination 'platform=watchOS,name=Joe Watch' \
//       OTHER_SWIFT_FLAGS='-D AR_RUNNER_HARDWARE_TESTS'
//
// The test deliberately uses a long timeout: BLE scan + connect + service
// discovery on a cold radio routinely takes 8–12 seconds.

#if AR_RUNNER_HARDWARE_TESTS

import ARRunnerCore
import XCTest
@testable import ARRunnerWatch

final class ActiveLookGlassesAdapterHardwareTests: XCTestCase {
    func testConnectAndPushOneFrame() async throws {
        let adapter = ActiveLookGlassesAdapter(scanTimeout: 20)

        try await adapter.connect()
        let state = await adapter.connectionState
        XCTAssertEqual(state, .connected, "expected connected after connect()")

        try await adapter.selectLayout(id: "balanced-run")
        try await adapter.updateField(
            HUDFieldUpdate(layoutID: "balanced-run", fieldIndex: 0, value: "5:42")
        )

        try await adapter.disconnect()
        let final = await adapter.connectionState
        XCTAssertEqual(final, .disconnected)
    }
}

#endif
