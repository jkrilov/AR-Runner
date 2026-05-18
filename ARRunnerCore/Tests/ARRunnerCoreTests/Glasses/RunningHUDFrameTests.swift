// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Pure-function tests for the v0.3 raw-text running HUD (time / distance /
/// pace). The BLE-side write path is covered by hardware bench-validation —
/// these tests pin the encoder + payload + push-policy contracts so the
/// frame builder can't silently regress on its own.
final class RunningHUDFrameTests: XCTestCase {
    // MARK: - Payload formatting

    func test_payload_useSharedPR41Formatters() {
        // 1h2m5s elapsed, 2.34 mi, ~8:30/mi (sanity-check the wiring;
        // formatting precision is already covered in
        // RunMetricFormattingTests).
        let elapsed: TimeInterval = 3725
        let distance = 2.34 * RunMetricFormatting.metersPerMile
        let payload = RunningHUDFrame.payload(elapsedSeconds: elapsed, distanceMeters: distance)
        XCTAssertEqual(payload.time, "1:02:05")
        XCTAssertEqual(payload.distance, "2.34 mi")
        XCTAssertEqual(payload.pace, "26:32/mi") // 3725 / 2.34 ≈ 1591.88 → rounds to 26:32
    }

    func test_payload_subHourElapsedRendersMMSS() {
        let payload = RunningHUDFrame.payload(
            elapsedSeconds: 65,
            distanceMeters: 0.2 * RunMetricFormatting.metersPerMile
        )
        XCTAssertEqual(payload.time, "1:05")
    }

    func test_payload_zeroDistanceHoldsPaceAtPlaceholder() {
        // Joe's spec: pace text is "--:--/mi" when distance < 0.01 mi.
        // Delegates to RunMetricFormatting.formatAveragePacePerMile which
        // already guards the threshold; this test pins the contract from
        // the HUD's POV.
        let payload = RunningHUDFrame.payload(elapsedSeconds: 10, distanceMeters: 0)
        XCTAssertEqual(payload.distance, "0.00 mi")
        XCTAssertEqual(payload.pace, "--:--/mi")
    }

    func test_payload_distanceBelowThresholdHoldsPace() {
        // 8 m (< 16 m / 0.01 mi threshold) → pace still placeholder.
        let payload = RunningHUDFrame.payload(elapsedSeconds: 30, distanceMeters: 8)
        XCTAssertEqual(payload.pace, "--:--/mi")
    }

    func test_formatElapsed_clampsNegativeAndNaN() {
        XCTAssertEqual(RunningHUDFrame.formatElapsed(-10), "0:00")
        XCTAssertEqual(RunningHUDFrame.formatElapsed(.nan), "0:00")
        XCTAssertEqual(RunningHUDFrame.formatElapsed(.infinity), "0:00")
    }

    func test_formatElapsed_roundsToNearestSecond() {
        XCTAssertEqual(RunningHUDFrame.formatElapsed(59.4), "0:59")
        XCTAssertEqual(RunningHUDFrame.formatElapsed(59.6), "1:00")
        XCTAssertEqual(RunningHUDFrame.formatElapsed(3599.6), "1:00:00")
    }

    // MARK: - Frame sequence

