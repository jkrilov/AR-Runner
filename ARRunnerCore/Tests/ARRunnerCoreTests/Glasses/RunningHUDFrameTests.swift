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
        XCTAssertEqual(payload.heartRate, "165")
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

    // MARK: - HR formatter (rc14 → rc16: dropped " bpm" suffix)

    /// rc14: HR pulled forward from v0.4.0-rc1. HK substrate emits BPM
    /// as Double.
    /// rc16: HUD renders just the digits ("165") — the new heart icon
    /// on line 1 (`heartIconID = 12`) carries the "this is BPM"
    /// semantic. Joe's rc15 bench saw the trailing "m" in "BPM"
    /// clipped on the panel's right edge; dropping the suffix is
    /// what frees those pixels.
    /// nil/sub-30/NaN/inf → "--" placeholder (pre-first-sample,
    /// sensor dropout).
    func test_formatHeartRate_nilRendersPlaceholder() {
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(nil), "--")
    }
    func test_formatHeartRate_normalReadingRendersJustDigits_rc16() {
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(165), "165")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(180.4), "180")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(180.6), "181")
    }
    func test_formatHeartRate_sensorDropoutHidesAsPlaceholder() {
        // Sub-30 BPM in a running workout = dropped contact. Don't
        // alarm the user mid-run with "12" next to the heart icon.
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(0), "--")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(12), "--")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(29.9), "--")
    }
    func test_formatHeartRate_nonFinitePlaceholder() {
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(.nan), "--")
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(.infinity), "--")
    }
    func test_formatHeartRate_doesNotCapHighEnd() {
        // If HK ever reports 220 bpm during a max effort, we want to
        // see it — don't silently floor. rc16: still no " bpm" suffix.
        XCTAssertEqual(RunningHUDFrame.formatHeartRate(220), "220")
    }
    func test_payload_defaultsHRtoPlaceholderWhenAbsent() {
        let payload = RunningHUDFrame.payload(elapsedSeconds: 60, distanceMeters: 200)
        XCTAssertEqual(payload.heartRate, "--")
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

    func test_frames_renderTimeAndHROnLine1ThenDistanceThenPace_rc16() {
        // rc16: 3-line mixed-font layout WITH preloaded ALooK icons.
        // Joe's rc15 bench feedback (verbatim): "the top line is just
        // slightly cutoff, 1 or two pixels on the 'm' in 'BPM' are
        // missing... large gap before the distance, then the pace is
        // almost completely off the screen". rc16 fixes all three at
        // once by (a) correcting Y coords for the real font-3 height
        // (64 px, not 49), (b) dropping " bpm" so HR text fits, and
        // (c) adding icons via imgDisplay (0x42).
        //
        // Frame sequence (11 frames):
        //   0  holdFlush(HOLD)
        //   1  clear
        //   2  imgDisplay(chrono)     line 1 icon
        //   3  txt(Time)              line 1 text (font 2)
        //   4  imgDisplay(heart)      line 1 right icon
        //   5  txt(HR digits)         line 1 right text (font 2)
        //   6  imgDisplay(distance)   line 2 icon
        //   7  txt(Distance)          line 2 text (font 3)
        //   8  imgDisplay(pace)       line 3 icon
        //   9  txt(Avg Pace)          line 3 text (font 3)
        //  10  holdFlush(FLUSH)
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        XCTAssertEqual(frames.count, 11,
                       "rc16 HUD = holdFlush(hold) + clear + 4×(imgDisplay+txt) + holdFlush(flush)")

        // 0: holdFlush(hold:true) — cmdID 0x39, payload [0x00].
        XCTAssertEqual(frames[0], [0xFF, 0x39, 0x01, 0x07, 0x00, 0x00, 0xAA])

        // 1: clear command (6 bytes with the queryID byte at index 4).
        XCTAssertEqual(frames[1], [0xFF, 0x01, 0x01, 0x06, 0x00, 0xAA])

        // 2,4,6,8: imgDisplay commands (cmdID 0x42). Each is 11 bytes:
        // 0xFF | 0x42 | 0x01 | 0x0B | 0x00 | id | x_hi x_lo | y_hi y_lo | 0xAA
        let imgIndices: [(Int, UInt8)] = [
            (2, RunningHUDFrame.Layout.chronoIconID),
            (4, RunningHUDFrame.Layout.heartIconID),
            (6, RunningHUDFrame.Layout.distanceIconID),
            (8, RunningHUDFrame.Layout.paceIconID)
        ]
        for (frameIdx, expectedID) in imgIndices {
            let frame = frames[frameIdx]
            XCTAssertEqual(frame[1], ActiveLookCommand.ID.imgDisplay.rawValue,
                           "frame \(frameIdx) must be an imgDisplay (0x42) command")
            XCTAssertEqual(frame[2], 0x01, "frame \(frameIdx) must include 1-byte queryID")
            XCTAssertEqual(frame[3], 0x0B, "frame \(frameIdx) length = 11 bytes (header 5 + payload 5 + footer 1)")
            XCTAssertEqual(frame[5], expectedID, "frame \(frameIdx) icon ID mismatch")
            XCTAssertEqual(frame.last, 0xAA)
        }

        // 3,5,7,9: txt commands (cmdID 0x37). Order: Time, HR, Distance, Pace.
        let textFrames = [(3, payload.time), (5, payload.heartRate),
                          (7, payload.distance), (9, payload.pace)]
        for (frameIdx, str) in textFrames {
            let frame = frames[frameIdx]
            XCTAssertEqual(frame.first, 0xFF)
            XCTAssertEqual(frame.last, 0xAA)
            XCTAssertEqual(frame[1], ActiveLookCommand.ID.textUpdate.rawValue,
                           "frame \(frameIdx) must be a txt (0x37) command")
            XCTAssertEqual(frame[2], 0x01, "frame \(frameIdx) must include 1-byte queryID")
            XCTAssertEqual(frame[frame.count - 2], 0x00)
            let payloadBytes = Array(str.utf8)
            let needleEnd = frame.count - 2
            let needleStart = needleEnd - payloadBytes.count
            XCTAssertEqual(Array(frame[needleStart..<needleEnd]), payloadBytes)
        }

        // 10: holdFlush(hold:false) — cmdID 0x39, payload [0x01].
        XCTAssertEqual(frames[10], [0xFF, 0x39, 0x01, 0x07, 0x00, 0x01, 0xAA])
    }

    func test_frames_textPayloadGeometryMatchesEngo2Layout() {
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        // rc16: mixed-font 3-line layout WITH preloaded icons. The txt
        // frames now sit at indices 3, 5, 7, 9 (icons interleaved at
        // 2, 4, 6, 8). Time anchors at `liveLeftMargin`; HR anchors
        // at `liveHRX` (right-side anchor on line 1, with the heart
        // icon between them).
        struct ExpectedTxt {
            let frameIndex: Int
            let x: Int16
            let y: Int16
            let font: UInt8
        }
        let expected: [ExpectedTxt] = [
            ExpectedTxt(frameIndex: 3, x: RunningHUDFrame.Layout.liveLeftMargin, y: RunningHUDFrame.Layout.liveLine1Y,    font: RunningHUDFrame.Layout.liveLine1Font),
            ExpectedTxt(frameIndex: 5, x: RunningHUDFrame.Layout.liveHRX,        y: RunningHUDFrame.Layout.liveLine1Y,    font: RunningHUDFrame.Layout.liveLine1Font),
            ExpectedTxt(frameIndex: 7, x: RunningHUDFrame.Layout.liveLeftMargin, y: RunningHUDFrame.Layout.liveDistanceY, font: RunningHUDFrame.Layout.fontSize),
            ExpectedTxt(frameIndex: 9, x: RunningHUDFrame.Layout.liveLeftMargin, y: RunningHUDFrame.Layout.livePaceY,     font: RunningHUDFrame.Layout.fontSize)
        ]
        for exp in expected {
            let frame = frames[exp.frameIndex]
            XCTAssertEqual(frame[4], 0x00) // queryID placeholder
            // x: big-endian Int16
            let x = Int16(bitPattern: (UInt16(frame[5]) << 8) | UInt16(frame[6]))
            XCTAssertEqual(x, exp.x, "txt[\(exp.frameIndex)] x mismatch")
            // y: big-endian Int16
            let y = Int16(bitPattern: (UInt16(frame[7]) << 8) | UInt16(frame[8]))
            XCTAssertEqual(y, exp.y, "txt[\(exp.frameIndex)] y mismatch")
            // rotation, font, color
            XCTAssertEqual(frame[9],  RunningHUDFrame.Layout.rotation)
            XCTAssertEqual(frame[10], exp.font, "txt[\(exp.frameIndex)] font mismatch")
            XCTAssertEqual(frame[11], RunningHUDFrame.Layout.color)
        }
    }

    /// rc16: pin the imgDisplay icon coordinates AND IDs against the
    /// preloaded ALooK flash IDs. If a future tuning shifts a constant
    /// or accidentally swaps two icon IDs, this catches it before
    /// reaching the bench.
    func test_frames_iconPayloadGeometryMatchesPreloadedALooK_rc16() {
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        struct ExpectedImg {
            let frameIndex: Int
            let id: UInt8
            let x: UInt16
            let y: UInt16
        }
        let expected: [ExpectedImg] = [
            ExpectedImg(frameIndex: 2, id: RunningHUDFrame.Layout.chronoIconID,
                        x: RunningHUDFrame.Layout.chronoIconX,   y: RunningHUDFrame.Layout.chronoIconY),
            ExpectedImg(frameIndex: 4, id: RunningHUDFrame.Layout.heartIconID,
                        x: RunningHUDFrame.Layout.heartIconX,    y: RunningHUDFrame.Layout.heartIconY),
            ExpectedImg(frameIndex: 6, id: RunningHUDFrame.Layout.distanceIconID,
                        x: RunningHUDFrame.Layout.distanceIconX, y: RunningHUDFrame.Layout.distanceIconY),
            ExpectedImg(frameIndex: 8, id: RunningHUDFrame.Layout.paceIconID,
                        x: RunningHUDFrame.Layout.paceIconX,     y: RunningHUDFrame.Layout.paceIconY)
        ]
        for exp in expected {
            let frame = frames[exp.frameIndex]
            XCTAssertEqual(frame[1], ActiveLookCommand.ID.imgDisplay.rawValue)
            XCTAssertEqual(frame[4], 0x00) // queryID placeholder
            XCTAssertEqual(frame[5], exp.id, "img[\(exp.frameIndex)] id mismatch")
            let x = (UInt16(frame[6]) << 8) | UInt16(frame[7])
            XCTAssertEqual(x, exp.x, "img[\(exp.frameIndex)] x mismatch")
            let y = (UInt16(frame[8]) << 8) | UInt16(frame[9])
            XCTAssertEqual(y, exp.y, "img[\(exp.frameIndex)] y mismatch")
        }
    }

    /// rc9: per-tick HUD updates must be wrapped in holdFlush so the
    /// `clear` + 3×`txt` sequence commits atomically to the display.
    /// Without the wrap the wearer sees a brief blank between `clear` and
    /// the first `txt` (Joe's "flashes every second" rc8 report).
    /// Per ActiveLook spec §4.6 + hud-api-spec-report.md §"Fix 3".
    func test_framesFor_wrapsInHoldFlush() {
        let payload = RunningHUDFrame.Payload(time: "0:00", heartRate: "--", distance: "0.00 mi", pace: "--:--/mi")
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
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
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
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
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
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
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
        XCTAssertLessThan(RunningHUDFrame.Layout.finishBannerY,   RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.finishTimeY,     RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.finishDistanceY, RunningHUDFrame.Layout.screenHeight)
        XCTAssertGreaterThanOrEqual(RunningHUDFrame.Layout.finishDistanceY, 0,
                                    "lowest finish-screen line top must stay in-bounds")
        XCTAssertLessThan(RunningHUDFrame.Layout.leftMargin, RunningHUDFrame.Layout.screenWidth)
        // rc16: 3-line mixed-font live HUD coordinates (text anchors)
        // AND icon framebuffer top-left coordinates must all fit.
        XCTAssertLessThan(RunningHUDFrame.Layout.liveLine1Y,    RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.liveDistanceY, RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThan(RunningHUDFrame.Layout.livePaceY,     RunningHUDFrame.Layout.screenHeight)
        XCTAssertGreaterThanOrEqual(RunningHUDFrame.Layout.livePaceY, 0,
                                    "lowest line top must stay in-bounds")
        XCTAssertGreaterThanOrEqual(RunningHUDFrame.Layout.liveHRX, 0,
                                    "HR x anchor must stay in-bounds")
        XCTAssertLessThan(RunningHUDFrame.Layout.liveHRX, RunningHUDFrame.Layout.screenWidth)
        XCTAssertLessThan(RunningHUDFrame.Layout.liveLeftMargin, RunningHUDFrame.Layout.screenWidth)
        XCTAssertGreaterThanOrEqual(RunningHUDFrame.Layout.liveLeftMargin, 0)

        // rc16: icon top-left + size must stay inside the 304×256 panel.
        // chrono is 40×40; heart/distance/pace are 28×28 each.
        let sw = UInt16(RunningHUDFrame.Layout.screenWidth)
        let sh = UInt16(RunningHUDFrame.Layout.screenHeight)
        XCTAssertLessThanOrEqual(RunningHUDFrame.Layout.chronoIconX + 40, sw)
        XCTAssertLessThanOrEqual(RunningHUDFrame.Layout.chronoIconY + 40, sh)
        XCTAssertLessThanOrEqual(RunningHUDFrame.Layout.heartIconX + 28, sw)
        XCTAssertLessThanOrEqual(RunningHUDFrame.Layout.heartIconY + 28, sh)
        XCTAssertLessThanOrEqual(RunningHUDFrame.Layout.distanceIconX + 28, sw)
        XCTAssertLessThanOrEqual(RunningHUDFrame.Layout.distanceIconY + 28, sh)
        XCTAssertLessThanOrEqual(RunningHUDFrame.Layout.paceIconX + 28, sw)
        XCTAssertLessThanOrEqual(RunningHUDFrame.Layout.paceIconY + 28, sh)
    }

    /// rc17 — finish-screen Y anchors revalidated under the canonical
    /// `y_fb = 255 − wearer_top` lens-flip formula (Richards's rc16
    /// review rec #1). The rc12-era values (166/86/6) were derived
    /// under `y_fb = 206 − T` and only "rendered OK" because the
    /// disconnect-on-stop bug (rc13-16) tore the BLE link down before
    /// anyone could inspect the finish screen. Walking the old paceY=6
    /// through the corrected formula puts the distance line at wearer
    /// bottom 313 → 57 px off-screen. rc17 keeps the link up past
    /// workout-stop, so the finish screen has to be pixel-correct.
    ///
    /// Locked layout (font 3, h=64): banner T=16, time T=96, distance
    /// T=176 (16-16-16 margins, even 16-px gaps). Asserting BOTH the
    /// raw constants AND that they obey the rc16 formula so a future
    /// edit that touches one without the other trips CI.
    func test_finishScreenYCoords_followLensFlipFormula_rc17() {
        XCTAssertEqual(RunningHUDFrame.Layout.finishBannerY,   239)
        XCTAssertEqual(RunningHUDFrame.Layout.finishTimeY,     159)
        XCTAssertEqual(RunningHUDFrame.Layout.finishDistanceY, 79)

        XCTAssertEqual(RunningHUDFrame.Layout.finishBannerY,   255 - 16,
                       "finishBannerY must equal 255 − wearer_top (rc16 formula)")
        XCTAssertEqual(RunningHUDFrame.Layout.finishTimeY,     255 - 96,
                       "finishTimeY must equal 255 − wearer_top (rc16 formula)")
        XCTAssertEqual(RunningHUDFrame.Layout.finishDistanceY, 255 - 176,
                       "finishDistanceY must equal 255 − wearer_top (rc16 formula)")

        // Every line's wearer-space bottom (top + font-3 height 64) must
        // stay within the 256-px panel. If a future edit nudges any of
        // the three constants past 191 (= 255 - 64), the corresponding
        // line will clip off the bottom of the wearer's view.
        let fontHeight: Int16 = 64
        for (name, yFB) in [
            ("finishBannerY",   RunningHUDFrame.Layout.finishBannerY),
            ("finishTimeY",     RunningHUDFrame.Layout.finishTimeY),
            ("finishDistanceY", RunningHUDFrame.Layout.finishDistanceY)
        ] {
            let wearerTop = 255 - yFB
            XCTAssertLessThanOrEqual(wearerTop + fontHeight, RunningHUDFrame.Layout.screenHeight,
                                     "\(name) puts text bottom off-panel (wearer_top=\(wearerTop) + \(fontHeight) > 256)")
            XCTAssertGreaterThanOrEqual(wearerTop, 0,
                                        "\(name) puts text above the wearer's view (wearer_top=\(wearerTop))")
        }
    }

    /// rc17 — `summaryFrames` MUST consume the new `finishBannerY /
    /// finishTimeY / finishDistanceY` constants and MUST do so in the
    /// banner / time / distance order. Pin both the y-anchor field of
    /// each `txt` frame and the string payload so a future edit that
    /// swaps the order (e.g. renders distance at the top) trips CI.
    func test_summaryFrames_yAnchorsUseFinishScreenConstants_rc17() {
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.summaryFrames(for: payload)
        XCTAssertEqual(frames.count, 4, "summary = clear + banner + time + distance (rc14)")

        struct ExpectedTxt { let frameIndex: Int; let y: Int16; let string: String }
        let expectations: [ExpectedTxt] = [
            ExpectedTxt(frameIndex: 1, y: RunningHUDFrame.Layout.finishBannerY,   string: "Workout Complete"),
            ExpectedTxt(frameIndex: 2, y: RunningHUDFrame.Layout.finishTimeY,     string: payload.time),
            ExpectedTxt(frameIndex: 3, y: RunningHUDFrame.Layout.finishDistanceY, string: payload.distance)
        ]

        for exp in expectations {
            let frame = frames[exp.frameIndex]
            // Layout: 0xFF | cmd | fmt | len | queryID | x(2) | y(2) | rot | font | color | bytes | 0x00 | 0xAA
            // y is bytes 7..8 big-endian.
            let yEncoded = Int16(bitPattern: (UInt16(frame[7]) << 8) | UInt16(frame[8]))
            XCTAssertEqual(yEncoded, exp.y,
                           "frame \(exp.frameIndex) y anchor must equal Layout finish constant")
            XCTAssertEqual(stringPayload(from: frame), exp.string)
        }
    }

    /// rc16: lens-flip arithmetic for the 3-line live HUD, **corrected**
    /// per Joe's rc15 bench evidence. Empirically:
    /// `y_fb = 255 − wearer_top` (topLR rotation=4 anchors at bottom of
    /// the framebuffer-rotated glyph, which maps to wearer-top after the
    /// 180° lens flip). Joe's rc15 "pace shows just one pixel at bottom"
    /// observation (livePaceY=26 + font-3 height 64 → wearer bottom 293,
    /// 38 px off-screen) only lines up under THIS formula, not the
    /// rc12-era `y_fb = 255 − T − font_height`.
    ///
    /// Wearer-space tops (with corrected font-3 height of 64 per the
    /// ActiveLook-Visual-Assets repo README):
    ///   Line 1 (font 2): T=15  → y_fb = 240
    ///   Line 2 (font 3): T=85  → y_fb = 170
    ///   Line 3 (font 3): T=178 → y_fb = 77
    func test_liveHUDYCoords_followLensFlipFormula_rc16() {
        XCTAssertEqual(RunningHUDFrame.Layout.liveLine1Y,    255 - 15)
        XCTAssertEqual(RunningHUDFrame.Layout.liveDistanceY, 255 - 85)
        XCTAssertEqual(RunningHUDFrame.Layout.livePaceY,     255 - 178)
    }

    /// rc16: pin the icon flash IDs against the preloaded ALooK config
    /// (asset filenames from `ActiveLook/Activelook-Visual-Assets`).
    /// A typo here would still encode a valid imgDisplay frame on the
    /// wire but the firmware would render the wrong icon (or nothing
    /// if the ID isn't preloaded). Lock the contract.
    func test_iconIDsMatchPreloadedALooKAssets_rc16() {
        XCTAssertEqual(RunningHUDFrame.Layout.chronoIconID,   40,
                       "chrono → 40_chrono_40x40")
        XCTAssertEqual(RunningHUDFrame.Layout.heartIconID,    12,
                       "heart-beat → 12_heart-beat_28x28")
        XCTAssertEqual(RunningHUDFrame.Layout.distanceIconID,  9,
                       "distance → 9_distance_28x28")
        XCTAssertEqual(RunningHUDFrame.Layout.paceIconID,     17,
                       "pace-avg → 17_pace-avg_28x28")
    }

    /// rc15: line 1 must use font 2 (smaller) so Time + HR can share
    /// the line without colliding. Single-metric lines 2/3 must stay
    /// on font 3 for readability. Guards against either constant being
    /// nudged in a way that re-introduces the rc14 overlap bug.
    func test_liveHUDLine1_usesShorterFontForTwoMetricLine() {
        XCTAssertEqual(RunningHUDFrame.Layout.liveLine1Font, 2,
                       "Line 1 hosts Time + HR — must use font 2 to fit both metrics")
        XCTAssertEqual(RunningHUDFrame.Layout.fontSize, 3,
                       "Single-metric lines must stay on font 3 for readability")
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

    /// rc15/rc16: distance + pace single-metric lines must stay at font 3
    /// for arm's-length readability. Line 1 (Time + HR) uses font 2 — see
    /// `test_liveHUDLine1_usesShorterFontForTwoMetricLine`. Together these
    /// guard against either a "make everything font 2" mass-edit
    /// regression (which would hurt readability) or a "make everything
    /// font 3" rollback (which would re-introduce the rc14 overlap bug).
    func test_runHUDFont_distanceAndPaceStayAtFont3() {
        XCTAssertEqual(RunningHUDFrame.Layout.fontSize, 3,
                       "run-HUD single-metric lines must stay at font 3 for readability")
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
        let frames = RunningHUDFrame.frames(for: payload)
        // rc16 frame order: 0 holdFlush, 1 clear, 2 chrono-img,
        // 3 Time (font 2), 4 heart-img, 5 HR (font 2),
        // 6 distance-img, 7 Distance (font 3), 8 pace-img,
        // 9 Pace (font 3), 10 holdFlush. Font byte in a txt frame
        // is at index 10.
        XCTAssertEqual(frames[3][10], 2, "Time (line 1) must use font 2")
        XCTAssertEqual(frames[5][10], 2, "HR (line 1) must use font 2")
        XCTAssertEqual(frames[7][10], 3, "Distance (line 2) must use font 3")
        XCTAssertEqual(frames[9][10], 3, "Pace (line 3) must use font 3")
    }

    func test_framesWithPowerOn_prependsCfgSetAndPowerOnToPlainFrames() {
        let payload = RunningHUDFrame.Payload(time: "0:00", heartRate: "--", distance: "0.00 mi", pace: "--:--/mi")
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
        let payload = RunningHUDFrame.Payload(time: "12:34", heartRate: "165", distance: "2.34 mi", pace: "8:30/mi")
        let plain = RunningHUDFrame.summaryFrames(for: payload)
        let withPower = RunningHUDFrame.summaryFramesWithPowerOn(for: payload)
        XCTAssertEqual(withPower.count, plain.count + 1)
        XCTAssertEqual(withPower[0], [0xFF, 0x00, 0x01, 0x07, 0x00, 0x01, 0xAA])
        XCTAssertEqual(Array(withPower.dropFirst()), plain)
    }

    func test_pushPolicy_firstSendAtT0PassesImmediatelyNotAfter1Second() {
        var policy = RunningHUDPushPolicy()
        let p = RunningHUDFrame.Payload(time: "0:00", heartRate: "--", distance: "0.00 mi", pace: "--:--/mi")
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
