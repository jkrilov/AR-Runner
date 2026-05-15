// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User-supplied body metrics used by the live energy estimator. The values
/// are typically read from HealthKit at workout start, but the type is plain
/// `Sendable` so it crosses Linux SPM tests and Swift 6 boundaries cleanly.
public struct BodyProfile: Sendable, Equatable {
    public enum BiologicalSex: String, Sendable, Equatable, Codable {
        case male
        case female
        case unspecified
    }

    public let weightKilograms: Double
    public let ageYears: Int
    public let sex: BiologicalSex

    public init(weightKilograms: Double, ageYears: Int, sex: BiologicalSex) {
        self.weightKilograms = weightKilograms
        self.ageYears = ageYears
        self.sex = sex
    }
}

/// Live, HR-based active-energy estimator for the watch HUD/mirror display.
///
/// **Hybrid model per v0.2 decision #4** — this is the *live* number shown to
/// the user during a run. The *official* number is whatever HealthKit returns
/// when `HKLiveWorkoutBuilder.finishWorkout()` resolves on save; the watch
/// should overwrite this estimate with the HealthKit value once available.
///
/// Formula: Keytel et al. (2005) HR-based kcal/min, integrated by sample time.
///   * Male:   kcal/min = (-55.0969 + 0.6309·HR + 0.1988·W + 0.2017·A) / 4.184
///   * Female: kcal/min = (-20.4022 + 0.4472·HR - 0.1263·W + 0.0740·A) / 4.184
/// Unspecified sex falls back to the simple average of the two.
///
/// The estimator is platform-neutral (pure Foundation) so it lives in `Core`
/// and stays Linux-buildable for `swift test`.
public struct EnergyEstimator: Sendable {
    public let profile: BodyProfile

    /// Maximum gap between consecutive HR samples that is still treated as
    /// "active". A gap longer than this is clamped — this prevents a stale
    /// heart-rate sample from inflating the estimate during a long pause.
    public let maxSampleGapSeconds: TimeInterval

    public init(profile: BodyProfile, maxSampleGapSeconds: TimeInterval = 15) {
        self.profile = profile
        self.maxSampleGapSeconds = maxSampleGapSeconds
    }

    /// kcal/min for a given heart-rate value. Pure function for testability.
    public func kilocaloriesPerMinute(heartRate: Double) -> Double {
        let w = profile.weightKilograms
        let a = Double(profile.ageYears)
        let male = (-55.0969 + 0.6309 * heartRate + 0.1988 * w + 0.2017 * a) / 4.184
        let female = (-20.4022 + 0.4472 * heartRate - 0.1263 * w + 0.0740 * a) / 4.184

        let raw: Double
        switch profile.sex {
        case .male: raw = male
        case .female: raw = female
        case .unspecified: raw = (male + female) / 2.0
        }
        return max(0, raw)
    }

    /// Integrate from the previous sample's HR over the elapsed wall-clock
    /// gap (clamped to `maxSampleGapSeconds`). Returns the kcal increment
    /// to add to a running total — the caller owns the accumulator.
    public func incrementKilocalories(
        heartRate: Double,
        sinceLast gap: TimeInterval
    ) -> Double {
        guard heartRate > 0, gap > 0 else { return 0 }
        let clampedGap = min(gap, maxSampleGapSeconds)
        let kcalPerMin = kilocaloriesPerMinute(heartRate: heartRate)
        return kcalPerMin * (clampedGap / 60.0)
    }
}

/// Stateful accumulator that pairs an `EnergyEstimator` with the most recent
/// HR sample timestamp. Use one per workout and reset between runs.
///
/// Designed for the watch view-model layer (single owner, always touched
/// from the same isolation domain). Not actor-isolated itself — wrap it on
/// the call site if cross-isolation access is needed.
public struct EnergyAccumulator: Sendable {
    private let estimator: EnergyEstimator
    private(set) public var totalKilocalories: Double = 0
    private var lastSampleAt: Date?

    public init(estimator: EnergyEstimator) {
        self.estimator = estimator
    }

    public mutating func ingest(heartRate: Double, at timestamp: Date) {
        defer { lastSampleAt = timestamp }
        guard let lastSampleAt else { return }
        let gap = timestamp.timeIntervalSince(lastSampleAt)
        totalKilocalories += estimator.incrementKilocalories(
            heartRate: heartRate,
            sinceLast: gap
        )
    }

    public mutating func reset() {
        totalKilocalories = 0
        lastSampleAt = nil
    }
}
