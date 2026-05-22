// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import ARRunnerCore
import Foundation

/// AppIntent the user assigns to the Apple Watch Ultra Action Button via
/// system Settings → Action Button → Shortcut → AR-Runner Action Button.
/// The actual behavior is selected in-app under Settings → Action Button
/// (`ActionButtonMode`), so the user can change what the button does
/// without re-binding it.
///
/// **Why we use an App Group flag instead of calling the coordinator
/// directly:** when the system triggers this intent from the Action Button
/// (Settings → Action Button → Shortcut), `perform()` runs in the system
/// Shortcuts process — NOT the watch host app. The MainActor singleton
/// `ActionButtonCoordinator.shared` accessed here would be a *different
/// instance* from the one wired to the live `WorkoutViewModel`, and any
/// `pendingMode` parked on it would be silently lost. The v0.5.4 build
/// shipped that bug — pressing the button did nothing because the foreign
/// coordinator's `pendingMode` was discarded when its process exited.
///
/// Fix (this file): `perform()` drops a timestamp into the shared App
/// Group via `AppGroupPendingActionButtonPressStore`. `openAppWhenRun =
/// true` then foregrounds the host app; `WorkoutView` consumes the flag
/// on `scenePhase == .active` (see `ActionButtonCoordinator
/// .consumePendingPress(...)`). We also still call the in-process
/// coordinator best-effort so the fast path (intent already in-host)
/// works without the round-trip through UserDefaults.
///
/// Surfaced via `ARRunnerAppShortcuts` so the user can pick it from the
/// Shortcuts list (which is what the Action Button picker actually
/// enumerates on watchOS).
struct ActionButtonIntent: AppIntent {
    static let title: LocalizedStringResource = "AR-Runner Action Button"
    static let description = IntentDescription(
        "Triggers the AR-Runner Action Button behavior you picked in Settings (mark split, pause/resume, or toggle HUD)."
    )
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true

    /// Test seam — production uses the App Group store.
    var pendingPressStore: any PendingActionButtonPressStore = AppGroupPendingActionButtonPressStore()
    /// Test seam — production uses the wall clock.
    var now: @Sendable () -> Date = { Date() }

    func perform() async throws -> some IntentResult {
        // Persist the press first — this is the authoritative path that
        // survives process boundaries.
        pendingPressStore.markPending(at: now())

        // Fast path: if the intent happens to be running in-host
        // (warm-launch from the watch app), dispatch immediately so the
        // user gets sub-100ms haptic feedback without waiting for the
        // scene-phase round-trip. No-op when the coordinator has no
        // attached view-model — the foregrounded `WorkoutView` will
        // consume the flag a beat later.
        await MainActor.run {
            ActionButtonCoordinator.shared.handleActionButtonPress()
        }

        return .result()
    }
}

/// Surfaces `ActionButtonIntent` in the Shortcuts app so it appears in
/// the Action Button assignment picker on Apple Watch Ultra (Settings →
/// Action Button → Action: Shortcut → First Press: …).
///
/// Apple's Action Button system enumerates AppShortcuts at this exact
/// site — there is no separate "App" submenu — so an AppShortcutsProvider
/// is the *only* way to make a third-party app target bindable. Plus:
/// `ARRunnerWatchApp` calls `updateAppShortcutParameters()` at launch to
/// force a registry refresh on every cold start, since shipping a new
/// shortcut without that call can leave the picker showing yesterday's
/// snapshot (the v0.5.4 "doesn't appear in settings" symptom).
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
