// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
#if canImport(WatchKit)
import WatchKit
#endif

/// MainActor-isolated bridge between `ActionButtonIntent.perform()` (which
/// runs inside the Watch app process because the intent declares
/// `openAppWhenRun = true`) and the live `WorkoutViewModel`.
///
/// Lifecycle:
/// 1. `WorkoutView.task` calls `attach(viewModel:)` so the intent has
///    somewhere to dispatch.
/// 2. The intent calls `handleActionButtonPress()`. The coordinator reads
///    the persisted `ActionButtonMode` from `UserDefaults` (same backing
///    store as `@AppStorage`) and routes to the view-model.
/// 3. If no view-model has attached yet (cold-start race), the request is
///    parked in `pendingMode` and replayed on the next `attach`.
///
/// Why a singleton: `AppIntent.perform()` cannot capture SwiftUI `@State`,
/// so we need a process-wide rendezvous point. The Start-Workout flow uses
/// a similar pattern via `AppGroupPendingWorkoutStartStore`; this one stays
/// in-process because the Action Button intent is always handled by the
/// host app (no widget extension).
@MainActor
final class ActionButtonCoordinator {
    static let shared = ActionButtonCoordinator()

    private weak var viewModel: WorkoutViewModel?
    private var pendingMode: ActionButtonMode?
    /// v0.5.11 — cold-start race for the *start-workout* path. The
    /// `ARRunnerStartWorkoutIntent.perform()` fast path can fire before
    /// `WorkoutView.task` has attached the view-model (the intent is the
    /// thing that brought the app to the foreground in the first place).
    /// Park the request here and replay it from `attach(viewModel:)` so
    /// the workout starts as soon as the UI is alive. Mirrors the
    /// `pendingMode` rendezvous used by mid-workout presses.
    private var pendingStart: Bool = false

    /// Cross-process press flag. Written by `ActionButtonIntent.perform()`
    /// (which may run in the system Shortcuts process) and consumed by
    /// the host app on `scenePhase == .active` via `consumePendingPress`.
    /// Exposed for test injection; production uses the App Group store.
    var pendingPressStore: any PendingActionButtonPressStore = AppGroupPendingActionButtonPressStore()

    /// Cross-process explicit pause/resume flag written by
    /// `ARRunnerPauseWorkoutIntent` / `ARRunnerResumeWorkoutIntent`
    /// (Apple's Action + Side simultaneous-press shortcut). Separate
    /// from `pendingPressStore` because these are explicit user actions
    /// that must bypass `ActionButtonMode`.
    var pendingWorkoutControlStore = AppGroupPendingWorkoutControlStore()

    private init() {}

    /// Called by `WorkoutView` once its view-model exists. Replays any
    /// `pendingMode` that arrived before the UI was alive.
    func attach(viewModel: WorkoutViewModel) {
        self.viewModel = viewModel
        actionButtonLog.notice("attach: viewModel attached, pendingStart=\(self.pendingStart, privacy: .public) pendingMode=\(self.pendingMode?.rawValue ?? "nil", privacy: .public)")
        if pendingStart {
            pendingStart = false
            handleWorkoutStart()
        }
        if let pending = pendingMode {
            pendingMode = nil
            dispatch(mode: pending)
        }
    }

    /// v0.5.11 — dedicated in-process entry point for
    /// `ARRunnerStartWorkoutIntent.perform()`. The generic
    /// `handleActionButtonPress()` dispatches the user's *mid-workout*
    /// `ActionButtonMode` (split / pause / HUD toggle) which is the
    /// wrong action when the user is launching the app cold via the
    /// hardware Action Button. This path skips the mode lookup and
    /// kicks the workout straight to `viewModel.start()`.
    ///
    /// In the simulator the App Group cross-process flag
    /// (`AppGroupPendingWorkoutStartStore`) doesn't reliably surface
    /// because the Intents extension and host don't share a container;
    /// this in-process path is the fallback that makes Action Button →
    /// auto-start work without leaving the simulator.
    ///
    /// Cold-start race: if the intent fires before `WorkoutView.task`
    /// has attached the view-model, park the request in `pendingStart`
    /// — `attach(viewModel:)` will replay it.
    func handleWorkoutStart() {
        guard let viewModel else {
            actionButtonLog.notice("handleWorkoutStart: no view-model attached, parking pending start")
            pendingStart = true
            return
        }
        switch viewModel.launchState {
        case .idle, .ended, .cancelled, .failed:
            actionButtonLog.notice("handleWorkoutStart: starting workout from launchState=\(String(describing: viewModel.launchState), privacy: .public)")
            Task { await viewModel.start() }
        default:
            actionButtonLog.notice("handleWorkoutStart: ignored, launchState=\(String(describing: viewModel.launchState), privacy: .public)")
        }
    }

