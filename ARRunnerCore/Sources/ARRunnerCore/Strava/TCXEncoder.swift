// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Encodes a `TCXWorkoutData` value into a TCX 2.0 (Training Center XML)
/// document ready for the Strava `POST /api/v3/uploads` endpoint.
///
/// **Per D-Strava-2 (v0.5):** TCX is XML, maps cleanly to `HKWorkout` +
/// `HKWorkoutRoute` + HR samples, and adds zero new dependencies — this
/// encoder uses Foundation string interpolation only (no XMLDocument, which
/// is unavailable on watchOS/iOS).
///
/// The output is deterministic: same input → byte-identical output. This is
/// what makes the upload idempotency guarantee (`external_id` =
/// `HKWorkout.uuid`) actually safe, because Strava de-dupes on bytes-and-id.
///
/// Edge cases handled:
/// - **No route, HR only:** trackpoints carry only `<Time>` + `<HeartRateBpm>`.
/// - **Route only, no HR:** trackpoints carry only `<Time>` + `<Position>` +
///   optional `<AltitudeMeters>`.
/// - **Empty workout (no trackpoints):** still produces valid TCX — the
///   `<Lap>` carries no `<Track>` child, which the TCX 2.0 schema permits.
public enum TCXEncoder {
    /// Standard TCX 2.0 namespace.
    public static let namespace = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
    public static let xsiNamespace = "http://www.w3.org/2001/XMLSchema-instance"
    public static let activityExtNamespace = "http://www.garmin.com/xmlschemas/ActivityExtension/v2"

    /// Encode `data` into a UTF-8 TCX document.
    public static func encode(_ data: TCXWorkoutData) -> Data {
        let xml = makeXMLString(data)
        // Force-unwrap: UTF-8 encoding of an ASCII-safe XML string with
        // escaped entities cannot fail. Foundation guarantees this.
        return xml.data(using: .utf8)!
    }

    /// String form for tests / debugging.
    public static func encodeToString(_ data: TCXWorkoutData) -> String {
        makeXMLString(data)
    }

    // MARK: - XML assembly

    private static func makeXMLString(_ data: TCXWorkoutData) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        xml += "<TrainingCenterDatabase"
        xml += " xmlns=\"\(namespace)\""
        xml += " xmlns:xsi=\"\(xsiNamespace)\""
        xml += " xmlns:ns3=\"\(activityExtNamespace)\""
        xml += ">\n"
        xml += "  <Activities>\n"
        xml += "    <Activity Sport=\"\(escapeAttr(data.sport))\">\n"
        xml += "      <Id>\(formatTimestamp(data.startDate))</Id>\n"

        if data.laps.isEmpty {
            // Synthesize a single lap from the workout summary so output is
            // always schema-valid (TCX requires ≥1 <Lap> per <Activity>).
            let synth = TCXLap(
                startTime: data.startDate,
                totalTimeSeconds: data.totalDurationSeconds,
                distanceMeters: data.totalDistanceMeters,
                trackpoints: data.trackpoints
            )
            xml += renderLap(synth)
        } else {
            for lap in data.laps {
                xml += renderLap(lap)
            }
        }

        xml += "      <Creator xsi:type=\"Device_t\">\n"
        xml += "        <Name>AR-Runner</Name>\n"
        xml += "        <UnitId>0</UnitId>\n"
        xml += "        <ProductID>0</ProductID>\n"
        xml += "      </Creator>\n"
        xml += "      <Notes>\(escapeText("via AR-Runner — \(data.workoutID.uuidString)"))</Notes>\n"
        xml += "    </Activity>\n"
        xml += "  </Activities>\n"
        xml += "</TrainingCenterDatabase>\n"
        return xml
    }

    private static func renderLap(_ lap: TCXLap) -> String {
        var xml = "      <Lap StartTime=\"\(formatTimestamp(lap.startTime))\">\n"
        xml += "        <TotalTimeSeconds>\(formatDecimal(lap.totalTimeSeconds))</TotalTimeSeconds>\n"
        xml += "        <DistanceMeters>\(formatDecimal(lap.distanceMeters))</DistanceMeters>\n"
        xml += "        <MaximumSpeed>0.0</MaximumSpeed>\n"
        xml += "        <Calories>\(lap.calories ?? 0)</Calories>\n"
        if let avg = lap.averageHeartRate {
            xml += "        <AverageHeartRateBpm>\n          <Value>\(avg)</Value>\n        </AverageHeartRateBpm>\n"
        }
        if let max = lap.maximumHeartRate {
            xml += "        <MaximumHeartRateBpm>\n          <Value>\(max)</Value>\n        </MaximumHeartRateBpm>\n"
        }
        xml += "        <Intensity>Active</Intensity>\n"
        xml += "        <TriggerMethod>Manual</TriggerMethod>\n"

        if !lap.trackpoints.isEmpty {
            xml += "        <Track>\n"
            for tp in lap.trackpoints {
                xml += renderTrackpoint(tp)
            }
            xml += "        </Track>\n"
        }
        xml += "      </Lap>\n"
        return xml
    }

    private static func renderTrackpoint(_ tp: TCXTrackpoint) -> String {
        var xml = "          <Trackpoint>\n"
        xml += "            <Time>\(formatTimestamp(tp.timestamp))</Time>\n"
        if let lat = tp.latitude, let lon = tp.longitude {
            xml += "            <Position>\n"
            xml += "              <LatitudeDegrees>\(formatCoordinate(lat))</LatitudeDegrees>\n"
            xml += "              <LongitudeDegrees>\(formatCoordinate(lon))</LongitudeDegrees>\n"
            xml += "            </Position>\n"
        }
        if let alt = tp.altitudeMeters {
            xml += "            <AltitudeMeters>\(formatDecimal(alt))</AltitudeMeters>\n"
        }
        if let hr = tp.heartRateBPM {
            xml += "            <HeartRateBpm>\n              <Value>\(hr)</Value>\n            </HeartRateBpm>\n"
        }
        xml += "          </Trackpoint>\n"
        return xml
    }

    // MARK: - Formatting

    /// TCX timestamps are ISO 8601 with millisecond precision, UTC.
    /// Strava's parser accepts both with and without ms, but ms is canonical.
    ///
    /// `ISO8601DateFormatter` is not `Sendable`, so under Swift 6 strict
    /// concurrency we cannot cache one in a `static let`. The allocation is
    /// cheap relative to TCX assembly (~thousands of trackpoints max per
    /// workout) and keeps the encoder a pure value-style function.
    static func formatTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    /// Avoid locale-dependent stringification of Double (e.g. comma decimal
    /// separators in fr_FR). TCX requires `.` as the decimal point.
    static func formatDecimal(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Coordinates get more precision (~1.1 cm at the equator).
    static func formatCoordinate(_ value: Double) -> String {
        String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: - Escaping

    /// Escape XML text content (5 special characters per XML 1.0 §2.4).
    static func escapeText(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            default:   out.append(c)
            }
        }
        return out
    }

    /// Escape attribute values (also escape quotes).
    static func escapeAttr(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "'":  out += "&apos;"
            default:   out.append(c)
            }
        }
        return out
    }
}
