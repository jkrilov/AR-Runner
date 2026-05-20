// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
#if canImport(HealthKit)
import HealthKit
import CoreLocation
#endif
import os

/// Glue between HealthKit (`HKWorkout` + `HKWorkoutRoute` + HR samples) and
/// `TCXWorkoutData` — the input model the cross-platform `TCXEncoder` accepts.
///
/// Why a bridge layer at all: `ARRunnerCore` is intentionally HK-agnostic
/// (D-Strava-7 — runs on watchOS *and* iOS, no `XMLDocument`, no HK in core).
/// All the HK-shaped queries live here, on the phone, where the upload also
/// runs (D-Strava-1).
///
/// The merge step (trackpoints × HR) is split out into `mergeTrackpoints`
/// so it's unit-testable without standing up an `HKHealthStore`.
enum WorkoutTCXBridge {

    private static let logger = Logger(subsystem: "com.arrunner.phone", category: "WorkoutTCXBridge")

    #if canImport(HealthKit)

    /// Build a `TCXWorkoutData` from a HealthKit workout. Fetches the GPS
    /// route (if any) and HR samples scoped to the workout's time range, then
    /// composes a single-lap structure (per D-Strava-2 — per-mile splits are
    /// deferred to v0.6).
    static func buildTCXData(from workout: HKWorkout, healthStore: HKHealthStore) async throws -> TCXWorkoutData {
        async let locations = fetchRouteLocations(for: workout, healthStore: healthStore)
        async let hrSamples = fetchHeartRateSamples(for: workout, healthStore: healthStore)

        let locs = (try? await locations) ?? []
        let hrs = (try? await hrSamples) ?? []
        let hrSamplesTrim = hrs.map(HRSample.init(_:))

        let trackpoints = mergeTrackpoints(locations: locs.map(LocationSample.init(_:)),
                                           heartRates: hrSamplesTrim)

        let avgHR = hrSamplesTrim.isEmpty
            ? nil
            : Int(hrSamplesTrim.map(\.beatsPerMinute).reduce(0, +) / Double(hrSamplesTrim.count))
        let maxHR = hrSamplesTrim.map(\.beatsPerMinute).max().map { Int($0) }
        let calories: Int? = {
            if let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                return Int(energy.doubleValue(for: .kilocalorie()))
            }
            return nil
        }()

        let distance: Double = {
            if let d = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity() {
                return d.doubleValue(for: .meter())
            }
            return 0
        }()

        let lap = TCXLap(
            startTime: workout.startDate,
            totalTimeSeconds: workout.duration,
            distanceMeters: distance,
            calories: calories,
            averageHeartRate: avgHR,
            maximumHeartRate: maxHR,
            trackpoints: trackpoints
        )

        return TCXWorkoutData(
            workoutID: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            totalDistanceMeters: distance,
            totalDurationSeconds: workout.duration,
            sport: "Running",
            trackpoints: trackpoints,
            laps: [lap]
        )
    }

    // MARK: - HK queries

    private static func fetchRouteLocations(for workout: HKWorkout, healthStore: HKHealthStore) async throws -> [CLLocation] {
        let routes = try await fetchRoutes(for: workout, healthStore: healthStore)
        var all: [CLLocation] = []
        for route in routes {
            let locs = try await fetchLocations(in: route, healthStore: healthStore)
            all.append(contentsOf: locs)
        }
        return all.sorted { $0.timestamp < $1.timestamp }
    }

    private static func fetchRoutes(for workout: HKWorkout, healthStore: HKHealthStore) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let q = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            healthStore.execute(q)
        }
    }

    private static func fetchLocations(in route: HKWorkoutRoute, healthStore: HKHealthStore) async throws -> [CLLocation] {
        // Wrap the accumulator in a reference type so the route-query
        // continuation (which fires on HK's worker queue) can mutate it
        // without Swift 6 strict-concurrency complaining about captured-var
        // mutation. HK guarantees sequential delivery for a single query so
        // no extra locking is needed.
        final class Box: @unchecked Sendable { var locations: [CLLocation] = [] }
        let box = Box()
        return try await withCheckedThrowingContinuation { continuation in
            let q = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let batch { box.locations.append(contentsOf: batch) }
                if done {
                    continuation.resume(returning: box.locations)
                }
            }
            healthStore.execute(q)
        }
    }

    private static func fetchHeartRateSamples(for workout: HKWorkout, healthStore: HKHealthStore) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let type = HKQuantityType(.heartRate)
            let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }
    }

    #endif

    // MARK: - Pure merge (testable)

    /// A location sample stripped down to just the fields TCX needs. Lets the
    /// merge step run on Linux CI / unit tests without a `CLLocation` literal.
    struct LocationSample: Sendable, Equatable {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        let altitude: Double?

        #if canImport(HealthKit)
        init(_ loc: CLLocation) {
            self.timestamp = loc.timestamp
            self.latitude = loc.coordinate.latitude
            self.longitude = loc.coordinate.longitude
            // verticalAccuracy < 0 → altitude invalid (CL contract).
            self.altitude = loc.verticalAccuracy >= 0 ? loc.altitude : nil
        }
        #endif

        init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double?) {
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
        }
    }

    /// HR sample stripped to the fields TCX needs.
    struct HRSample: Sendable, Equatable {
        let timestamp: Date
        let beatsPerMinute: Double

        #if canImport(HealthKit)
        init(_ sample: HKQuantitySample) {
            self.timestamp = sample.startDate
            self.beatsPerMinute = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        #endif

        init(timestamp: Date, beatsPerMinute: Double) {
            self.timestamp = timestamp
            self.beatsPerMinute = beatsPerMinute
        }
    }

    /// Merge GPS + HR streams into TCX trackpoints. Strategy:
    /// - One trackpoint per location sample (locations are the primary axis;
    ///   they're 1Hz, HR is sparser).
    /// - HR for that trackpoint = nearest HR sample within ±10 seconds.
    /// - If there are no locations, fall back to emitting one trackpoint per
    ///   HR sample (HR-only workout — treadmill, indoor session).
    static func mergeTrackpoints(locations: [LocationSample], heartRates: [HRSample]) -> [TCXTrackpoint] {
        if locations.isEmpty {
            return heartRates.map { hr in
                TCXTrackpoint(timestamp: hr.timestamp, heartRateBPM: Int(hr.beatsPerMinute.rounded()))
            }
        }
        return locations.map { loc in
            TCXTrackpoint(
                timestamp: loc.timestamp,
                latitude: loc.latitude,
                longitude: loc.longitude,
                altitudeMeters: loc.altitude,
                heartRateBPM: nearestHR(to: loc.timestamp, in: heartRates).map { Int($0.beatsPerMinute.rounded()) }
            )
        }
    }

    private static func nearestHR(to timestamp: Date, in samples: [HRSample]) -> HRSample? {
        guard let first = samples.first else { return nil }
        var best = first
        var bestDelta = abs(first.timestamp.timeIntervalSince(timestamp))
        for s in samples.dropFirst() {
            let delta = abs(s.timestamp.timeIntervalSince(timestamp))
            if delta < bestDelta {
                best = s
                bestDelta = delta
            }
        }
        // ±10s window — anything further out probably belongs to a different
        // sampling moment and stitching it in would over-state HR continuity.
        return bestDelta <= 10 ? best : nil
    }
}
