// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

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

    private init() {}

    /// Called by `WorkoutView` once its view-model exists. Replays any
    /// `pendingMode` that arrived before the UI was alive.
    func attach(viewModel: WorkoutViewModel) {
        self.viewModel = viewModel
        if let pending = pendingMode {
            pendingMode = nil
            dispatch(mode: pending)
        }
    }

    /// Invoked by `ActionButtonIntent.perform()`. Pulls the configured mode
    /// from `@AppStorage` (UserDefaults — same store) and routes accordingly.
    func handleActionButtonPress() {
        let raw = UserDefaults.standard.string(forKey: ActionButtonMode.storageKey)
        let mode = ActionButtonMode(rawValue: raw ?? "") ?? ActionButtonMode.defaultMode
        dispatch(mode: mode)
    }

    func dispatch(mode: ActionButtonMode) {
        guard mode != .off else { return }
        guard let viewModel else {
            // Intent fired before the UI woke up (rare cold-start race).
            // Park the request — `attach(viewModel:)` will replay it.
            pendingMode = mode
            return
        }
        switch mode {
        case .off:
            return
        case .splits:
            let didMark = viewModel.markSplitFromActionButton()
            if didMark { playHaptic(forSplit: true) }
        case .pauseResume:
            let didToggle = viewModel.togglePauseResumeFromActionButton()
            if didToggle { playHaptic(forSplit: false) }
        case .toggleHUD:
            viewModel.toggleHUDFromActionButton()
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
