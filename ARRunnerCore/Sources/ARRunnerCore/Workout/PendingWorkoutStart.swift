// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Cross-process "user asked us to start a workout" flag. Set by the
/// `StartWorkoutIntent` AppIntent (runs in the WidgetKit extension process
/// when Smart Stack's Start button is tapped) and consumed by the watch
/// app on the next `scenePhase == .active` transition.
///
/// Why a flag instead of a direct call? `AppIntent.perform()` runs in the
/// widget extension process, which has no access to the host app's
/// `WorkoutController`. `openAppWhenRun = true` foregrounds the host, but
/// the host historically landed on the idle `WorkoutView` (v0.2 audit
/// P1.1). The host now reads this flag on activation and auto-starts.
public protocol PendingWorkoutStartStore: Sendable {
    func markPending(at timestamp: Date)
    /// Returns `true` (and clears the flag) iff a pending-start was
    /// recorded within `freshness` seconds of `now`. Stale flags are
    /// cleared without triggering a start so a foreground transition that
    /// happens 12h after a long-forgotten widget tap doesn't surprise the
    /// user with an auto-start.
    func consumePending(now: Date, freshness: TimeInterval) -> Bool
}

/// Default freshness window used by the watch app when consuming the
/// flag. 60 seconds is generous enough for slow watch wakes (Smart Stack
/// cold path can take several seconds) but short enough that a stale
/// flag never auto-starts a run.
public let pendingWorkoutStartDefaultFreshnessSeconds: TimeInterval = 60

/// Identifier for the AR-Runner App Group shared across watch host, phone
/// host, and both widget extensions (declared in each target's
/// entitlements). All cross-process state for v0.2 lives here.
public let arRunnerSharedAppGroupIdentifier = "group.com.arrunner.shared"

/// `UserDefaults`-backed implementation written to the shared App Group
/// suite so the widget-extension `perform()` and the host app see the
/// same flag.
public final class AppGroupPendingWorkoutStartStore: PendingWorkoutStartStore, @unchecked Sendable {
    private static let key = "pendingWorkoutStartTimestamp"

    private let defaults: UserDefaults?

    /// Convenience init that targets the shared App Group suite.
    public convenience init() {
        self.init(suiteName: arRunnerSharedAppGroupIdentifier)
    }

    /// Init for a named UserDefaults suite (production = App Group).
    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName)
    }

    /// Init taking an explicit defaults instance — tests use this with a
    /// throwaway suite to avoid polluting the real shared container.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func markPending(at timestamp: Date) {
        defaults?.set(timestamp.timeIntervalSinceReferenceDate, forKey: Self.key)
    }

    public func consumePending(now: Date, freshness: TimeInterval) -> Bool {
        guard let defaults else { return false }
        let raw = defaults.double(forKey: Self.key)
        guard raw > 0 else { return false }
        // Always clear — a stale flag is cleared without triggering, so a
        // forgotten tap from yesterday can't strand a future foreground.
        defaults.removeObject(forKey: Self.key)
        let stamp = Date(timeIntervalSinceReferenceDate: raw)
        let age = now.timeIntervalSince(stamp)
        return age >= 0 && age <= freshness
    }
}
