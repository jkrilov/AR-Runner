// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Compact live-workout snapshot streamed from the watch to the iPhone mirror
/// at ~1 Hz over WCSession (v0.2 workstream #3).
///
/// Watch-first per v0.2 decision #3: this payload is opportunistic. The watch
/// emits ticks whenever a workout is running and the WC link is reachable;
/// missing the iPhone (out of range, app not installed, airplane mode) MUST
/// NOT affect the watch-side workout. Receivers treat the absence of new
/// ticks as "stale" rather than "ended" — the lifecycle is reported via
/// `WCMessage.workoutLifecycle` / the snapshot's own `phase` field.
///
/// Hybrid energy per v0.2 decision #4: `estimatedActiveKilocalories` is the
/// watch-side rolling estimate from heart rate + body metrics. The official
/// HealthKit number is reconciled on save and lives on `WorkoutSummary`; the
/// mirror should treat this field as an indicative live readout only.
public struct WorkoutTickMessage: Sendable, Codable, Equatable {
    public let sessionID: UUID
    public let sport: SportType
    public let phase: WorkoutPhase
    public let timestamp: Date

    /// Seconds since `WorkoutState.startedAt`. Wall-clock derived; not the
    /// HealthKit "active duration" (that one is final-only).
    public let elapsedSeconds: TimeInterval

    public let heartRateBeatsPerMinute: Double?
    public let distanceMeters: Double?
    public let paceSecondsPerKilometer: Double?

    /// Live local kcal estimate (decision #4). Nil if the watch hasn't seen
    /// enough HR samples or has no body profile to compute against.
    public let estimatedActiveKilocalories: Double?

    public let glassesConnected: Bool

    public init(
        sessionID: UUID,
        sport: SportType,
        phase: WorkoutPhase,
        timestamp: Date,
        elapsedSeconds: TimeInterval,
        heartRateBeatsPerMinute: Double?,
        distanceMeters: Double?,
        paceSecondsPerKilometer: Double?,
        estimatedActiveKilocalories: Double?,
        glassesConnected: Bool
    ) {
        self.sessionID = sessionID
        self.sport = sport
        self.phase = phase
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.heartRateBeatsPerMinute = heartRateBeatsPerMinute
        self.distanceMeters = distanceMeters
        self.paceSecondsPerKilometer = paceSecondsPerKilometer
        self.estimatedActiveKilocalories = estimatedActiveKilocalories
        self.glassesConnected = glassesConnected
    }
}
