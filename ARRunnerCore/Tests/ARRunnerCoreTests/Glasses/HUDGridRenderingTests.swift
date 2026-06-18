// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// v0.6.0 — pins the per-workout-type, unit-aware live-HUD render path:
/// `HUDLayout.default(for:)` slot ordering × `HUDGridDefinition` geometry ×
/// unit-aware `metricStrings`. These are the contracts the watch's
/// `pushHUDFrameIfConnected` relies on; the BLE write path itself is
/// bench-validated on hardware.
final class HUDGridRenderingTests: XCTestCase {

    private func snapshot() -> RunningHUDFrame.HUDMetricSnapshot {
        RunningHUDFrame.HUDMetricSnapshot(
            elapsedSeconds: 600,
            distanceMeters: 2000,
            heartRate: 150,
            speedMetersPerSecond: 8,
            cadence: 85,
            activeKilocalories: nil,
            elevationMeters: nil
        )
    }

    // MARK: - Unit-aware metric strings

    func test_metricStrings_metricUnits() {
        let s = RunningHUDFrame.metricStrings(
            snapshot: snapshot(), activity: .running, unitSystem: .metric
        )
        XCTAssertEqual(s[.duration], "10:00")
        XCTAssertEqual(s[.heartRate], "150")
        XCTAssertEqual(s[.distance], "2.00 km")
        XCTAssertEqual(s[.pace], "5:00/km")          // 600s / 2.0 km = 300 s/km
        XCTAssertEqual(s[.speed], "28.8 km/h")       // 8 m/s × 3.6
        XCTAssertEqual(s[.energy], "--")             // no value → placeholder
    }

    func test_metricStrings_imperialUnits() {
        let s = RunningHUDFrame.metricStrings(
            snapshot: snapshot(), activity: .cycling, unitSystem: .imperial
        )
        XCTAssertEqual(s[.distance], "1.24 mi")
        XCTAssertTrue(s[.pace]?.hasSuffix("/mi") ?? false, "imperial pace suffix")
        XCTAssertTrue(s[.speed]?.hasSuffix("mph") ?? false, "imperial speed unit")
        XCTAssertEqual(s[.cadence], "85 rpm")        // cycling → RPM
    }

    func test_formatCadence_perActivity() {
        XCTAssertEqual(RunningHUDFrame.formatCadence(85, activity: .cycling), "85 rpm")
        XCTAssertEqual(RunningHUDFrame.formatCadence(170, activity: .running), "170 spm")
        XCTAssertEqual(RunningHUDFrame.formatCadence(nil, activity: .running), "--")
    }

    func test_formatPace_secondsPerKilometer_unitAware() {
        XCTAssertEqual(
            RunMetricFormatting.formatPace(secondsPerKilometer: 300, unitSystem: .metric),
            "5:00/km"
        )
        // 300 s/km × 1.609344 km/mi = 482.8 s/mi → 8:03/mi
        XCTAssertEqual(
            RunMetricFormatting.formatPace(secondsPerKilometer: 300, unitSystem: .imperial),
            "8:03/mi"
        )
    }

    // MARK: - Slot ordering follows the layout

    func test_orderedSlotStrings_followLayout() {
        let strings = RunningHUDFrame.metricStrings(
            snapshot: snapshot(), activity: .cycling, unitSystem: .metric
        )
        // Outdoor bike default: [speed, heartRate, distance, duration].
        let bike = RunningHUDFrame.orderedSlotStrings(
            metricStrings: strings,
            layout: .default(for: .outdoorBike),
            grid: .standard4
        )
        XCTAssertEqual(bike.count, 4)
        XCTAssertEqual(bike[0], "28.8 km/h")  // speed in the prominent slot 0
        XCTAssertEqual(bike[1], "150")        // heart rate
        XCTAssertEqual(bike[3], "10:00")      // duration
    }

    // MARK: - Frame assembly + icons

    func test_frames_runIncludesIconPerSlot() {
        let strings = RunningHUDFrame.metricStrings(
            snapshot: snapshot(), activity: .running, unitSystem: .metric
        )
        // Outdoor run: [pace, heartRate, distance, duration] — every metric
        // has a preloaded icon, so each of the 4 slots emits icon + text.
        let frames = RunningHUDFrame.frames(
            metricStrings: strings, layout: .default(for: .outdoorRun), grid: .standard4
        )
        // holdFlush(true) + clear + 4×(icon+text) + holdFlush(false) = 11.
        XCTAssertEqual(frames.count, 11)
    }

    func test_frames_speedSlotIsTextOnly() {
        let strings = RunningHUDFrame.metricStrings(
            snapshot: snapshot(), activity: .cycling, unitSystem: .metric
        )
        // Outdoor bike: speed has no preloaded icon → that slot is text-only,
        // so the batch is one frame shorter than the all-iconned run layout.
        let frames = RunningHUDFrame.frames(
            metricStrings: strings, layout: .default(for: .outdoorBike), grid: .standard4
        )
        XCTAssertEqual(frames.count, 10)
    }

    func test_framesWithPowerOn_prependsCfgSetAndPower() {
        let strings = RunningHUDFrame.metricStrings(
            snapshot: snapshot(), activity: .running, unitSystem: .metric
        )
        let plain = RunningHUDFrame.frames(
            metricStrings: strings, layout: .default(for: .outdoorRun), grid: .standard4
        )
        let powered = RunningHUDFrame.framesWithPowerOn(
            metricStrings: strings, layout: .default(for: .outdoorRun), grid: .standard4
        )
        XCTAssertEqual(powered.count, plain.count + 2)
        XCTAssertEqual(Array(powered.suffix(plain.count)), plain)
    }

    func test_iconFramebuffer_reproducesRC16Coordinates() {
        // The standard4 grid + chrono icon (40×40) must land at the
        // rc16 bench-validated framebuffer anchor (248, 200).
        let slot = HUDGridDefinition.standard4.slots[0]
        let chrono = RunningHUDFrame.HUDIcon(id: 40, width: 40, height: 40)
        let pos = RunningHUDFrame.iconFramebuffer(slot: slot, icon: chrono)
        XCTAssertEqual(pos.x, 248)
        XCTAssertEqual(pos.y, 200)
    }

    // MARK: - Push policy (generalized signature)

    func test_pushPolicy_signatureChangeDetection() {
        let t0 = Date(timeIntervalSince1970: 0)
        var policy = RunningHUDPushPolicy()
        XCTAssertTrue(policy.shouldSend(["10:00", "150", "2.00 km", "5:00/km"], now: t0))
        // Identical signature inside the 1 Hz window → suppressed.
        XCTAssertFalse(policy.shouldSend(["10:00", "150", "2.00 km", "5:00/km"],
                                         now: t0.addingTimeInterval(0.5)))
        // A changed value inside the window still ships immediately.
        XCTAssertTrue(policy.shouldSend(["10:01", "150", "2.00 km", "5:00/km"],
                                        now: t0.addingTimeInterval(0.6)))
    }
}
