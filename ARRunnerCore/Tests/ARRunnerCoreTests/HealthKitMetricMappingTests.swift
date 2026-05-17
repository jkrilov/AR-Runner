// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class HealthKitMetricMappingTests: XCTestCase {
    /// v0.2 audit P1.3: assert the substrate's adapter path emits
    /// `.energy` (kcal) — not `.duration` — so live HealthKit kcal
    /// reaches downstream consumers (controller fan-out, HUD, mirror).
    /// The substrate itself can only run under a watchOS test host
    /// (which this project does not have), so the Core-side helper is
    /// the contract surface we lock instead.
    func testActiveEnergyMapsToEnergyKindWithKilocalorieUnit() {
        let timestamp = Date(timeIntervalSinceReferenceDate: 7_654)
        let metric = HealthKitMetricMapping.activeEnergy(
            kilocalories: 142.5,
            timestamp: timestamp
        )

        XCTAssertEqual(metric.kind, .energy, "active energy must not regress to .duration (v0.2 P1.3)")
        XCTAssertEqual(metric.value, 142.5)
        XCTAssertEqual(metric.unit, "kcal")
        XCTAssertEqual(metric.timestamp, timestamp)
    }

    func testActiveEnergyPreservesValueAcrossRange() {
        // Sanity: no rounding / clamping on the adapter side. HealthKit's
        // kcal samples can be < 1 (early in a workout) or > 1000 (long
        // runs); both must pass through unchanged so post-session
        // reconciliation against `HKWorkout.totalEnergyBurned` matches.
        for kcal in [0.0, 0.42, 1.0, 873.4, 4_312.99] {
            let metric = HealthKitMetricMapping.activeEnergy(kilocalories: kcal, timestamp: Date())
            XCTAssertEqual(metric.value, kcal, accuracy: .ulpOfOne)
            XCTAssertEqual(metric.kind, .energy)
        }
    }
}
