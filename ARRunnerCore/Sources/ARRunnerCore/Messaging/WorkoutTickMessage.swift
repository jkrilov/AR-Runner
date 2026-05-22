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

    /// Wall-clock start time of the workout — the `HKWorkoutSession`
    /// `startDate` mirrored from the watch. rc2 (2026-05-20) addition for
    /// the phone-side "Started at …" row in the live mirror. Carried on
    /// every tick (not a one-shot lifecycle event) so a phone that joins
    /// the mirror mid-run still sees the start time on the very first
    /// snapshot it receives — no "wait for the next lifecycle event" race.
    ///
    /// **Optional** for backwards compatibility with v3 peers (a watch
    /// running rc17 / TestFlight build 32 doesn't populate this field;
    /// the phone falls back to `timestamp − elapsedSeconds` for display).
    /// WC schema bumped 3 → 4 to flag the additive change.
    public let startedAt: Date?

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

    /// v0.5.16 — most recent GPS fix (decimal degrees), piggybacked on the
    /// existing ~1 Hz tick so the iPhone live mirror can plot the route
    /// without a second stream. Both values are present together or both
    /// are nil — the watch only emits them once `CoreLocation` has handed
    /// it a fix that passed the same horizontal-accuracy filter that
    /// feeds `HKWorkoutRouteBuilder`, so the polyline the phone draws is
    /// identical to what Apple Health stores. Optional for backwards
    /// compatibility with v4 / older watch builds (the phone treats
    /// "no lat/lon" as "no map yet" — never as an error).
    public let latitude: Double?
    public let longitude: Double?

    public init(
        sessionID: UUID,
        sport: SportType,
        phase: WorkoutPhase,
        timestamp: Date,
        startedAt: Date? = nil,
        elapsedSeconds: TimeInterval,
        heartRateBeatsPerMinute: Double?,
        distanceMeters: Double?,
        paceSecondsPerKilometer: Double?,
        estimatedActiveKilocalories: Double?,
        glassesConnected: Bool,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.sessionID = sessionID
        self.sport = sport
        self.phase = phase
        self.timestamp = timestamp
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.heartRateBeatsPerMinute = heartRateBeatsPerMinute
        self.distanceMeters = distanceMeters
        self.paceSecondsPerKilometer = paceSecondsPerKilometer
        self.estimatedActiveKilocalories = estimatedActiveKilocalories
        self.glassesConnected = glassesConnected
        self.latitude = latitude
        self.longitude = longitude
    }
}
