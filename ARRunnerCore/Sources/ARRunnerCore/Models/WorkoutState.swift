// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// High-level lifecycle phase of a workout. Mirrors the legal transitions of
/// `HKWorkoutSessionState` but is platform-agnostic so it can flow through
/// Swift 6 strict-concurrent boundaries without leaking HealthKit types.
public enum WorkoutPhase: String, Sendable, Codable, Equatable, CaseIterable {
    case idle
    case preparing
    case running
    case paused
    case ended
    case failed
}

/// An immutable snapshot of the controller's observable state. Every transition
/// emits a fresh value on the controller's `states` async sequence so views,
/// the glasses adapter, and the WatchConnectivity bridge can react uniformly.
///
/// Sport-agnostic per D3: the `sport` field is populated for v0.1 running runs
/// and will carry cycling/walking values when those surfaces ship in v1.
public struct WorkoutState: Sendable, Codable, Equatable {
    public let sessionID: UUID
    public let sport: SportType
    public let phase: WorkoutPhase
    public let startedAt: Date?
    public let endedAt: Date?
    public let glassesConnected: Bool
    public let timestamp: Date
    public let failureReason: String?

    public init(
        sessionID: UUID,
        sport: SportType,
        phase: WorkoutPhase,
        startedAt: Date?,
        endedAt: Date?,
        glassesConnected: Bool,
        timestamp: Date,
        failureReason: String? = nil
    ) {
        self.sessionID = sessionID
        self.sport = sport
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.glassesConnected = glassesConnected
        self.timestamp = timestamp
        self.failureReason = failureReason
    }
}
