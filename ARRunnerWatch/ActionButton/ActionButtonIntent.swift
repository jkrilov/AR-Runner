// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import Foundation

/// AppIntent the user assigns to the Apple Watch Ultra Action Button via
/// system Settings → Action Button → App → AR-Runner. The actual behavior
/// is selected in-app under Settings → Action Button (`ActionButtonMode`),
/// so the user can change what the button does without re-binding it.
///
/// `openAppWhenRun = true` — we want the Watch app foregrounded before
/// dispatch so the live `WorkoutViewModel` is available and the user sees
/// any state change (paused indicator, split flash) on screen. The
/// dispatch itself runs synchronously in `ActionButtonCoordinator`.
///
/// Also exposed as a Shortcut (via `AppShortcutsProvider` below) so the
/// user can find it in the Shortcuts app and assign it without typing.
struct ActionButtonIntent: AppIntent {
    static let title: LocalizedStringResource = "AR-Runner Action Button"
    static let description = IntentDescription(
        "Triggers the AR-Runner Action Button behavior you picked in Settings (mark split, pause/resume, or toggle HUD)."
    )
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ActionButtonCoordinator.shared.handleActionButtonPress()
        return .result()
    }
}

/// Surfaces `ActionButtonIntent` in the Shortcuts app so the user can pick
/// it from the Action Button assignment list without typing a phrase.
struct ARRunnerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ActionButtonIntent(),
            phrases: [
                "Action Button in \(.applicationName)",
                "\(.applicationName) Action Button"
            ],
            shortTitle: "Action Button",
            systemImageName: "button.programmable"
        )
    }
}
