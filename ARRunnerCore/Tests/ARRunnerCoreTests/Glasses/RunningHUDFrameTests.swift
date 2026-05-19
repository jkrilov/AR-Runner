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

        // 0: clear command (now 6 bytes with the queryID byte at index 4).
        XCTAssertEqual(frames[0], [0xFF, 0x01, 0x01, 0x06, 0x00, 0xAA])

        // 1..3: txt commands (cmdID 0x37) with the payload strings
        // appearing verbatim in the UTF-8 region.
        for (i, expected) in [payload.time, payload.distance, payload.pace].enumerated() {
            let frame = frames[i + 1]
            XCTAssertEqual(frame.first, 0xFF)
            XCTAssertEqual(frame.last, 0xAA)
            XCTAssertEqual(frame[1], ActiveLookCommand.ID.textUpdate.rawValue,
                           "frame \(i + 1) must be a txt (0x37) command")
            XCTAssertEqual(frame[2], 0x01, "frame \(i + 1) must include 1-byte queryID")
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
        // 0xFF | cmd | fmt | len | queryID | x(i16 BE) | y(i16 BE) | rotation | font | color | bytes | 0x00 | 0xAA
        // payload starts at index 5 (after the 1-byte queryID at index 4).
        let expectedY: [Int16] = [
            RunningHUDFrame.Layout.timeY,
            RunningHUDFrame.Layout.distanceY,
            RunningHUDFrame.Layout.paceY
        ]
        for i in 0..<3 {
            let frame = frames[i + 1]
            XCTAssertEqual(frame[4], 0x00) // queryID placeholder
            // x: big-endian 0x00 0x14 (20)
            XCTAssertEqual(frame[5], 0x00)
            XCTAssertEqual(frame[6], 0x14)
            // y: big-endian 16-bit signed
            let y = Int16(bitPattern: (UInt16(frame[7]) << 8) | UInt16(frame[8]))
            XCTAssertEqual(y, expectedY[i])
            // rotation, font, color
            XCTAssertEqual(frame[9],  RunningHUDFrame.Layout.rotation)
            XCTAssertEqual(frame[10], RunningHUDFrame.Layout.fontSize)
            XCTAssertEqual(frame[11], RunningHUDFrame.Layout.color)
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

    /// Dedicated explicit guard that the first byte of the connect
    /// sequence is the cfgSet command. This is the rc8 fix — if a future
    /// refactor accidentally drops cfgSet, the screen will go blank on
    /// real hardware. This test catches that in CI.
    func test_connectFrames_startsWithCfgSetForALooK() {
        let frames = RunningHUDFrame.connectFrames()
        XCTAssertFalse(frames.isEmpty)
        let first = frames[0]
        // cmdID byte at index 1 must be 0xD2 (cfgSet).
        XCTAssertEqual(first[1], 0xD2)
        XCTAssertEqual(first[1], ActiveLookCommand.ID.cfgSet.rawValue)
        // Config name "ALooK" appears in the payload region (after the
        // 5-byte header: 0xFF | cmd | format | len | queryID).
        let nameBytes = Array("ALooK".utf8)
        let payloadStart = 5
        XCTAssertEqual(Array(first[payloadStart..<(payloadStart + nameBytes.count)]), nameBytes)
    }

    // MARK: - rc4 regression: power-on prefix

    /// Engo 2 boots into a low-power display state after a fresh BLE
    /// link-up. PR #49 cleared the firmware splash without first sending
    /// `power(on:true)` (cmdID 0x00), which left the screen blank on
    /// connect and during the run. Every "first frame of a connection"
    /// path must lead with the power-on command.
    func test_connectFrames_leadWithCfgSetThenPowerOnBeforeAnyDraw() {
        // rc8: fonts 1–5 live in the ALooK configuration stored in glasses'
        // flash, NOT baked into firmware. Per ActiveLook-Visual-Assets repo,
        // `cfgSet("ALooK")` must precede any txt command referencing those
        // fonts — otherwise font index 3 doesn't exist in the active
        // namespace and the screen stays blank.
        let frames = RunningHUDFrame.connectFrames()
        XCTAssertGreaterThanOrEqual(frames.count, 3)
        // Frame 0: cfgSet("ALooK") — cmdID 0xD2.
        XCTAssertEqual(frames[0][1], ActiveLookCommand.ID.cfgSet.rawValue)
        // Frame 1: power(on:true) — cmdID 0x00, format 0x01, len 7,
        // queryID placeholder 0x00, payload [0x01].
        XCTAssertEqual(frames[1], [0xFF, 0x00, 0x01, 0x07, 0x00, 0x01, 0xAA])
        // Frame 2: clear (cmdID 0x01).
        XCTAssertEqual(frames[2][1], ActiveLookCommand.ID.clear.rawValue)
    }

    func test_connectFrames_paintBannerSoUserSeesPairingSucceeded() {
        let frames = RunningHUDFrame.connectFrames(banner: "AR-Runner Ready")
        // rc8: cfgSet + power + clear + 2× txt = 5 frames.
        XCTAssertEqual(frames.count, 5)
        // Frame index 3: txt with the banner string in its UTF-8 region.
        let bannerFrame = frames[3]
        XCTAssertEqual(bannerFrame[1], ActiveLookCommand.ID.textUpdate.rawValue)
        let needle = Array("AR-Runner Ready".utf8)
        let needleEnd = bannerFrame.count - 2 // exclusive (skip 0x00 + 0xAA)
        let needleStart = needleEnd - needle.count
        XCTAssertEqual(Array(bannerFrame[needleStart..<needleEnd]), needle)
    }

    func test_framesWithPowerOn_prependsCfgSetAndPowerOnToPlainFrames() {
        let payload = RunningHUDFrame.Payload(time: "0:00", distance: "0.00 mi", pace: "--:--/mi")
        let plain = RunningHUDFrame.frames(for: payload)
        let withPower = RunningHUDFrame.framesWithPowerOn(for: payload)
        // rc8: cfgSet + power prepended (2 extra frames, not 1).
        XCTAssertEqual(withPower.count, plain.count + 2)
        // Frame 0: cfgSet("ALooK") — activates ALooK font config.
        XCTAssertEqual(withPower[0][1], ActiveLookCommand.ID.cfgSet.rawValue)
        // Frame 1: power(on:true).
        XCTAssertEqual(withPower[1], [0xFF, 0x00, 0x01, 0x07, 0x00, 0x01, 0xAA])
        // Tail is identical to plain frames(for:).
        XCTAssertEqual(Array(withPower.dropFirst(2)), plain)
    }

    func test_summaryFramesWithPowerOn_prependsPowerOnToSummaryFrames() {
        let payload = RunningHUDFrame.Payload(time: "12:34", distance: "2.34 mi", pace: "8:30/mi")
        let plain = RunningHUDFrame.summaryFrames(for: payload)
        let withPower = RunningHUDFrame.summaryFramesWithPowerOn(for: payload)
        XCTAssertEqual(withPower.count, plain.count + 1)
        XCTAssertEqual(withPower[0], [0xFF, 0x00, 0x01, 0x07, 0x00, 0x01, 0xAA])
        XCTAssertEqual(Array(withPower.dropFirst()), plain)
    }

    /// Belt-and-braces test that would have caught the rc4 regression: a
    /// fresh `RunningHUDPushPolicy` must allow the very first send through
    /// without waiting out the 1Hz throttle window. If the throttle ever
    /// gets a "lastSentAt initialized to now" bug, the first workout-start
    /// frame would wait a full second before reaching the glasses.
    func test_pushPolicy_firstSendAtT0PassesImmediatelyNotAfter1Second() {
        var policy = RunningHUDPushPolicy()
        let p = RunningHUDFrame.Payload(time: "0:00", distance: "0.00 mi", pace: "--:--/mi")
        // No prior send → first call must pass at t=0, not require Δt ≥ 1s.
        XCTAssertTrue(policy.shouldSend(p, now: Date(timeIntervalSince1970: 0)))
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
        // 0xFF | cmd 0x37 | format 0x01 | length | queryID 0x00 | x_hi x_lo | y_hi y_lo | rot | font | color | 'H' 'I' | 0x00 | 0xAA
        // Total = 1+1+1+1+ 1 +2+2+1+1+1 +2 +1 +1 = 16 bytes.
        XCTAssertEqual(frame.count, 16)
        XCTAssertEqual(frame, [
            0xFF,
            0x37,
            0x01,         // format: 1-byte queryID
            UInt8(16),
            0x00,         // queryID placeholder (adapter stamps a real one)
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
        // With the 1-byte queryID prefix, y now sits at indices 7..8.
        let frame = ActiveLookCommand.text(x: 0, y: -1, string: "")
        XCTAssertEqual(frame[7], 0xFF) // y_hi
        XCTAssertEqual(frame[8], 0xFF) // y_lo
    }

    func test_textFrame_emptyStringStillCarriesNullTerminator() {
        let frame = ActiveLookCommand.text(x: 0, y: 0, string: "")
        // last byte is footer 0xAA, second-to-last is the null terminator.
        XCTAssertEqual(frame[frame.count - 1], 0xAA)
        XCTAssertEqual(frame[frame.count - 2], 0x00)
    }
}
