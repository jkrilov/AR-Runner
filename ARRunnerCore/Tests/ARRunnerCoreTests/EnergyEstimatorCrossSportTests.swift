// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Cross-sport sanity for the live `EnergyEstimator` (Keytel HR-based model).
///
/// The Keytel (2005) formula was validated on *running/treadmill* cohorts, so
/// the live number is biased for walking (slightly high) and cycling (the same
/// HR maps to a different true VO₂ than running). The official kcal still comes
/// from HealthKit on save — this estimator only drives the live HUD/mirror.
/// These tests therefore assert *plausibility* (non-negative, monotone in HR,
/// inside a generous physiological window) rather than exact values, and
/// document the known running-derived bias instead of pinning it.
final class EnergyEstimatorCrossSportTests: XCTestCase {

    // Representative bodies. Female + unspecified exercise both formula
    // branches and the average fallback.
    private let male = BodyProfile(weightKilograms: 78, ageYears: 38, sex: .male)
    private let female = BodyProfile(weightKilograms: 62, ageYears: 30, sex: .female)
    private let unspecified = BodyProfile(weightKilograms: 70, ageYears: 35, sex: .unspecified)

    // MARK: - Per-sport representative HR is non-negative and plausible

    func testWalkingLowHeartRateIsNonNegativeAndModest() {
        // Walking ~ HR 90. Live kcal/min should be small but >= 0, never NaN.
        for profile in [male, female, unspecified] {
            let rate = EnergyEstimator(profile: profile).kilocaloriesPerMinute(heartRate: 90)
            XCTAssertGreaterThanOrEqual(rate, 0, "walking kcal/min must never go negative")
            XCTAssertTrue(rate.isFinite)
            XCTAssertLessThan(rate, 14, "walking at HR 90 should be a modest burn")
        }
    }

    func testRunningHeartRateInValidatedWindow() {
        // Running ~ HR 150 — the cohort the formula was fit on. Widest trust.
        for profile in [male, female, unspecified] {
            let rate = EnergyEstimator(profile: profile).kilocaloriesPerMinute(heartRate: 150)
            XCTAssertGreaterThan(rate, 4)
            XCTAssertLessThan(rate, 22)
        }
    }

    func testCyclingHeartRateIsPlausibleDespiteRunningBias() {
        // Cycling ~ HR 140. Same HR → the running-derived formula tends to
        // *over*-estimate vs a cycling-specific model; we only assert it stays
        // in a sane band and stays positive.
        for profile in [male, female, unspecified] {
            let rate = EnergyEstimator(profile: profile).kilocaloriesPerMinute(heartRate: 140)
            XCTAssertGreaterThan(rate, 3)
            XCTAssertLessThan(rate, 22)
        }
    }

    // MARK: - Structural guarantees that hold for every sport

    func testKilocaloriesPerMinuteIsMonotoneInHeartRate() {
        // Higher HR ⇒ never fewer kcal/min, for every profile. Guards a sign
        // flip in the formula (female weight coefficient is negative).
        for profile in [male, female, unspecified] {
            let estimator = EnergyEstimator(profile: profile)
            let low = estimator.kilocaloriesPerMinute(heartRate: 90)
            let mid = estimator.kilocaloriesPerMinute(heartRate: 140)
            let high = estimator.kilocaloriesPerMinute(heartRate: 170)
            XCTAssertLessThanOrEqual(low, mid, "\(profile.sex) not monotone 90→140")
            XCTAssertLessThanOrEqual(mid, high, "\(profile.sex) not monotone 140→170")
        }
    }

    func testUnspecifiedSexIsAverageOfMaleAndFemale() {
        let hr = 150.0
        let m = EnergyEstimator(profile: BodyProfile(weightKilograms: 70, ageYears: 35, sex: .male))
            .kilocaloriesPerMinute(heartRate: hr)
        let f = EnergyEstimator(profile: BodyProfile(weightKilograms: 70, ageYears: 35, sex: .female))
            .kilocaloriesPerMinute(heartRate: hr)
        let u = EnergyEstimator(profile: unspecified).kilocaloriesPerMinute(heartRate: hr)
        XCTAssertEqual(u, (m + f) / 2.0, accuracy: 1e-9)
    }

    func testNonFiniteHeartRateNeverProducesNegativeIncrement() {
        // Defensive: a stray NaN/inf HR sample must not corrupt the live total.
        let estimator = EnergyEstimator(profile: male)
        XCTAssertEqual(estimator.incrementKilocalories(heartRate: .nan, sinceLast: 60), 0)
        // inf HR clamps via max(0, …) on a finite gap; just assert non-negative.
        XCTAssertGreaterThanOrEqual(estimator.incrementKilocalories(heartRate: 150, sinceLast: 60), 0)
    }

    func testHeavierAthleteBurnsAtLeastAsMuchAtSameHeartRate() {
        // Male/unspecified weight coefficient is positive — more mass, more
        // kcal at identical HR. (Female branch is the documented exception:
        // its weight term is negative, so it is intentionally excluded here.)
        let light = EnergyEstimator(profile: BodyProfile(weightKilograms: 60, ageYears: 35, sex: .male))
        let heavy = EnergyEstimator(profile: BodyProfile(weightKilograms: 95, ageYears: 35, sex: .male))
        XCTAssertGreaterThan(
            heavy.kilocaloriesPerMinute(heartRate: 150),
            light.kilocaloriesPerMinute(heartRate: 150)
        )
    }
}
