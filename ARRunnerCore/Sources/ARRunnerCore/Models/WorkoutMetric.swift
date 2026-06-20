// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MetricKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case heartRate
    case pace
    case distance
    case duration
    case cadence
    case elevation
    case energy
    /// Ground speed (metres per second on the wire). Cycling surfaces speed
    /// rather than pace; formatted as km/h or mph by `RunMetricFormatting`.
    case speed
    /// Compass heading (bearing in **degrees 0–359** on the wire). Sourced on
    /// watchOS from `CLLocationManager.startUpdatingHeading()` (the device
    /// magnetometer), so it is meaningful indoors and without a GPS fix. Value
    /// is unit-system independent; `RunMetricFormatting.formatHeading(degrees:)`
    /// renders it as an 8-point cardinal + zero-padded degrees (e.g. "NE 045°").
    case heading
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