    /// Invoked by `ActionButtonIntent.perform()` on the in-process fast
    /// path. Reads the persisted mode from the **shared App Group** suite
    /// — NOT `UserDefaults.standard`, because the intent process and the
    /// host process have separate `.standard` containers and would see
    /// stale values. See `ActionButtonMode.sharedDefaults` for the
    /// rationale.
    func handleActionButtonPress() {
        let raw = ActionButtonMode.sharedDefaults.string(forKey: ActionButtonMode.storageKey)
        let mode = ActionButtonMode(rawValue: raw ?? "") ?? ActionButtonMode.defaultMode
        actionButtonLog.notice("handleActionButtonPress: dispatching mode=\(mode.rawValue, privacy: .public) viewModelAttached=\(self.viewModel != nil, privacy: .public)")
        dispatch(mode: mode)
    }

    /// Drain any cross-process press flag dropped by the intent and, if
    /// fresh, dispatch the currently-configured mode. Called by
    /// `WorkoutView` on `.task` and on every `scenePhase == .active`
    /// transition so a press that landed while the host was suspended is
    /// never lost. Stale flags (older than the freshness window) are
    /// silently cleared.
    func consumePendingPress(
        now: Date = Date(),
        freshness: TimeInterval = pendingActionButtonPressDefaultFreshnessSeconds
    ) {
        guard pendingPressStore.consumePending(now: now, freshness: freshness) else { return }
        handleActionButtonPress()
    }

    /// Drain any cross-process explicit pause/resume flag dropped by
    /// `ARRunnerPauseWorkoutIntent` / `ARRunnerResumeWorkoutIntent`
    /// (Apple's Action + Side simultaneous-press hardware shortcut) and
    /// apply it directly to the live view-model, bypassing
    /// `ActionButtonMode`. Stale flags are silently cleared by the
    /// store; this returns the consumed control (if any) for logging /
    /// test purposes.
    @discardableResult
    func consumePendingWorkoutControl(
        now: Date = Date(),
        freshness: TimeInterval = pendingActionButtonPressDefaultFreshnessSeconds
    ) -> ExplicitWorkoutControl? {
        guard let control = pendingWorkoutControlStore.consumePending(now: now, freshness: freshness) else {
            return nil
        }
        _ = applyExplicitWorkoutControl(control)
        return control
    }

    /// In-process apply path used by both the cross-process consumer
    /// above and the rare in-host `perform()` fast path. Returns `true`
    /// if the view-model actually transitioned (mirrors the pattern of
    /// `markSplitFromActionButton` / `togglePauseResumeFromActionButton`).
    @discardableResult
    func applyExplicitWorkoutControl(_ control: ExplicitWorkoutControl) -> Bool {
        guard let viewModel else { return false }
        switch control {
        case .pause:
            // Only pause when actually running — `togglePauseResume`
            // would otherwise resume a paused workout on a redundant
            // press, which is the opposite of user intent.
            guard viewModel.launchState == .running else { return false }
            let didToggle = viewModel.togglePauseResumeFromActionButton()
            if didToggle { playHaptic(forSplit: false) }
            return didToggle
        case .resume:
            guard viewModel.launchState == .paused else { return false }
            let didToggle = viewModel.togglePauseResumeFromActionButton()
            if didToggle { playHaptic(forSplit: false) }
            return didToggle
        }
    }

    func dispatch(mode: ActionButtonMode) {
        guard mode != .off else { return }
        guard let viewModel else {
            // Intent fired before the UI woke up (rare cold-start race).
            // Park the request — `attach(viewModel:)` will replay it.
            actionButtonLog.notice("dispatch: no view-model attached, parking mode=\(mode.rawValue, privacy: .public)")
            pendingMode = mode
            return
        }
        switch mode {
        case .off:
            return
        case .splits:
            let didMark = viewModel.markSplitFromActionButton()
            actionButtonLog.notice("dispatch .splits: markSplitFromActionButton -> \(didMark, privacy: .public) launchState=\(String(describing: viewModel.launchState), privacy: .public)")
            if didMark { playHaptic(forSplit: true) }
        case .pauseResume:
            let didToggle = viewModel.togglePauseResumeFromActionButton()
            actionButtonLog.notice("dispatch .pauseResume: toggled=\(didToggle, privacy: .public)")
            if didToggle { playHaptic(forSplit: false) }
        case .toggleHUD:
            viewModel.toggleHUDFromActionButton()
            actionButtonLog.notice("dispatch .toggleHUD applied")
            playHaptic(forSplit: false)
        }
    }

    private func playHaptic(forSplit: Bool) {
        #if canImport(WatchKit) && os(watchOS)
        // `.notification` is the same crisp confirmation tap Apple's
        // Workout app uses for lap presses; `.start` for pause/resume and
        // HUD toggles distinguishes mode toggles from data captures.
        WKInterfaceDevice.current().play(forSplit ? .notification : .start)
        #endif
    }
}
