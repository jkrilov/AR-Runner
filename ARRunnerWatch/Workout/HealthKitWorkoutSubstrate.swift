// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

/// Real `WorkoutHealthSubstrate` backed by `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder`. Only compiled on platforms that ship HealthKit
/// (watchOS in production). Mocks are used in `ARRunnerCoreTests` so this file
/// can stay thin.
///
/// Authorization is the caller's responsibility — request HealthKit access
/// during onboarding and only construct this substrate after the user has
/// granted both share and read permissions for the relevant workout types.
#if canImport(HealthKit)
import os

public final class HealthKitWorkoutSubstrate: NSObject, WorkoutHealthSubstrate, @unchecked Sendable {

    /// rc3 (2026-05-20) — GPS-route diagnostics. Joe's rc2 bench: the
    /// `NSLocationWhenInUseUsageDescription` fix made the auth prompt
    /// appear and CoreLocation started delivering fixes, but the route
    /// polyline still didn't reach Apple Health. Root cause was missing
    /// `HKSeriesType.workoutRoute()` share authorization (silent drops on
    /// `insertRouteData`). These log sites pin every step of the route
    /// pipeline so the next missing-route bug surfaces in `Console.app`
    /// instead of needing another bench bisection.
    private static let routeLog = Logger(subsystem: "com.arrunner.watch", category: "WorkoutRoute")

    private struct MutableState {
        var session: HKWorkoutSession?
        var builder: HKLiveWorkoutBuilder?
        var startedAt: Date?
        /// rc2 (2026-05-20) — `HKWorkoutRouteBuilder` is the GPS route
        /// recorder. Created in `begin(...)` alongside the live builder so
        /// `CLLocationManager` deliveries can be funneled in via
        /// `insertRouteData(_:)` for the entire workout. Finalized on
        /// `end(...)` via `finishRoute(with:metadata:)` so the resulting
        /// `HKWorkout` carries a polyline visible in Apple Health (and
        /// usable by Strava's auto-import).
        var routeBuilder: HKWorkoutRouteBuilder?
        /// v0.5.11 — End of the previous `.segment` event (or nil before
        /// the first split of a workout). Used by `markSegment(at:title:)`
        /// to synthesize a *positive-duration* `DateInterval` for each
        /// `HKWorkoutEvent`, because HealthKit raises an
        /// `NSInvalidArgumentException` ("Invalid date interval duration
        /// for type HKWorkoutEventTypeSegment") when the interval has
        /// zero duration. Reset to nil in `begin(...)` so a new workout
        /// starts measuring its first split from `startedAt`.
        var lastSegmentDate: Date?
    }

    private let healthStore: HKHealthStore
    private let stateContinuation: AsyncStream<WorkoutSubstratePhase>.Continuation
    private let metricContinuation: AsyncStream<WorkoutMetric>.Continuation

    public let stateEvents: AsyncStream<WorkoutSubstratePhase>
    public let metricEvents: AsyncStream<WorkoutMetric>

    #if canImport(CoreLocation)
    /// v0.5.15 — live route coordinates for the on-watch map. Yielded
    /// from the same filtered batches the route builder consumes, so the
    /// polyline drawn on screen matches the polyline persisted to the
    /// HKWorkoutRoute. Parallel stream (not on `WorkoutHealthSubstrate`)
    /// because Core stays Linux-clean and CoreLocation is watch-only.
    private let routeCoordinateContinuation: AsyncStream<CLLocationCoordinate2D>.Continuation
    public let routeCoordinateEvents: AsyncStream<CLLocationCoordinate2D>
    #endif

    private let state = OSAllocatedUnfairLock<MutableState>(initialState: MutableState())

    /// rc2 (2026-05-20) — CoreLocation is owned by the substrate so the
    /// route recorder's lifecycle is bound to the workout. Created lazily
    /// the first time a workout begins so a watch session that never runs
    /// a workout doesn't request location authorization. Configured for
    /// best-accuracy continuous fitness updates per Apple's outdoor-workout
    /// guidance — `kCLLocationAccuracyBest` + `fitness` activity.
    #if os(watchOS)
    private let locationManager: CLLocationManager
    private let locationDelegate: LocationDelegate
    #endif

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore

