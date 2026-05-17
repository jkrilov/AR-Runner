// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import ARRunnerCore
import Foundation

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start AR Run"
    static let description = IntentDescription("Foregrounds AR-Runner so the watch workout flow can take over.")
    static let openAppWhenRun = true

    /// Override for tests — production uses the App Group default.
    var pendingStartStore: any PendingWorkoutStartStore = AppGroupPendingWorkoutStartStore()
    /// Override for tests — production uses the wall clock.
    var now: @Sendable () -> Date = { Date() }

    func perform() async throws -> some IntentResult {
        // v0.2 audit P1.1: AppIntent runs in the WidgetKit extension
        // process and cannot touch the host app's `WorkoutController`
        // directly. Drop a timestamped flag in the shared App Group;
        // `openAppWhenRun = true` then foregrounds the host, which
        // consumes the flag on `scenePhase == .active` and calls
        // `WorkoutViewModel.start()`.
        pendingStartStore.markPending(at: now())
        return .result()
    }
}
