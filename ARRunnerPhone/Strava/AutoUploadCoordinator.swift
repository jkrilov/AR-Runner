// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import os
#if canImport(HealthKit)
import HealthKit
#endif

/// Listens for `WCMessage.workoutLifecycle(.ended)` ticks from the watch and,
/// if Strava is connected and auto-upload is on (D-Strava-5), enqueues any
/// running HK workout that landed in HealthKit in the last few minutes.
///
/// Why not a dedicated "workout saved" WC message: the existing
/// `WCMessage` schema doesn't carry one, and adding a new case requires a
/// schema version bump across watch + phone + core. Polling HealthKit on
/// `.ended` instead is one-line wiring and (because HK is the source of
/// truth per D-Strava-4) just as reliable.
///
/// Phone-optional: if the phone misses the `.ended` tick (out of range,
/// app suspended), the user can still manually upload from the History tab.
@MainActor
final class AutoUploadCoordinator {
    private let logger = Logger(subsystem: "com.arrunner.phone", category: "AutoUpload")
    private let connectivity: WatchConnectivityService
    private let queue: StravaUploadQueue
    private let tokenStore: StravaTokenStore
    private let defaults: UserDefaults
    #if canImport(HealthKit)
    private let healthStore: HKHealthStore?
    #endif
    private var task: Task<Void, Never>?

    /// Look-back window for "recently saved" workouts after an `.ended` tick.
    /// Generous because save can lag end by several seconds, especially on
    /// watchOS where HK writes batch around the workout-end transition.
    static let recentWorkoutWindow: TimeInterval = 5 * 60

    init(
        connectivity: WatchConnectivityService,
        queue: StravaUploadQueue = .shared,
        tokenStore: StravaTokenStore = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.connectivity = connectivity
        self.queue = queue
        self.tokenStore = tokenStore
        self.defaults = defaults
        #if canImport(HealthKit)
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        #endif
    }

    /// Start listening. Idempotent — safe to call multiple times at launch.
    func start() {
        guard task == nil else { return }
        let stream = connectivity.incomingMessages
        task = Task { [weak self] in
            for await message in stream {
                guard let self else { return }
                if case .workoutLifecycle(.ended) = message {
                    await self.handleWorkoutEnded()
                }
            }
        }
        // Also try to drain the queue at launch — covers retries that backed
        // off into "next launch".
        Task { [queue] in await queue.process() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private var isAutoUploadEnabled: Bool {
        defaults.bool(forKey: SettingsViewModel.autoUploadDefaultsKey)
    }

    private func handleWorkoutEnded() async {
        guard isAutoUploadEnabled else {
            logger.log("Auto-upload OFF — ignoring workout-ended tick.")
            return
        }
        guard tokenStore.isConnected else {
            logger.log("Strava not connected — ignoring workout-ended tick.")
            return
        }
        #if canImport(HealthKit)
        guard let healthStore else { return }
        // Small delay to let watch → phone HK sync settle. HK writes from the
        // watch propagate over a few seconds; querying immediately on the
        // `.ended` tick frequently sees the workout that ended *before* this
        // one rather than the one we want.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        do {
            let workouts = try await fetchRecentRunningWorkouts(healthStore: healthStore)
            for workout in workouts {
                let existing = await queue.snapshot().contains { $0.workoutID == workout.uuid }
                guard !existing else { continue }
                let tcx = try await WorkoutTCXBridge.buildTCXData(from: workout, healthStore: healthStore)
                let bytes = TCXEncoder.encode(tcx)
                _ = try await queue.enqueue(workoutID: workout.uuid, startDate: workout.startDate, tcxData: bytes)
                logger.log("Auto-enqueued workout \(workout.uuid.uuidString, privacy: .public)")
            }
            await queue.process()
        } catch {
            logger.error("Auto-upload enqueue failed: \(String(describing: error), privacy: .public)")
        }
        #endif
    }

    #if canImport(HealthKit)
    private func fetchRecentRunningWorkouts(healthStore: HKHealthStore) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let start = Date().addingTimeInterval(-Self.recentWorkoutWindow)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForWorkouts(with: .running),
                HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictEndDate)
            ])
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 10,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let allowed = HistoryViewModel.arRunnerSourceBundleIDs
                let filtered = ((samples as? [HKWorkout]) ?? []).filter {
                    allowed.contains($0.sourceRevision.source.bundleIdentifier)
                }
                continuation.resume(returning: filtered)
            }
            healthStore.execute(q)
        }
    }
    #endif
}