        var stateCont: AsyncStream<WorkoutSubstratePhase>.Continuation!
        self.stateEvents = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            stateCont = continuation
        }
        self.stateContinuation = stateCont

        var metricCont: AsyncStream<WorkoutMetric>.Continuation!
        self.metricEvents = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            metricCont = continuation
        }
        self.metricContinuation = metricCont

        #if canImport(CoreLocation)
        var routeCont: AsyncStream<CLLocationCoordinate2D>.Continuation!
        self.routeCoordinateEvents = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            routeCont = continuation
        }
        self.routeCoordinateContinuation = routeCont
        #endif

        #if os(watchOS)
        self.locationManager = CLLocationManager()
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.activityType = .fitness
        // Distance filter 0 = report every fix so the route polyline is
        // dense enough to look like a continuous track in Apple Health.
        self.locationManager.distanceFilter = kCLDistanceFilterNone
        self.locationDelegate = LocationDelegate()
        #endif

        super.init()

        #if os(watchOS)
        self.locationManager.delegate = self.locationDelegate
        self.locationDelegate.owner = self
        #endif

        stateContinuation.yield(.notStarted)
    }

    deinit {
        stateContinuation.finish()
        metricContinuation.finish()
        #if canImport(CoreLocation)
        routeCoordinateContinuation.finish()
        #endif
    }

    // MARK: - Authorization

    /// Types this substrate writes to HealthKit. Workouts are the canonical
    /// share target; the rest are the per-sample types `HKLiveWorkoutBuilder`
    /// persists onto the resulting `HKWorkout`.
    public static var sharedTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let cycling = HKQuantityType.quantityType(forIdentifier: .distanceCycling) { types.insert(cycling) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        // rc3 (2026-05-20) — GPS-route fix. `HKWorkoutRouteBuilder
        // .insertRouteData` requires explicit share authorization for
        // the workout-route series type; without it, every insert is
        // silently dropped and `finishRoute(with:metadata:)` returns
        // no polyline. This was the missing piece in rc2: the Info.plist
        // location-usage string made the CoreLocation prompt appear and
        // fixes started flowing, but HealthKit was never asked to write
        // routes so the data never reached Health. Adding it here means
        // the next auth request (on launch + defensively from `begin`)
        // includes route-write in the user prompt.
        types.insert(HKSeriesType.workoutRoute())
        return types
    }

    /// Types this substrate reads back from HealthKit (statistics off the
    /// live builder, plus the workout objects themselves on end).
    public static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let cycling = HKQuantityType.quantityType(forIdentifier: .distanceCycling) { types.insert(cycling) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    /// Request HealthKit authorization for every type this substrate produces
    /// or consumes. Must complete successfully **before** `begin(...)` —
    /// without it, `HKLiveWorkoutBuilder` enters its terminal `Error(7)` state
    /// the moment `beginCollection` is invoked and refuses all transitions.
    /// Safe to call repeatedly: HealthKit treats a re-request as a no-op once
    /// the user has answered, so the watch app calls this on launch *and* the
    /// substrate calls it again defensively from `begin(...)`.
    public static func requestAuthorization(healthStore: HKHealthStore = HKHealthStore()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutHealthSubstrateError.notAuthorized
        }
        try await healthStore.requestAuthorization(toShare: sharedTypes, read: readTypes)
    }

    // MARK: - WorkoutHealthSubstrate

    public func begin(sport: SportType, startedAt: Date) async throws {
        // Defensive: HK Error(7) on `beginCollection` is almost always a
        // pre-flight failure (missing entitlement / usage-string / un-granted
        // auth). Re-requesting here is cheap once the user has answered, and
        // surfaces a clean `notAuthorized` if HealthKit is unavailable.
        try await Self.requestAuthorization(healthStore: healthStore)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: sport)
        configuration.locationType = .outdoor

        #if os(watchOS)
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        session.delegate = self
        builder.delegate = self

        // rc2 — start the GPS route recorder alongside the workout builder.
        // `HKWorkoutRouteBuilder` is the only API that lets us attach a
        // route polyline to the resulting `HKWorkout`; without it the
        // workout writes to Health without GPS, which is exactly the
        // missing-route bug Joe reported after his 5K (and the most
        // likely reason Strava's auto-importer was rejecting our runs).
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)

        state.withLock { mutable in
            mutable.session = session
            mutable.builder = builder
            mutable.routeBuilder = routeBuilder
            mutable.startedAt = startedAt
            mutable.lastSegmentDate = nil
        }

        // Ask for "when in use" authorization the first time we ever
        // record a route. The system prompts once; subsequent workouts
        // are silent. Without `NSLocationWhenInUseUsageDescription` in
        // the watch Info.plist (added in rc2) the prompt never appears
        // and the manager stays unauthorized — locations are silently
        // dropped and the route polyline is empty. The Info.plist fix
        // and the auth request together unblock the GPS record path.
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
        Self.routeLog.info("route: begin — auth=\(self.locationManager.authorizationStatus.rawValue, privacy: .public), accuracy=\(self.locationManager.desiredAccuracy, privacy: .public)")

        stateContinuation.yield(.preparing)
        session.startActivity(with: startedAt)
        try await builder.beginCollection(at: startedAt)
        stateContinuation.yield(.running)
        #else
        // Non-watchOS HealthKit (iOS) does not own workout sessions. The watch
        // is the canonical D5 owner; if this ever lands on iOS it should error.
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "HKWorkoutSession is watchOS-only")
        #endif
    }

    public func pause(at date: Date) async throws {
        #if os(watchOS)
        let session = state.withLock { $0.session }
        guard let session else {
            throw WorkoutHealthSubstrateError.notRunning
        }
        session.pause()
        stateContinuation.yield(.paused)
        #else
        _ = date
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "watchOS-only")
        #endif
    }

    public func resume(at date: Date) async throws {
        #if os(watchOS)
        let session = state.withLock { $0.session }
        guard let session else {
            throw WorkoutHealthSubstrateError.notRunning
        }
        session.resume()
        stateContinuation.yield(.running)
        #else
        _ = date
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "watchOS-only")
        #endif
    }

    /// v0.5.10 — Action Button split / lap marker. `HKWorkoutBuilder
    /// .addWorkoutEvents` with `HKWorkoutEventType.segment` is the Apple-
    /// native equivalent of the stock Workout app's lap press. The marker
    /// surfaces as a segment event on the resulting `HKWorkout` (Health
    /// app, Strava import, and our own side-store can render the per-split
    /// table from these). The `title`, when supplied, is preserved in the
    /// event metadata under our app-namespaced key so we can round-trip
    /// "Split 3 · 1:23" labels through HealthKit without colliding with
    /// system-reserved metadata keys.
    ///
    /// v0.5.11 — `HKWorkoutEvent(type: .segment, ...)` requires a
    /// `DateInterval` with *positive* duration. The original implementation
    /// used `duration: 0` which crashes with
    /// `NSInvalidArgumentException: Invalid date interval duration for
    /// type HKWorkoutEventTypeSegment`. The interval is now the span from
    /// the previous segment's end (or the workout's `startedAt` if this
    /// is the first split) to the current tap timestamp, which is also
    /// how the stock Workout app models laps. A guard at the bottom
    /// snaps any pathological (non-positive) duration to a 1-second
    /// window ending at `date` so we never call into HealthKit with an
    /// interval that would trip the NSException — it bypasses Swift
    /// `do/catch` and would crash the watch app.
    public func markSegment(at date: Date, title: String?) async throws {
        #if os(watchOS)
        let snapshot = state.withLock { current -> (HKLiveWorkoutBuilder?, Date?, Date?) in
            (current.builder, current.startedAt, current.lastSegmentDate)
        }
        let (builder, startedAt, lastSegmentDate) = snapshot
        guard let builder else {
            throw WorkoutHealthSubstrateError.notRunning
        }

        var segmentStart = lastSegmentDate ?? startedAt ?? date.addingTimeInterval(-1)
        if segmentStart >= date {
            // Safety net: clock skew, duplicate presses inside the same
            // millisecond, or a corrupt prior state would otherwise yield
            // a zero/negative-duration interval and crash HealthKit.
            segmentStart = date.addingTimeInterval(-1)
        }
        let interval = DateInterval(start: segmentStart, end: date)

        var metadata: [String: Any]? = nil
        if let title, !title.isEmpty {
            metadata = ["com.arrunner.actionButtonSplitTitle": title]
        }

        guard interval.duration > 0 else {
            // Should be unreachable given the snap above, but keep an
            // explicit guard so a future refactor can't reintroduce the
            // zero-duration crash. NSException from HKWorkoutEvent is not
            // a Swift error and bypasses `do/catch` at the callsite.
            throw WorkoutHealthSubstrateError.sessionFailed(
                reason: "segment interval has non-positive duration"
            )
        }

        let event = HKWorkoutEvent(
            type: .segment,
            dateInterval: interval,
            metadata: metadata
        )
        try await builder.addWorkoutEvents([event])

        state.withLock { $0.lastSegmentDate = date }
        #else
        _ = date; _ = title
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "watchOS-only")
        #endif
    }

    public func end(at date: Date) async throws -> WorkoutHealthResult {
        #if os(watchOS)
        let snapshot = state.withLock { current -> (HKWorkoutSession?, HKLiveWorkoutBuilder?, HKWorkoutRouteBuilder?, Date?) in
            (current.session, current.builder, current.routeBuilder, current.startedAt)
        }
        let (session, builder, routeBuilder, startedAt) = snapshot

        guard let session, let builder else {
            throw WorkoutHealthSubstrateError.notRunning
        }

        // rc2 — stop GPS first so no further locations are buffered after
        // the user's tap. Pending in-flight locations were already routed
        // into `routeBuilder` synchronously inside `insertRouteData` from
        // the delegate callback so there's nothing to drain.
        locationManager.stopUpdatingLocation()

        session.end()
        try await builder.endCollection(at: date)
        let workout = try await builder.finishWorkout()

        // rc2 — attach the recorded route polyline to the finalized
        // workout. `finishRoute(with:metadata:)` associates the route
        // samples with the parent `HKWorkout` so it shows up in Apple
        // Health and is exportable to Strava via Health's own sync. If
        // `workout` is nil (HK didn't return a sample, e.g. a zero-length
        // run) skip the route finalization — there's nothing to attach to.
        if let workout, let routeBuilder {
            do {
                let route = try await routeBuilder.finishRoute(with: workout, metadata: nil)
                Self.routeLog.info("route: finishRoute OK — sampleCount=\(route.count, privacy: .public) workoutID=\(workout.uuid.uuidString, privacy: .public)")
            } catch {
                // Logged loudly so the next missing-route regression
                // shows up in Console.app without another bench bisect.
                Self.routeLog.error("route: finishRoute FAILED — \(String(describing: error), privacy: .public)")
            }
        } else {
            Self.routeLog.notice("route: finishRoute skipped — workout=\(workout != nil, privacy: .public) routeBuilder=\(routeBuilder != nil, privacy: .public)")
        }

        stateContinuation.yield(.ended)
        stateContinuation.finish()
        metricContinuation.finish()

        // Clear the substrate's mutable state so a second `end` call
        // fails cleanly with `.notRunning` rather than re-finalizing.
        state.withLock { $0 = MutableState() }

        let duration = startedAt.map { date.timeIntervalSince($0) } ?? 0
        return WorkoutHealthResult(
            healthKitWorkoutID: workout?.uuid ?? UUID(),
            endedAt: date,
            activeDuration: max(0, duration),
            totalDistanceMeters: workout?.totalDistance?.doubleValue(for: .meter()),
            totalActiveEnergyKilocalories: workout?.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        )
        #else
        _ = date
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "watchOS-only")
        #endif
    }

    /// rc2 — discard the workout without persisting anything to HealthKit.
    /// `HKLiveWorkoutBuilder.discardWorkout()` cleans up all in-memory
    /// samples and the underlying `HKWorkoutSession` is ended. The
    /// `HKWorkoutRouteBuilder` is intentionally NOT finalized — without a
    /// `finishRoute(with:metadata:)` call the route samples are dropped
    /// when the builder deallocates.
    public func discard(at date: Date) async throws {
        #if os(watchOS)
        let snapshot = state.withLock { current -> (HKWorkoutSession?, HKLiveWorkoutBuilder?) in
            (current.session, current.builder)
        }
        let (session, builder) = snapshot

        guard let session, let builder else {
            throw WorkoutHealthSubstrateError.notRunning
        }

        locationManager.stopUpdatingLocation()
        session.end()
        builder.discardWorkout()

        stateContinuation.yield(.ended)
        stateContinuation.finish()
        metricContinuation.finish()

        state.withLock { $0 = MutableState() }
        #else
        _ = date
        throw WorkoutHealthSubstrateError.sessionFailed(reason: "watchOS-only")
        #endif
    }

    // MARK: - Route ingestion (rc2)

    #if os(watchOS)
    /// Called by the `CLLocationManager` delegate whenever a fresh batch
    /// of fixes is delivered. Filters out low-quality samples (per Apple's
    /// HKWorkoutRouteBuilder guidance: drop horizontal accuracy > 50 m and
    /// invalid timestamps) before handing them to the route builder.
    fileprivate func ingest(locations: [CLLocation]) {
        let routeBuilder = state.withLock { $0.routeBuilder }
        guard let routeBuilder else {
            Self.routeLog.notice("route: ingest dropped — no active routeBuilder (count=\(locations.count, privacy: .public))")
            return
        }

        let filtered = locations.filter { loc in
            loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 50
        }
        guard !filtered.isEmpty else {
            // High-accuracy filter rejected everything — common for the
            // first few fixes when the watch's GPS is still warming up.
            // Logged at debug so it shows up in the per-second cadence
            // without spamming default-level logs.
            Self.routeLog.debug("route: ingest filtered all — raw=\(locations.count, privacy: .public)")
            return
        }

        routeBuilder.insertRouteData(filtered) { success, error in
            if success {
                Self.routeLog.debug("route: insertRouteData OK — count=\(filtered.count, privacy: .public)")
            } else {
                // rc3 — surface insert failures loudly. Pre-rc3 this was
                // a silent best-effort that masked the missing
                // HKSeriesType.workoutRoute() authorization. Keep it
                // best-effort (no throw) but observable.
                Self.routeLog.error("route: insertRouteData FAILED — count=\(filtered.count, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }

        // v0.5.15 — fan the same filtered fixes out to the on-watch live
        // map. Done after the HKWorkoutRouteBuilder hand-off so persistence
        // can never be starved by UI subscribers.
        for loc in filtered {
            routeCoordinateContinuation.yield(loc.coordinate)
        }
    }
    #endif

    // MARK: - Mapping

    private static func activityType(for sport: SportType) -> HKWorkoutActivityType {
        switch sport {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        }
    }
}

#if os(watchOS)
extension HealthKitWorkoutSubstrate: HKWorkoutSessionDelegate {
    public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let phase: WorkoutSubstratePhase
        switch toState {
        case .notStarted, .prepared: phase = .preparing
        case .running: phase = .running
        case .paused: phase = .paused
        case .ended, .stopped: phase = .ended
        @unknown default: phase = .running
        }
        stateContinuation.yield(phase)
    }

    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        stateContinuation.yield(.failed(reason: String(describing: error)))
    }
}

