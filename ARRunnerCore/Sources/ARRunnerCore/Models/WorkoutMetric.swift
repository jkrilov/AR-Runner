// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MetricKind: String, Sendable, Codable, CaseIterable, Equatable {
    case heartRate
    case pace
    case distance
    case duration
    case cadence
    case elevation
    case energy
}

public struct WorkoutMetric: Sendable, Codable, Equatable {
    public let kind: MetricKind
    public let value: Double
    public let unit: String
    public let timestamp: Date

    public init(kind: MetricKind, value: Double, unit: String, timestamp: Date) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
    }
}
