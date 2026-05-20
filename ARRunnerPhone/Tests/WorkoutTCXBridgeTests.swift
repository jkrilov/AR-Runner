// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ARRunnerCore
@testable import ARRunnerPhone

/// `WorkoutTCXBridge` exposes a pure `mergeTrackpoints` step independently of
/// HealthKit so the merge logic (the part most likely to regress) is unit-
/// testable without a HK store.
final class WorkoutTCXBridgeTests: XCTestCase {

    func test_mergeTrackpoints_emitsHROnly_whenNoLocations() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let hr = [
            WorkoutTCXBridge.HRSample(timestamp: t0, beatsPerMinute: 140),
            WorkoutTCXBridge.HRSample(timestamp: t0.addingTimeInterval(5), beatsPerMinute: 150)
        ]
        let tp = WorkoutTCXBridge.mergeTrackpoints(locations: [], heartRates: hr)
        XCTAssertEqual(tp.count, 2)
        XCTAssertEqual(tp[0].heartRateBPM, 140)
        XCTAssertNil(tp[0].latitude)
    }

    func test_mergeTrackpoints_emitsLocationsWithHR_withinWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let locs = [
            WorkoutTCXBridge.LocationSample(timestamp: t0, latitude: 1.0, longitude: 2.0, altitude: 100),
            WorkoutTCXBridge.LocationSample(timestamp: t0.addingTimeInterval(10), latitude: 1.1, longitude: 2.1, altitude: 101)
        ]
        let hr = [
            WorkoutTCXBridge.HRSample(timestamp: t0.addingTimeInterval(1), beatsPerMinute: 142),
            WorkoutTCXBridge.HRSample(timestamp: t0.addingTimeInterval(11), beatsPerMinute: 158)
        ]
        let tp = WorkoutTCXBridge.mergeTrackpoints(locations: locs, heartRates: hr)
        XCTAssertEqual(tp.count, 2)
        XCTAssertEqual(tp[0].latitude, 1.0)
        XCTAssertEqual(tp[0].heartRateBPM, 142)
        XCTAssertEqual(tp[1].heartRateBPM, 158)
    }

    func test_mergeTrackpoints_skipsHR_outsideWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let locs = [
            WorkoutTCXBridge.LocationSample(timestamp: t0, latitude: 1.0, longitude: 2.0, altitude: nil)
        ]
        let hr = [
            // 30s away — well beyond the ±10s window.
            WorkoutTCXBridge.HRSample(timestamp: t0.addingTimeInterval(30), beatsPerMinute: 142)
        ]
        let tp = WorkoutTCXBridge.mergeTrackpoints(locations: locs, heartRates: hr)
        XCTAssertEqual(tp.count, 1)
        XCTAssertNil(tp[0].heartRateBPM)
        XCTAssertNil(tp[0].altitudeMeters)
    }

    func test_mergeTrackpoints_resultEncodesToValidTCX() {
        // End-to-end sanity: a merged trackpoint set is acceptable input to
        // the cross-platform TCXEncoder (catches accidental field-shape
        // regressions where a merge change breaks encoder expectations).
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let locs = [
            WorkoutTCXBridge.LocationSample(timestamp: t0, latitude: 37.0, longitude: -122.0, altitude: 50)
        ]
        let hr = [WorkoutTCXBridge.HRSample(timestamp: t0, beatsPerMinute: 130)]
        let tp = WorkoutTCXBridge.mergeTrackpoints(locations: locs, heartRates: hr)
        let lap = TCXLap(
            startTime: t0, totalTimeSeconds: 60, distanceMeters: 100,
            calories: nil, averageHeartRate: 130, maximumHeartRate: 130,
            trackpoints: tp)
        let data = TCXWorkoutData(
            workoutID: UUID(),
            startDate: t0,
            endDate: t0.addingTimeInterval(60),
            totalDistanceMeters: 100,
            totalDurationSeconds: 60,
            trackpoints: tp,
            laps: [lap])
        let bytes = TCXEncoder.encode(data)
        XCTAssertFalse(bytes.isEmpty)
        let s = String(data: bytes, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("<TrainingCenterDatabase"))
        XCTAssertTrue(s.contains("37."))
        XCTAssertTrue(s.contains("130"))
    }
}
