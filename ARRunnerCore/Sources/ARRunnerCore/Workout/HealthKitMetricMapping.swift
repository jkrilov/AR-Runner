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
    /// Active energy (kcal). Routes to `MetricKind.energy` — units match
    /// HealthKit's `HKUnit.kilocalorie()` so no conversion is required at
    /// the adapter boundary. Must NOT be routed through `.duration`;
    /// downstream default-cases would silently drop the value.
    public static func activeEnergy(kilocalories: Double, timestamp: Date) -> WorkoutMetric {
        WorkoutMetric(kind: .energy, value: kilocalories, unit: "kcal", timestamp: timestamp)
    }
}
