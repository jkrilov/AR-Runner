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
        let payload = RunningHUDFrame.payload(elapsedSeconds: elapsed, distanceMeters: distance, heartRate: 165)
        XCTAssertEqual(payload.time, "1:02:05")
        XCTAssertEqual(payload.distance, "2.34 mi")
        XCTAssertEqual(payload.pace, "26:32/mi") // 3725 / 2.34 ≈ 1591.88 → rounds to 26:32
        XCTAssertEqual(payload.heartRate, "165 bpm")
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

    // MARK: - HR formatter (rc14)

    /// rc14: HR pulled forward from v0.4.0-rc1. HK substrate emits BPM
    /// as Double; HUD must render "165 bpm" matching the wrist
    /// (WorkoutView.swift:169 → `"\(Int($0)) bpm"`). nil/sub-30/NaN/inf
    /// → "-- bpm" placeholder (pre-first-sample, sensor dropout).
    func test_formatHeartRate_nilRendersPlaceholder() {
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(nil), "-- bpm")
    }
    func test_formatHeartRate_normalReadingRendersBpm() {
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(165), "165 bpm")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(180.4), "180 bpm")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(180.6), "181 bpm")
    }
    func test_formatHeartRate_sensorDropoutHidesAsPlaceholder() {
        // Sub-30 BPM in a running workout = dropped contact. Don't
        // alarm the user mid-run with "12 bpm".
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(0), "-- bpm")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(12), "-- bpm")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(29.9), "-- bpm")
    }
    func test_formatHeartRate_nonFinitePlaceholder() {
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(.nan), "-- bpm")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(.infinity), "-- bpm")
    }
    func test_formatHeartRate_doesNotCapHighEnd() {
        // If HK ever reports 220 bpm during a max effort, we want to
        // see it — don't silently floor.
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(220), "220 bpm")
    }
    func test_payload_defaultsHRtoPlaceholderWhenAbsent() {
        let payload = RunningHUDFrame.payload(elapsedSeconds: 60, distanceMeters: 200)
        XCTAssertEqual(payload.heartRate, "-- bpm")
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

    func test_frames_startWithHoldFlushThenClearThenFourTxtThenFlush() {
        // rc14: live HUD expanded from 3 fields (time/distance/pace) to
        // 4 (time/HR/distance/pace) per Joe's bench feedback. HR pulled
        // forward from v0.4.0-rc1.
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165 bpm", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        XCTAssertEqual(frames.count, 7, "rc14 HUD = holdFlush(hold) + clear + 4 lines + holdFlush(flush)")

        // 0: holdFlush(hold:true) — cmdID 0x39, payload [0x00].
        XCTAssertEqual(frames[0], [0xFF, 0x39, 0x01, 0x07, 0x00, 0x00, 0xAA])

        // 1: clear command (6 bytes with the queryID byte at index 4).
        XCTAssertEqual(frames[1], [0xFF, 0x01, 0x01, 0x06, 0x00, 0xAA])

        // 2..5: txt commands (cmdID 0x37) with the payload strings
        // appearing verbatim in the UTF-8 region.
        let expected = [payload.time, payload.heartRate, payload.distance, payload.pace]
        for (i, str) in expected.enumerated() {
            let frame = frames[i + 2]
            XCTAssertEqual(frame.first, 0xFF)
            XCTAssertEqual(frame.last, 0xAA)
            XCTAssertEqual(frame[1], ActiveLookCommand.ID.textUpdate.rawValue,
                           "frame \(i + 2) must be a txt (0x37) command")
            XCTAssertEqual(frame[2], 0x01, "frame \(i + 2) must include 1-byte queryID")
            XCTAssertEqual(frame[frame.count - 2], 0x00)
            let payloadBytes = Array(str.utf8)
            let needleEnd = frame.count - 2
            let needleStart = needleEnd - payloadBytes.count
            XCTAssertEqual(Array(frame[needleStart..<needleEnd]), payloadBytes)
        }

        // 6: holdFlush(hold:false) — cmdID 0x39, payload [0x01].
        XCTAssertEqual(frames[6], [0xFF, 0x39, 0x01, 0x07, 0x00, 0x01, 0xAA])
    }

    func test_frames_textPayloadGeometryMatchesEngo2Layout() {
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165 bpm", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        // rc14: 4-field live HUD geometry. Order: time, HR, distance, pace.
        let expectedY: [Int16] = [
            RunningHUDFrame.Layout.liveTimeY,
            RunningHUDFrame.Layout.liveHRY,
            RunningHUDFrame.Layout.liveDistanceY,
            RunningHUDFrame.Layout.livePaceY
        ]
        for i in 0..<4 {
            let frame = frames[i + 2]
            XCTAssertEqual(frame[4], 0x00) // queryID placeholder
            // x: big-endian 0x01 0x1C (284) — rc12 lens-flip-corrected anchor
            XCTAssertEqual(frame[5], 0x01)
            XCTAssertEqual(frame[6], 0x1C)
            // y: big-endian 16-bit signed
            let y = Int16(bitPattern: (UInt16(frame[7]) << 8) | UInt16(frame[8]))
            XCTAssertEqual(y, expectedY[i])
            // rotation, font, color
            XCTAssertEqual(frame[9],  RunningHUDFrame.Layout.rotation)
            XCTAssertEqual(frame[10], RunningHUDFrame.Layout.fontSize)
            XCTAssertEqual(frame[11], RunningHUDFrame.Layout.color)
        }
    }

    /// rc9: per-tick HUD updates must be wrapped in holdFlush so the
    /// `clear` + 3×`txt` sequence commits atomically to the display.
    /// Without the wrap the wearer sees a brief blank between `clear` and
    /// the first `txt` (Joe's "flashes every second" rc8 report).
    /// Per ActiveLook spec §4.6 + hud-api-spec-report.md §"Fix 3".
    func test_framesFor_wrapsInHoldFlush() {
        let payload = RunningHUDFrame.Payload(time: "0:00", heartRate: "-- bpm", distance: "0.00 mi", pace: "--:--/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        XCTAssertGreaterThanOrEqual(frames.count, 2)
        // First frame: holdFlush with action=0 (HOLD).
        XCTAssertEqual(frames.first?[1], ActiveLookCommand.ID.holdFlush.rawValue)
        XCTAssertEqual(frames.first?[5], 0x00, "first holdFlush payload byte must be 0x00 (HOLD)")
        // Last frame: holdFlush with action=1 (FLUSH).
        XCTAssertEqual(frames.last?[1], ActiveLookCommand.ID.holdFlush.rawValue)
        XCTAssertEqual(frames.last?[5], 0x01, "trailing holdFlush payload byte must be 0x01 (FLUSH)")
    }

    /// rc9: holdFlush wrap is for per-tick updates only. The connect
    /// banner is a one-shot draw where the user only sees the final state,
    /// so flicker is acceptable AND adding holdFlush around the
    /// cfgSet → power → clear → 2×txt sequence would conflate concerns.
    /// Pin the contract so a future refactor doesn't accidentally wrap it.
    func test_connectFrames_doesNotUseHoldFlush() {
        let frames = RunningHUDFrame.connectFrames()
        for (i, frame) in frames.enumerated() {
            XCTAssertNotEqual(frame[1], ActiveLookCommand.ID.holdFlush.rawValue,
                              "connectFrames[\(i)] must not be a holdFlush command")
        }
    }

    /// rc9: summary frames are a one-shot draw at workout end; no wrap.
    func test_summaryFrames_doesNotUseHoldFlush() {
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165 bpm", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.summaryFrames(for: payload)
        for (i, frame) in frames.enumerated() {
            XCTAssertNotEqual(frame[1], ActiveLookCommand.ID.holdFlush.rawValue,
                              "summaryFrames[\(i)] must not be a holdFlush command")
        }
    }

    /// rc14: finish screen drops pace. Joe's directive: "Time + Distance
    /// ONLY (final stats)". Layout: clear + "Workout Complete" + time +
    /// distance = 4 frames. Top line is the banner, then time, then
    /// distance — no pace, no HR.
    func test_summaryFrames_renderTimeAndDistanceOnlyPerFinishScreenDirective() {
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165 bpm", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.summaryFrames(for: payload)
        XCTAssertEqual(frames.count, 4, "summary = clear + banner + time + distance (rc14)")
        // frames[1] = banner, frames[2] = time, frames[3] = distance.
        // Banner at top (timeY), time at middle (distanceY), distance at bottom (paceY).
        let bannerStr = stringPayload(from: frames[1])
        let timeStr   = stringPayload(from: frames[2])
        let distStr   = stringPayload(from: frames[3])
        XCTAssertEqual(bannerStr, "Workout Complete")
        XCTAssertEqual(timeStr,   payload.time)
        XCTAssertEqual(distStr,   payload.distance)
        // Pace must NOT appear in any frame's UTF-8 region.
        for frame in frames where frame[1] == ActiveLookCommand.ID.textUpdate.rawValue {
            let str = stringPayload(from: frame)
            XCTAssertNotEqual(str, payload.pace, "summary must not render pace (rc14 directive)")
            XCTAssertNotEqual(str, payload.heartRate, "summary must not render HR (rc14 directive)")
        }
    }

    func test_summaryFrames_replaceTopLineWithCompleteBanner() {
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165 bpm", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.summaryFrames(for: payload)
        XCTAssertEqual(frames.count, 4)
        // First txt frame's string region carries "Workout Complete".
        let topLine = frames[1]
        let banner = Array("Workout Complete".utf8)
        let needleEnd = topLine.count - 2 // exclusive, before 0x00 + 0xAA
        let needleStart = needleEnd - banner.count
        XCTAssertEqual(Array(topLine[needleStart..<needleEnd]), banner)
    }

    /// Extract the UTF-8 string payload from a txt (0x37) frame.
    private func stringPayload(from frame: [UInt8]) -> String {
        // Layout: 0xFF | cmd | fmt | len | queryID | x(2) | y(2) | rot | font | color | bytes | 0x00 | 0xAA
        // → string starts at index 12, ends before the 0x00 (index count-2).
        let start = 12
        let end = frame.count - 2
        guard end > start else { return "" }
        return String(bytes: frame[start..<end], encoding: .utf8) ?? ""
    }

    func test_layoutCoordinates_fitWithinEngo2Panel() {
        // Sanity guard for any future tuning — keep all baselines inside
        // the 304×256 panel so we never silently push text off-screen.
        XCTAssertLessThan(RunningHUDFrame.Layout.timeY,     RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.distanceY, RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.paceY,     RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.leftMargin, RunningHUDFrame.Layout.screenWidth)
        // rc14: 4-field live HUD coordinates must also fit.
        XCTAssertLessThan(RunningHUDFrame.Layout.liveTimeY,     RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.liveHRY,       RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.liveDistanceY, RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.livePaceY,     RunningHUDFrame.Layout.screenHeight)
        XCTAssertGreaterThanOrEqual(RunningHUDFrame.Layout.livePaceY, 0,
                                    "lowest line top must stay in-bounds")
    }

    /// rc14: lens-flip arithmetic for the 4-field live HUD must match
    /// `y_fb = 255 − T − 49` (font 3 = 49 px tall) for the same
    /// 55-px-spaced wearer-space anchors (T = 20, 75, 130, 185).
    /// Pinned so a future Y retune can't silently drift off-screen.
    func test_liveHUDYCoords_followLensFlipFormula() {
        XCTAssertEqual(RunningHUDFrame.Layout.liveTimeY,     206 - 20)
        XCTAssertEqual(RunningHUDFrame.Layout.liveHRY,       206 - 75)
        XCTAssertEqual(RunningHUDFrame.Layout.liveDistanceY, 206 - 130)
        XCTAssertEqual(RunningHUDFrame.Layout.livePaceY,     206 - 185)
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

    /// rc14: splash line 1 trimmed from "AR-Runner Ready" → "AR-Runner"
    /// per Joe's bench feedback ("Can we change the first line to just
    /// 'AR-Runner'?"). Line 2 ("Start a run") stays as-is. The shorter
    /// 9-char string trivially fits at font 2; the rc13 font-fit
    /// guard (`test_connectFrames_useShorterFontSoFullBannerFits`)
    /// continues to enforce the font choice independent of this.
    func test_connectFrames_defaultBannerIsTrimmedToARRunner() {
        let frames = RunningHUDFrame.connectFrames()
        XCTAssertEqual(frames.count, 5)
        let bannerFrame = frames[3]
        let str = String(bytes: bannerFrame[12..<(bannerFrame.count - 2)], encoding: .utf8)
        XCTAssertEqual(str, "AR-Runner",
                       "rc14 trimmed splash line 1 to 'AR-Runner' (was 'AR-Runner Ready')")
        // Line 2 still says "Start a run".
        let line2Frame = frames[4]
        let line2 = String(bytes: line2Frame[12..<(line2Frame.count - 2)], encoding: .utf8)
        XCTAssertEqual(line2, "Start a run")
    }

    func test_connectFrames_paintBannerSoUserSeesPairingSucceeded() {
        // Custom banner override still works (callers can override the
        // default if they want a different post-pair message).
        let frames = RunningHUDFrame.connectFrames(banner: "Hello")
        XCTAssertEqual(frames.count, 5)
        let bannerFrame = frames[3]
        XCTAssertEqual(bannerFrame[1], ActiveLookCommand.ID.textUpdate.rawValue)
        let needle = Array("Hello".utf8)
        let needleEnd = bannerFrame.count - 2
        let needleStart = needleEnd - needle.count
        XCTAssertEqual(Array(bannerFrame[needleStart..<needleEnd]), needle)
    }

    /// rc13 Bug A (Joe's bench: "last letter on each line is cutoff"):
    /// splash banner MUST render at font 2 (38 px tall, ~18 px wide), not
    /// font 3 (49 px tall, ~28 px wide). The default banner
    /// "AR-Runner Ready" is 15 chars; at font 3 ≈ 420 px which extends
    /// from `x_fb = 284` to `x_fb ≈ −136` and gets silently clipped per
    /// spec §5.5.6. At font 2 it spans ~270 px, fully inside `0 ≤ x_fb`.
    /// Per-tick run-HUD strings ("0:00", "0.00 mi", "8:30/mi") stay on
    /// font 3 — short enough to fit.
    func test_connectFrames_useShorterFontSoFullBannerFits() {
        let frames = RunningHUDFrame.connectFrames(banner: "AR-Runner Ready")
        // Frames 3 and 4 are the two banner txt frames; both must use
        // bannerFontSize (2), at bannerLine1Y / bannerLine2Y respectively.
        // txt layout: 0xFF | cmd | fmt | len | queryID | x_hi x_lo |
        //             y_hi y_lo | rot | font | color | bytes | 0x00 | 0xAA
        // → font byte is at index 10.
        XCTAssertEqual(frames[3][10], RunningHUDFrame.Layout.bannerFontSize,
                       "banner line 1 must render at bannerFontSize, not fontSize")
        XCTAssertEqual(frames[4][10], RunningHUDFrame.Layout.bannerFontSize,
                       "banner line 2 must render at bannerFontSize, not fontSize")
        XCTAssertEqual(RunningHUDFrame.Layout.bannerFontSize, 2,
                       "bannerFontSize must be 2 (38 px) to fit 15-char banner at leftMargin=284")
        // Y coords must use the banner-specific values, NOT the run-HUD
        // ones (which assume font 3's 49 px height).
        let line1Y = Int16(bitPattern: (UInt16(frames[3][7]) << 8) | UInt16(frames[3][8]))
        let line2Y = Int16(bitPattern: (UInt16(frames[4][7]) << 8) | UInt16(frames[4][8]))
        XCTAssertEqual(line1Y, RunningHUDFrame.Layout.bannerLine1Y)
        XCTAssertEqual(line2Y, RunningHUDFrame.Layout.bannerLine2Y)
    }

    /// Pin the lens-flip arithmetic for the banner so a future font/Y
    /// retune can't silently drift off-screen. With font 2 (38 px tall),
    /// `bannerLine1Y` must equal `255 − T − 38` for the same wearer-y
    /// target T = 40 that the run HUD's `timeY` uses with font 3.
    func test_bannerYCoords_compensateForShorterFontHeight() {
        // Font 2 is 38 px tall per spec §5.9; line 1 targets wearer-y=40,
        // line 2 targets wearer-y=120 (mirroring run-HUD `timeY`/`distanceY`).
        XCTAssertEqual(RunningHUDFrame.Layout.bannerLine1Y, 255 - 40 - 38)
        XCTAssertEqual(RunningHUDFrame.Layout.bannerLine2Y, 255 - 120 - 38)
    }

    /// Run-HUD font (fontSize) must stay at 3 — short per-tick strings
    /// ("0:00", "0.00 mi", "8:30/mi") fit at font 3 and are more readable
    /// at arm's length. Only the splash drops to font 2 for the long
    /// "AR-Runner Ready" / "Start a run" banners. Guards against a future
    /// "make everything font 2" mass-edit regression.
    /// rc14: live HUD jumped from 3 → 4 txt commands.
    func test_runHUDFont_staysAtFont3() {
        XCTAssertEqual(RunningHUDFrame.Layout.fontSize, 3,
                       "run HUD must stay at font 3 for readability at arm's length")
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165 bpm", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        // frames[2..5] are the four txt commands; font byte at index 10.
        for i in 2...5 {
            XCTAssertEqual(frames[i][10], 3,
                           "run-HUD txt[\(i)] must use font 3 (was \(frames[i][10]))")
        }
    }

    func test_framesWithPowerOn_prependsCfgSetAndPowerOnToPlainFrames() {
        let payload = RunningHUDFrame.Payload(time: "0:00", heartRate: "-- bpm", distance: "0.00 mi", pace: "--:--/mi")
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
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165 bpm", distance: "2.34 mi", pace: "8:30/mi")
        let plain = RunningHUDFrame.summaryFrames(for: payload)
        let withPower = RunningHUDFrame.summaryFramesWithPowerOn(for: payload)
        XCTAssertEqual(withPower.count, plain.count + 1)
        XCTAssertEqual(withPower[0], [0xFF, 0x00, 0x01, 0x07, 0x00, 0x01, 0xAA])
        XCTAssertEqual(Array(withPower.dropFirst()), plain)
    }

    func test_pushPolicy_firstSendAtT0PassesImmediatelyNotAfter1Second() {
        var policy = RunningHUDPushPolicy()
        let p = RunningHUDFrame.Payload(time: "0:00", heartRate: "-- bpm", distance: "0.00 mi", pace: "--:--/mi")
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
