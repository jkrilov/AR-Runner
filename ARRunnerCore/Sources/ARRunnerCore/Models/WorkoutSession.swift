// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum WorkoutSessionStatus: String, Sendable, Codable, Equatable {
    case prepared
    case running
    case paused
    case ended
}

public struct WorkoutSession: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let sport: WorkoutType
    public let startedAt: Date
    public let status: WorkoutSessionStatus
    public let metricStream: [WorkoutMetric]

    public init(
        id: UUID = UUID(),
        sport: WorkoutType,
        startedAt: Date,
        status: WorkoutSessionStatus,
        metricStream: [WorkoutMetric]
    ) {
        self.id = id
        self.sport = sport
        self.startedAt = startedAt
        self.status = status
        self.metricStream = metricStream
    }
}