extension HealthKitWorkoutSubstrate: HKLiveWorkoutBuilderDelegate {
    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Events (pause/resume markers) are reflected via the session delegate.
    }

    public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: quantityType) else { continue }

            // Cumulative HK types (distance, active energy) must source
            // from `sumQuantity()` so the value monotonically increases;
            // instantaneous types (heart rate) want `mostRecentQuantity()`.
            // See `.squad/skills/healthkit-derived-metrics-watchos`.
            let quantity: HKQuantity?
            switch quantityType {
            case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
                 HKQuantityType.quantityType(forIdentifier: .distanceCycling),
                 HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                quantity = stats.sumQuantity()
            default:
                quantity = stats.mostRecentQuantity()
            }
            guard let quantity else { continue }

            let sample = Self.metric(for: quantityType, quantity: quantity, timestamp: stats.endDate)
            if let sample {
                metricContinuation.yield(sample)
            }
        }
    }

    private static func metric(
        for type: HKQuantityType,
        quantity: HKQuantity,
        timestamp: Date
    ) -> WorkoutMetric? {
        switch type {
        case HKQuantityType.quantityType(forIdentifier: .heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            return WorkoutMetric(kind: .heartRate, value: quantity.doubleValue(for: unit), unit: "count/min", timestamp: timestamp)
        case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
            return WorkoutMetric(kind: .distance, value: quantity.doubleValue(for: .meter()), unit: "m", timestamp: timestamp)
        case HKQuantityType.quantityType(forIdentifier: .distanceCycling):
            return WorkoutMetric(kind: .distance, value: quantity.doubleValue(for: .meter()), unit: "m", timestamp: timestamp)
        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
            // Route through the Core helper so the mapping contract is
            // exercisable from `ARRunnerCoreTests` without a watchOS host.
            return HealthKitMetricMapping.activeEnergy(
                kilocalories: quantity.doubleValue(for: .kilocalorie()),
                timestamp: timestamp
            )
        default:
            return nil
        }
    }
}
#endif

// MARK: - CoreLocation delegate (rc2)

#if os(watchOS)
extension HealthKitWorkoutSubstrate {
    /// Owns the `CLLocationManager` callback surface so the substrate
    /// itself doesn't have to inherit from `NSObject`-bound delegate
    /// machinery beyond what HK already requires. Holds a weak back-ref
    /// to the substrate so deallocation order can't cause callbacks into
    /// a freed instance.
    final class LocationDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
        weak var owner: HealthKitWorkoutSubstrate?

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            owner?.ingest(locations: locations)
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            // Single-fix failures are noisy and recoverable — log and
            // wait for the next update. Persistent failure (e.g. auth
            // denied) surfaces via the authorization callback below.
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            // If the user grants auth after `begin(...)` already started
            // the manager, the very next callback will deliver fixes. No
            // explicit re-start is required.
        }
    }
}
#endif

#endif
