// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class EnergyEstimatorTests: XCTestCase {
    private let profile = BodyProfile(weightKilograms: 75, ageYears: 35, sex: .male)

    func testKilocaloriesPerMinutePositiveForRunningHR() {
        let estimator = EnergyEstimator(profile: profile)
        let rate = estimator.kilocaloriesPerMinute(heartRate: 150)
        // Sanity bounds — Keytel gives roughly 13 kcal/min for a 75kg/35yo male
        // at HR 150; assert a generous window so future tweaks don't break us.
        XCTAssertGreaterThan(rate, 8)
        XCTAssertLessThan(rate, 20)
    }

    func testZeroHeartRateProducesZeroKilocalories() {
        let estimator = EnergyEstimator(profile: profile)
        XCTAssertEqual(estimator.kilocaloriesPerMinute(heartRate: 0), 0)
        XCTAssertEqual(estimator.incrementKilocalories(heartRate: 0, sinceLast: 60), 0)
    }

    func testGapClampPreventsRunawayEstimate() {
        let estimator = EnergyEstimator(profile: profile, maxSampleGapSeconds: 10)
        // A 5-minute gap between samples MUST be clamped to 10s — otherwise a
        // long pause would falsely accumulate kcal once the watch resumed
        // sampling.
        let huge = estimator.incrementKilocalories(heartRate: 150, sinceLast: 300)
        let bounded = estimator.incrementKilocalories(heartRate: 150, sinceLast: 10)
        XCTAssertEqual(huge, bounded, accuracy: 0.0001)
    }

    func testAccumulatorIntegratesAcrossSamples() {
        var accumulator = EnergyAccumulator(estimator: EnergyEstimator(profile: profile))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        accumulator.ingest(heartRate: 150, at: t0)        // first sample — no gap yet
        XCTAssertEqual(accumulator.totalKilocalories, 0)

        accumulator.ingest(heartRate: 150, at: t0.addingTimeInterval(60))
        XCTAssertGreaterThan(accumulator.totalKilocalories, 0)

        let afterOneMinute = accumulator.totalKilocalories
        accumulator.ingest(heartRate: 150, at: t0.addingTimeInterval(120))
        XCTAssertGreaterThan(accumulator.totalKilocalories, afterOneMinute)
    }

    func testAccumulatorResetClearsState() {
        var accumulator = EnergyAccumulator(estimator: EnergyEstimator(profile: profile))
        let t0 = Date()
        accumulator.ingest(heartRate: 160, at: t0)
        accumulator.ingest(heartRate: 160, at: t0.addingTimeInterval(60))
        accumulator.reset()
        XCTAssertEqual(accumulator.totalKilocalories, 0)
    }
}
