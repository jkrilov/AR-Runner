// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure, platform-agnostic helpers that translate raw HealthKit sample
/// values into `WorkoutMetric` instances. Lives in Core (rather than
/// inside `HealthKitWorkoutSubstrate`) so the mapping contract is
/// exercisable from `ARRunnerCoreTests` without needing a watchOS test
/// host — the substrate just calls through.
///
/// Adapter-only contract: callers are responsible for passing the sample
/// value already converted into the documented unit.
public enum HealthKitMetricMapping {
    /// Active energy (kcal). Maps to `MetricKind.energy` — kcal units
    /// match HealthKit's `HKUnit.kilocalorie()` so no conversion is
    /// required at the adapter boundary (see Amber's D-AMBER decision).
    ///
    /// v0.2 audit P1.3: prior to MetricKind.energy existing the
    /// substrate routed this through `.duration`, which downstream
    /// consumers silently default-case'd — live HK kcal never reached
    /// the UI.
    public static func activeEnergy(kilocalories: Double, timestamp: Date) -> WorkoutMetric {
        WorkoutMetric(kind: .energy, value: kilocalories, unit: "kcal", timestamp: timestamp)
    }
}
