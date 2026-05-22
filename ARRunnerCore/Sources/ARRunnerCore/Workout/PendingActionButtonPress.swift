// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Cross-process "the Action Button just fired" flag. Set by the
/// `ActionButtonIntent` AppIntent (which, when invoked via Settings →
/// Action Button → Shortcut, runs in the system Shortcuts process — NOT
/// the watch app's process) and consumed by the watch app on the next
/// `scenePhase == .active` transition.
///
/// **Why a flag instead of a direct singleton call?** This was the v0.5.4
/// bug. `ActionButtonIntent.perform()` was calling
/// `ActionButtonCoordinator.shared.handleActionButtonPress()` directly,
/// assuming intents in the main app target run in-host. On watchOS, when
/// the system Action Button → Shortcut pipeline triggers an AppIntent,
/// `perform()` runs in a separate process and the MainActor singleton it
/// touches is a *different instance* from the one the host app uses. The
/// press was silently lost. Mirrors `PendingWorkoutStartStore`.
///
/// The mode itself is *not* stored here — the host reads the latest
/// `ActionButtonMode` from the shared App Group `UserDefaults` at consume
/// time. That keeps the wire surface trivial (just a timestamp) and means
/// a mid-flight mode change can't get sandwiched between press and
/// consume.
public protocol PendingActionButtonPressStore: Sendable {
    func markPending(at timestamp: Date)
    /// Returns `true` (and clears the flag) iff a pending press was
    /// recorded within `freshness` seconds of `now`. Stale flags are
    /// cleared without dispatching so a forgotten press from yesterday
    /// can't fire a split / pause-resume on next launch.
    func consumePending(now: Date, freshness: TimeInterval) -> Bool
}

/// Default freshness window for action-button press consumption. Shorter
/// than the workout-start window (60s) because the Action Button is a
/// foreground UX gesture — if dispatch hasn't happened within 30s of the
/// press, the user has already moved on.
public let pendingActionButtonPressDefaultFreshnessSeconds: TimeInterval = 30

/// `UserDefaults`-backed implementation written to the shared App Group
/// suite so the system Shortcuts process and the host app see the same
/// flag.
public final class AppGroupPendingActionButtonPressStore: PendingActionButtonPressStore, @unchecked Sendable {
    private static let key = "pendingActionButtonPressTimestamp"

    private let defaults: UserDefaults?

    public convenience init() {
        self.init(suiteName: arRunnerSharedAppGroupIdentifier)
    }

    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName)
    }

    /// Test seam — pass a throwaway `UserDefaults` suite to avoid touching
    /// the real shared container.
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
        defaults.removeObject(forKey: Self.key)
        let stamp = Date(timeIntervalSinceReferenceDate: raw)
        let age = now.timeIntervalSince(stamp)
        return age >= 0 && age <= freshness
    }
}
