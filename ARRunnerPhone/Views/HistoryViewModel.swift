// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import os
#if canImport(HealthKit)
import HealthKit
#endif

/// View-model for the History tab. Reads completed workouts from HealthKit
/// (filtered to AR-Runner's own bundle IDs) and joins them against the upload
/// queue to compute a per-row Strava status.
///
/// Per D-Strava-6 the History tab is the *manual* upload surface: every row
/// gets an action when Strava is connected. The auto-upload toggle in
/// Settings (D-Strava-5) merely decides whether `AutoUploadCoordinator`
/// pre-enqueues the workout the moment it arrives from the watch.
@MainActor
@Observable
final class HistoryViewModel {

    enum UploadDisplay: Sendable, Equatable {
        case notUploaded
        case pending(message: String?)
        case uploading
        case processing(message: String?)
        case completed(activityID: Int?)
        case failed(message: String?)
    }

    /// Date-range filter for the History list. Raw value is the look-back
    /// window in days; `.unlimited` (0) disables the lower bound entirely.
    enum DateRangeFilter: Int, CaseIterable, Sendable, Identifiable {
        case days30 = 30
        case days60 = 60
        case days90 = 90
        case days365 = 365
        case unlimited = 0

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .days30:    return "Last 30 days"
            case .days60:    return "Last 60 days"
            case .days90:    return "Last 90 days"
            case .days365:   return "Last year"
            case .unlimited: return "All time"
            }
        }

        /// Query lower bound for this range, or `nil` for `.unlimited`. Pure so
        /// it can be unit-tested without a clock or HealthKit.
        func startDate(from reference: Date, calendar: Calendar = .current) -> Date? {
            guard self != .unlimited else { return nil }
            return calendar.date(byAdding: .day, value: -rawValue, to: reference)
        }
    }

    struct Row: Sendable, Identifiable, Equatable {
        let id: UUID
        let startDate: Date
        let distanceMeters: Double
        let durationSeconds: TimeInterval
        let upload: UploadDisplay
    }

    private(set) var rows: [Row] = []
    private(set) var isLoading: Bool = false
    private(set) var lastErrorMessage: String?
    private(set) var hasHealthKit: Bool

    /// Currently-selected date-range filter. Defaults to the last 30 days.
    /// Settable so the History picker can bind to it; the view reloads on change.
    var selectedRange: DateRangeFilter = .days30

    private let queue: StravaUploadQueue
    private let tokenStore: StravaTokenStore
    private let logger = Logger(subsystem: "com.arrunner.phone", category: "History")
    #if canImport(HealthKit)
    private let healthStore: HKHealthStore?
    #endif

    /// Bundle IDs that count as "an AR-Runner workout". Used to filter the
    /// raw `HKWorkout` query down to runs we recorded. `nonisolated` so the
    /// HK query continuations (which run off the main actor) can read it.
    nonisolated static let arRunnerSourceBundleIDs: Set<String> = [
        "com.arrunner.phone",
        "com.arrunner.phone.watchkitapp"
    ]

    init(
        queue: StravaUploadQueue = .shared,
        tokenStore: StravaTokenStore = .shared
    ) {
        self.queue = queue
        self.tokenStore = tokenStore
        #if canImport(HealthKit)
        let available = HKHealthStore.isHealthDataAvailable()
        self.hasHealthKit = available
        self.healthStore = available ? HKHealthStore() : nil
        #else
        self.hasHealthKit = false
        #endif
    }

    var isStravaConnected: Bool { tokenStore.isConnected }

    // MARK: - Load

    func loadWorkouts() async {
        isLoading = true
        defer { isLoading = false }
        lastErrorMessage = nil
        #if canImport(HealthKit)
        guard let healthStore else { return }
        do {
            try await requestAuthorizationIfNeeded(healthStore: healthStore)
            let workouts = try await fetchRunningWorkouts(healthStore: healthStore)
            let entriesByID = Dictionary(uniqueKeysWithValues: await queue.snapshot().map { ($0.workoutID, $0) })
            rows = workouts.map { workout in
                Row(
                    id: workout.uuid,
                    startDate: workout.startDate,
                    distanceMeters: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                        .sumQuantity()?.doubleValue(for: .meter()) ?? 0,
                    durationSeconds: workout.duration,
                    upload: Self.displayStatus(for: entriesByID[workout.uuid])
                )
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            logger.error("History load failed: \(String(describing: error), privacy: .public)")
        }
        #endif
    }

    // MARK: - Actions

    func uploadWorkout(id: UUID) async {
        await enqueueAndProcess(workoutID: id)
    }

    func retryUpload(id: UUID) async {
        do {
            try await queue.retry(workoutID: id)
        } catch {
            lastErrorMessage = "Couldn't retry: \(error.localizedDescription)"
            return
        }
        await queue.process()
        await loadWorkouts()
    }

    private func enqueueAndProcess(workoutID: UUID) async {
        #if canImport(HealthKit)
        guard let healthStore else { return }
        do {
            guard let workout = try await fetchWorkout(uuid: workoutID, healthStore: healthStore) else {
                lastErrorMessage = "Workout not found in HealthKit."
                return
            }
            let tcxData = try await WorkoutTCXBridge.buildTCXData(from: workout, healthStore: healthStore)
            let bytes = ARRunnerCore.TCXEncoder.encode(tcxData)
            _ = try await queue.enqueue(workoutID: workout.uuid, startDate: workout.startDate, tcxData: bytes)
            await queue.process()
            await loadWorkouts()
        } catch {
            lastErrorMessage = "Upload failed: \(error.localizedDescription)"
        }
        #endif
    }

    static func displayStatus(for entry: StravaUploadQueueEntry?) -> UploadDisplay {
        guard let entry else { return .notUploaded }
        switch entry.status {
        case .pending:    return .pending(message: entry.errorMessage)
        case .uploading:  return .uploading
        case .processing: return .processing(message: entry.errorMessage)
        case .completed:  return .completed(activityID: entry.stravaActivityID)
        case .failed:     return .failed(message: entry.errorMessage)
        }
    }

    // MARK: - HealthKit plumbing

    #if canImport(HealthKit)
    private func requestAuthorizationIfNeeded(healthStore: HKHealthStore) async throws {
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned)
        ]
        try await healthStore.requestAuthorization(toShare: [], read: read)
    }

    private func fetchRunningWorkouts(healthStore: HKHealthStore) async throws -> [HKWorkout] {
        // Compute the lower bound on the main actor before crossing into the
        // off-actor query continuation (which must not touch `selectedRange`).
        let rangeStart = selectedRange.startDate(from: Date())
        return try await withCheckedThrowingContinuation { continuation in
            // Source filter is applied in-memory below — HK's NSPredicate
            // string-based source filter is fragile across iOS versions, and
            // 200 running workouts is a trivial post-filter.
            var predicates: [NSPredicate] = [HKQuery.predicateForWorkouts(with: .running)]
            if let rangeStart {
                predicates.append(HKQuery.predicateForSamples(
                    withStart: rangeStart, end: nil, options: .strictStartDate))
            }
            let predicate = predicates.count == 1
                ? predicates[0]
                : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 200,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let filtered = workouts.filter {
                    Self.arRunnerSourceBundleIDs.contains($0.sourceRevision.source.bundleIdentifier)
                }
                continuation.resume(returning: filtered)
            }
            healthStore.execute(q)
        }
    }

    private func fetchWorkout(uuid: UUID, healthStore: HKHealthStore) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObject(with: uuid)
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout])?.first)
            }
            healthStore.execute(q)
        }
    }
    #endif
}
