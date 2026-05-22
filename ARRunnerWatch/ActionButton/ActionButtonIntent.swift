// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import ARRunnerCore
import Foundation

/// Workout-style enum exposed to the system Action Button picker as the
/// `@Parameter` value for `ARRunnerStartWorkoutIntent`. The Action Button
/// "Workout" category requires the intent's `workoutStyle` parameter to
/// adopt `AppEnum` (or `AppEntity`) so the system can render the choice
/// in Settings → Action Button → Workout → App → AR-Runner.
///
/// v0.1 is running-only per D3 (multi-sport scope), so we expose a single
/// `.run` case. Adding interval / outdoor / treadmill variants later is a
/// matter of new cases + matching `suggestedWorkouts` entries.
enum ARRunnerWorkoutStyleEnum: String, AppEnum {
    case run

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "AR-Runner Workout"
    static let caseDisplayRepresentations: [ARRunnerWorkoutStyleEnum: DisplayRepresentation] = [
        .run: DisplayRepresentation(title: "Run")
    ]
}

/// Conforms to Apple's `AppIntents.StartWorkoutIntent` protocol — this is
/// the *only* surface that registers an app under Settings → Action Button
/// → Workout on Apple Watch Ultra. (`AppShortcutsProvider` registers under
/// the "Shortcut" category instead — that was the v0.5.4 / v0.5.5 mistake.)
///
/// The protocol requirements are load-bearing for system discovery:
/// - `title` — shown in the picker row.
/// - `@Parameter workoutStyle` adopting `AppEnum` — the system asks for
///   this so it knows the activity to surface alongside Apple's first-party
///   workout types (Strava, Nike Run Club, etc. follow the same shape).
/// - `static var suggestedWorkouts` — listed by the picker as available
///   activities for this app. Must be non-empty or AR-Runner won't appear.
/// - `displayRepresentation` — per-instance label.
/// - `openAppWhenRun = true` — foregrounds the watch host so we can take
///   over the run UX (matches D7: foreground launch to running view).
/// - `perform()` — invoked on press; runs in the system Intents process,
///   NOT the host (see cross-process flag rationale below).
///
/// **Cross-process dispatch (kept from PR #95):** `perform()` runs in the
/// system Intents extension process, so it cannot mutate the host's live
/// `WorkoutController`. We drop two App Group flags and let the
/// foregrounded host consume whichever applies:
/// - `AppGroupPendingWorkoutStartStore` → if the host is idle on
///   activation, `WorkoutView.maybeAutoStartFromIntent` calls
///   `viewModel.start()`.
/// - `AppGroupPendingActionButtonPressStore` → if the host is running on
///   activation, `ActionButtonCoordinator.consumePendingPress()` dispatches
///   the user's configured `ActionButtonMode` (Mark Split / Pause-Resume /
///   Toggle HUD). When idle, the guards inside `WorkoutViewModel`'s
///   action-button methods make the press a harmless no-op.
///
/// Order in `WorkoutView.task` / `.onChange(scenePhase)` is intentional:
/// `consumePendingPress()` runs first (no-ops while idle), then
/// `maybeAutoStartFromIntent()` (which is guarded to only fire from idle /
/// terminal states), so an "Action Button while idle" press still results
/// in a clean workout start without any spurious split-marker side effect.
struct ARRunnerStartWorkoutIntent: AppIntents.StartWorkoutIntent {
    static let title: LocalizedStringResource = "Start AR Run"

    // `StartWorkoutIntent` requires `suggestedWorkouts` to be a settable
    // static array (the system may rewrite it during registration). Swift
    // 6 strict concurrency flags shared mutable state — we mark it
    // `nonisolated(unsafe)` because it's effectively immutable after
    // process launch and reads/writes happen only through the protocol's
    // own serialized registration flow (same reasoning as
    // `ActionButtonMode.sharedDefaults`).
    nonisolated(unsafe) static var suggestedWorkouts: [ARRunnerStartWorkoutIntent] = [
        ARRunnerStartWorkoutIntent()
    ]

    static let openAppWhenRun: Bool = true

    @Parameter(title: "Workout Style")
    var workoutStyle: ARRunnerWorkoutStyleEnum

    init() {
        workoutStyle = .run
    }

    var displayRepresentation: DisplayRepresentation {
        ARRunnerWorkoutStyleEnum.caseDisplayRepresentations[workoutStyle]
            ?? DisplayRepresentation(title: "Run")
    }

    func perform() async throws -> some IntentResult {
        let timestamp = Date()

        // Authoritative cross-process flags. We always drop both — the
        // host decides which one to honor based on `launchState` at
        // foreground time. Idle host → pending-start auto-starts the run;
        // running host → pending-press dispatches the configured
        // ActionButtonMode. The complementary "wrong-flag" consumption is
        // a safe no-op in either case (see WorkoutView guards +
        // WorkoutViewModel action-button method preconditions).
        AppGroupPendingWorkoutStartStore().markPending(at: timestamp)
        AppGroupPendingActionButtonPressStore().markPending(at: timestamp)

        // Fast path: if (rarely) the intent happens to be running
        // in-host, dispatch immediately so the user feels sub-100ms
        // feedback without waiting for the scene-phase round-trip. The
        // coordinator silently parks the request when no view-model is
        // attached, so this is a harmless best-effort call when out of
        // process.
        await MainActor.run {
            ActionButtonCoordinator.shared.handleActionButtonPress()
        }

        return .result()
    }
}
