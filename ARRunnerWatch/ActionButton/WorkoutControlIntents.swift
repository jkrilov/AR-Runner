// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import ARRunnerCore
import Foundation

// MARK: - Cross-process explicit workout control flag

/// Shared App Group identifier — duplicated from
/// `ARRunnerCore.arRunnerSharedAppGroupIdentifier` so this small store
/// can live alongside the intents without forcing Core to grow a new
/// public surface for what is effectively a watch-target-only concern.
private let workoutControlSharedAppGroupIdentifier = "group.com.arrunner.shared"

/// Distinct from `AppGroupPendingActionButtonPressStore`: those flags
/// dispatch the user's *configured* `ActionButtonMode`, while these flags
/// represent *explicit* hardware shortcuts (Action + Side button) that
/// Apple maps to `PauseWorkoutIntent` / `ResumeWorkoutIntent`. Keeping
/// the two flag families separate prevents the simultaneous press from
/// being misread as a Mark-Split or Toggle-HUD when the user has chosen
/// those modes.
enum ExplicitWorkoutControl: String {
    case pause
    case resume
}

/// Single-key UserDefaults flag with the same freshness window as the
/// generic action-button press store. Written by the Pause/Resume
/// intents (which run in the system Intents process) and consumed by
/// the host on `scenePhase == .active`.
struct AppGroupPendingWorkoutControlStore {
    private static let actionKey = "pendingWorkoutControlAction"
    private static let timestampKey = "pendingWorkoutControlTimestamp"

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: workoutControlSharedAppGroupIdentifier)) {
        self.defaults = defaults
    }

    func markPending(_ control: ExplicitWorkoutControl, at timestamp: Date = Date()) {
        guard let defaults else { return }
        defaults.set(control.rawValue, forKey: Self.actionKey)
        defaults.set(timestamp.timeIntervalSinceReferenceDate, forKey: Self.timestampKey)
    }

    /// Returns the pending control (and clears the flag) iff a fresh one
    /// was recorded. Stale flags are cleared silently so a forgotten
    /// pause from yesterday can't fire on next launch.
    func consumePending(
        now: Date = Date(),
        freshness: TimeInterval = pendingActionButtonPressDefaultFreshnessSeconds
    ) -> ExplicitWorkoutControl? {
        guard let defaults else { return nil }
        let raw = defaults.double(forKey: Self.timestampKey)
        guard raw > 0 else { return nil }
        let action = defaults.string(forKey: Self.actionKey)
        defaults.removeObject(forKey: Self.actionKey)
        defaults.removeObject(forKey: Self.timestampKey)
        let stamp = Date(timeIntervalSinceReferenceDate: raw)
        let age = now.timeIntervalSince(stamp)
        guard age >= 0, age <= freshness else { return nil }
        return action.flatMap(ExplicitWorkoutControl.init(rawValue:))
    }
}

// MARK: - System workout-control intents

/// Conforms to Apple's `PauseWorkoutIntent` protocol. Per the Action
/// Button article, this fires when the user presses Action + Side
/// simultaneously during an active workout. "If your app doesn't
/// implement structures that adopt these protocols, the system ignores
/// simultaneous presses." Implementing it (and `ResumeWorkoutIntent`
/// below) also signals to the system that AR-Runner is a complete
/// workout app, matching Strava / Nike Run Club.
struct ARRunnerPauseWorkoutIntent: PauseWorkoutIntent {
    static let title: LocalizedStringResource = "Pause AR Run"

    init() {}

    func perform() async throws -> some IntentResult {
        AppGroupPendingWorkoutControlStore().markPending(.pause)
        // Fast path for the rare in-host invocation (mirrors
        // ARRunnerStartWorkoutIntent.perform). When the intent runs in
        // the system Intents process the singleton call is a different
        // process's instance and a harmless no-op.
        await MainActor.run {
            _ = ActionButtonCoordinator.shared.applyExplicitWorkoutControl(.pause)
        }
        return .result()
    }
}

/// Conforms to Apple's `ResumeWorkoutIntent`. Fires on a subsequent
/// Action + Side simultaneous press while the workout is paused.
struct ARRunnerResumeWorkoutIntent: ResumeWorkoutIntent {
    static let title: LocalizedStringResource = "Resume AR Run"

    init() {}

    func perform() async throws -> some IntentResult {
        AppGroupPendingWorkoutControlStore().markPending(.resume)
        await MainActor.run {
            _ = ActionButtonCoordinator.shared.applyExplicitWorkoutControl(.resume)
        }
        return .result()
    }
}

// MARK: - "Next action" intent donated after workout start

/// Per Apple's Action Button documentation, after a workout has started
/// the host should donate a "next action" intent so subsequent Action
/// Button presses do something different (e.g., mark a lap) instead of
/// trying to start a second workout. We donate this from
/// `WorkoutViewModel.start()` via `WorkoutControlDonation`.
///
/// The intent itself is intentionally minimal — `perform()` just drops
/// the same cross-process press flag as `ARRunnerStartWorkoutIntent`,
/// so the host consumes it on next foreground and dispatches the user's
/// currently-configured `ActionButtonMode` (Mark Split, Pause-Resume,
/// or Toggle HUD). This keeps the mode source-of-truth in one place
/// (App Group `UserDefaults`) rather than baking it into the intent.
struct ARRunnerNextActionIntent: AppIntent {
    static let title: LocalizedStringResource = "AR-Runner Action"
    static let description = IntentDescription("Mid-workout Action Button press for AR-Runner.")

    /// v0.5.10 — force the host to foreground on every press so the
    /// scene-phase consumer (`ActionButtonCoordinator.consumePendingPress`)
    /// always runs, even if the user pressed Action while the watch face
    /// or another app was visible. Without this override the intent
    /// dropped its App Group flag in the system Intents process and the
    /// host — if it happened to be backgrounded — never woke to consume
    /// it, which is exactly the "no haptic, no marker" symptom Joe
    /// reported. The `StartWorkoutIntent` "do not override" guidance
    /// applies only to that protocol; plain `AppIntent` defaults to
    /// `false`, so we must opt in explicitly here.
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        let timestamp = Date()
        AppGroupPendingActionButtonPressStore().markPending(at: timestamp)
        await MainActor.run {
            ActionButtonCoordinator.shared.handleActionButtonPress()
        }
        return .result()
    }
}

// MARK: - Donation helper

/// Called from `WorkoutViewModel.start()` once `launchState == .running`.
/// Donates `ARRunnerNextActionIntent` as the follow-up Action Button
/// behavior so subsequent presses dispatch the user's configured mode
/// instead of attempting to start another workout. Failures are
/// non-fatal — donation is a UX hint to the system, not a correctness
/// requirement.
enum WorkoutControlDonation {
    static func donateNextAction() async {
        do {
            try await ARRunnerStartWorkoutIntent().donate(
                result: .result(actionButtonIntent: ARRunnerNextActionIntent())
            )
        } catch {
            // Donation is best-effort; the user can still press the
            // Action Button — it just won't have a "next action" hint
            // bound to it for this session. Avoid noisy logging.
        }
    }
}
