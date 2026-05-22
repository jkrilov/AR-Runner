// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import ARRunnerCore
import Foundation
import os

/// Subsystem-scoped logger shared by all Action Button intents and the
/// coordinator. Filter Console.app on
/// `subsystem == "com.arrunner.watch" && category == "ActionButton"` to
/// watch the full press lifecycle: intent fires → flag dropped → host
/// foregrounded → coordinator dispatches mode → view-model mutates.
let actionButtonLog = Logger(subsystem: "com.arrunner.watch", category: "ActionButton")

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
struct ARRunnerStartWorkoutIntent: StartWorkoutIntent {
    static let title: LocalizedStringResource = "Start AR Run"

    // `StartWorkoutIntent` requires `suggestedWorkouts` to be a settable
    // static array (the system may rewrite it during registration). Swift
    // 6 strict concurrency flags shared mutable state — we mark it
    // `nonisolated(unsafe)` because (a) the protocol mandates `static var
    // { get set }`, (b) the property is effectively immutable after
    // process launch, and (c) reads/writes happen only through the
    // protocol's own serialized registration flow (same reasoning as
    // `ActionButtonMode.sharedDefaults`). Apple's own sample code uses
    // the same pattern under Swift 6 strict concurrency.
    nonisolated(unsafe) static var suggestedWorkouts: [ARRunnerStartWorkoutIntent] = [
        ARRunnerStartWorkoutIntent()
    ]

    // Note: `openAppWhenRun` is intentionally NOT redeclared. Per Apple's
    // `StartWorkoutIntent` documentation: "By default, these intents set
    // their openAppWhenRun property to true. To ensure these intents run
    // as expected, don't change the property's value." We rely on the
    // protocol-provided default of `true` so a future SDK update can't
    // be silently overridden by a stale stored value here.

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
        actionButtonLog.notice("StartWorkoutIntent.perform fired at \(timestamp.timeIntervalSinceReferenceDate, privacy: .public)")

        // Authoritative cross-process flags. We always drop both — the
        // host decides which one to honor based on `launchState` at
        // foreground time. Idle host → pending-start auto-starts the run;
        // running host → pending-press dispatches the configured
        // ActionButtonMode. The complementary "wrong-flag" consumption is
        // a safe no-op in either case (see WorkoutView guards +
        // WorkoutViewModel action-button method preconditions).
        AppGroupPendingWorkoutStartStore().markPending(at: timestamp)
        AppGroupPendingActionButtonPressStore().markPending(at: timestamp)

        // Fast path: when `openAppWhenRun=true` the system runs
        // `perform()` in-host once the app is foregrounded, so this is
        // typically the *primary* path that actually starts the workout
        // (the App Group flag is a belt-and-braces fallback that the
        // simulator can't honor — the Intents extension and host don't
        // share a container in Simulator builds).
        //
        // v0.5.11 — call the dedicated `handleWorkoutStart()` path
        // rather than the generic `handleActionButtonPress()`. The
        // generic dispatcher routes by the persisted `ActionButtonMode`
        // (default `.splits`), which is the right behavior *mid*-workout
        // but the wrong behavior when the user is cold-launching the
        // app to begin a run. The coordinator parks the request if no
        // view-model has attached yet and replays it from `attach`.
        await MainActor.run {
            ActionButtonCoordinator.shared.handleWorkoutStart()
        }

        // v0.5.11 (build 41) — Per Apple's Action Button docs, returning
        // `.result(actionButtonIntent:)` is the PRIMARY mechanism to tell
        // the system what the *next* Action Button press should fire.
        // We return it on every path (including the "already running"
        // no-op handled inside `handleWorkoutStart`), so that even a
        // redundant first press wires `ARRunnerNextActionIntent` as the
        // follow-up. The separate `WorkoutControlDonation.donateNextAction()`
        // call from `WorkoutViewModel.start()` is now a belt-and-braces
        // fallback for the case where the workout was started from the
        // in-app UI rather than via the Action Button.
        return .result(actionButtonIntent: ARRunnerNextActionIntent())
    }
}