    func test_frames_startWithClearThenThreeTxt() {
        let payload = RunningHUDFrame.Payload(time: "12:34", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        XCTAssertEqual(frames.count, 4, "v1 HUD = clear + 3 lines")

        // 0: clear command, exact byte sequence pinned in
        // ActiveLookCommandTests already, but re-verify here so a future
        // re-ordering of `frames(for:)` is caught.
        XCTAssertEqual(frames[0], [0xFF, 0x01, 0x00, 0x05, 0xAA])

        // 1..3: txt commands (cmdID 0x37) with the payload strings
        // appearing verbatim in the UTF-8 region.
        for (i, expected) in [payload.time, payload.distance, payload.pace].enumerated() {
            let frame = frames[i + 1]
            XCTAssertEqual(frame.first, 0xFF)
            XCTAssertEqual(frame.last, 0xAA)
            XCTAssertEqual(frame[1], ActiveLookCommand.ID.textUpdate.rawValue,
                           "frame \(i + 1) must be a txt (0x37) command")
            // Last byte before the trailing 0xAA is the null terminator.
            XCTAssertEqual(frame[frame.count - 2], 0x00)
            // UTF-8 bytes appear before the null+footer.
            let payloadBytes = Array(expected.utf8)
            let needleEnd = frame.count - 2 // exclusive
            let needleStart = needleEnd - payloadBytes.count
            XCTAssertEqual(Array(frame[needleStart..<needleEnd]), payloadBytes)
        }
    }

    func test_frames_textPayloadGeometryMatchesEngo2Layout() {
        let payload = RunningHUDFrame.Payload(time: "12:34", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        // x(i16 BE) | y(i16 BE) | rotation | font | color | bytes | 0x00
        // starts at index 4 (0xFF, cmd, fmt, len).
        // For our defaults: x=20, rotation=4, fontSize=3, color=15.
        let expectedY: [Int16] = [
            RunningHUDFrame.Layout.timeY,
            RunningHUDFrame.Layout.distanceY,
            RunningHUDFrame.Layout.paceY
        ]
        for i in 0..<3 {
            let frame = frames[i + 1]
            // x: big-endian 0x00 0x14 (20)
            XCTAssertEqual(frame[4], 0x00)
            XCTAssertEqual(frame[5], 0x14)
            // y: big-endian 16-bit signed
            let y = Int16(bitPattern: (UInt16(frame[6]) << 8) | UInt16(frame[7]))
            XCTAssertEqual(y, expectedY[i])
            // rotation, font, color
            XCTAssertEqual(frame[8],  RunningHUDFrame.Layout.rotation)
            XCTAssertEqual(frame[9],  RunningHUDFrame.Layout.fontSize)
            XCTAssertEqual(frame[10], RunningHUDFrame.Layout.color)
        }
    }

    func test_summaryFrames_replaceTopLineWithCompleteBanner() {
        let payload = RunningHUDFrame.Payload(time: "12:34", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.summaryFrames(for: payload)
        XCTAssertEqual(frames.count, 4)
        // First txt frame's string region carries "Workout Complete".
        let topLine = frames[1]
        let banner = Array("Workout Complete".utf8)
        let needleEnd = topLine.count - 2 // exclusive, before 0x00 + 0xAA
        let needleStart = needleEnd - banner.count
        XCTAssertEqual(Array(topLine[needleStart..<needleEnd]), banner)
    }

    func test_layoutCoordinates_fitWithinEngo2Panel() {
        // Sanity guard for any future tuning — keep the three baselines
        // inside the 304×256 panel so we never silently push text off-screen.
        XCTAssertLessThan(RunningHUDFrame.Layout.timeY,     RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.distanceY, RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.paceY,     RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.leftMargin, RunningHUDFrame.Layout.screenWidth)
    }
}

/// Push-policy contract: 1Hz minimum + change-detection. Mirrors the gate
/// `WorkoutViewModel.pushHUDFrameIfConnected` relies on so a flapping
/// elapsed ticker can't saturate the BLE link.
final class RunningHUDPushPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let p = RunningHUDFrame.Payload(time: "1:00", distance: "0.10 mi", pace: "10:00/mi")

    func test_firstSendIsAlwaysAllowed() {
        var policy = RunningHUDPushPolicy()
        XCTAssertTrue(policy.shouldSend(p, now: t0))
    }

    func test_identicalPayloadInsideWindowIsDropped() {
        var policy = RunningHUDPushPolicy()
        XCTAssertTrue(policy.shouldSend(p, now: t0))
        XCTAssertFalse(policy.shouldSend(p, now: t0.addingTimeInterval(0.5)))
        XCTAssertFalse(policy.shouldSend(p, now: t0.addingTimeInterval(0.999)))
    }

    func test_identicalPayloadAtOrAfterWindowPasses() {
        var policy = RunningHUDPushPolicy()
        XCTAssertTrue(policy.shouldSend(p, now: t0))
        XCTAssertTrue(policy.shouldSend(p, now: t0.addingTimeInterval(1.0)))
    }

    func test_changedPayloadBypassesWindow() {
        // Pace flipping from "--:--/mi" to a real number must reach the
        // glasses immediately — that's the moment the user crosses the
        // 0.01 mi threshold and the HUD comes alive.
        var policy = RunningHUDPushPolicy()
        XCTAssertTrue(policy.shouldSend(p, now: t0))
        let p2 = RunningHUDFrame.Payload(time: "1:01", distance: "0.11 mi", pace: "9:30/mi")
        XCTAssertTrue(policy.shouldSend(p2, now: t0.addingTimeInterval(0.5)))
    }

    func test_resetReleasesGate() {
        var policy = RunningHUDPushPolicy()
        _ = policy.shouldSend(p, now: t0)
        policy.reset()
        // First send after reset always passes, even with the same payload.
        XCTAssertTrue(policy.shouldSend(p, now: t0.addingTimeInterval(0.1)))
    }

    func test_defaultMinimumIntervalMatchesHUDFieldThrottle() {
        XCTAssertEqual(RunningHUDPushPolicy.defaultMinimumInterval,
                       HUDFieldThrottle.defaultMinimumInterval)
    }
}

/// Coverage for the new `ActiveLookCommand.text(...)` encoder — pins the
/// wire format so it can't silently drift from the ActiveLook API spec.
final class ActiveLookTextCommandTests: XCTestCase {
    func test_textFrame_layoutMatchesActiveLookSpec() {
        // x=20, y=40, rotation=4, font=3, color=15, string="HI"
        let frame = ActiveLookCommand.text(
            x: 20, y: 40, rotation: 4, fontSize: 3, color: 15, string: "HI"
        )
        // 0xFF | cmd 0x37 | format 0x00 | length | x_hi x_lo | y_hi y_lo | rot | font | color | 'H' 'I' | 0x00 | 0xAA
        // Total = 1+1+1+1+ 2+2+1+1+1 +2+1 +1 = 15 bytes.
        XCTAssertEqual(frame.count, 15)
        XCTAssertEqual(frame, [
            0xFF,
            0x37,
            0x00,
            UInt8(15),
            0x00, 0x14,   // x=20 BE
            0x00, 0x28,   // y=40 BE
            0x04,         // rotation
            0x03,         // font
            0x0F,         // color = 15
            0x48, 0x49,   // "HI"
            0x00,         // null terminator
            0xAA
        ])
    }

    func test_textFrame_negativeYEncodesAsTwosComplement() {
        // ActiveLook coordinates are signed; verify -1 → 0xFF 0xFF.
        let frame = ActiveLookCommand.text(x: 0, y: -1, string: "")
        XCTAssertEqual(frame[6], 0xFF) // y_hi
        XCTAssertEqual(frame[7], 0xFF) // y_lo
    }

    func test_textFrame_emptyStringStillCarriesNullTerminator() {
        let frame = ActiveLookCommand.text(x: 0, y: 0, string: "")
        // last byte is footer 0xAA, second-to-last is the null terminator.
        XCTAssertEqual(frame[frame.count - 1], 0xAA)
        XCTAssertEqual(frame[frame.count - 2], 0x00)
    }
}
