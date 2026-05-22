// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Shared App Group identifier — duplicated from
/// `ARRunnerCore.arRunnerSharedAppGroupIdentifier` so `Shared/` stays
/// importable from targets that don't depend on ARRunnerCore (the
/// `ActionButtonMode` enum has no other reason to pull in Core).
private let actionButtonSharedAppGroupIdentifier = "group.com.arrunner.shared"

/// User-selected behavior for the Apple Watch Ultra Action Button while
/// AR-Runner is the assigned app. Persisted via `@AppStorage` under
/// `ActionButtonMode.storageKey` and dispatched by `ActionButtonCoordinator`
/// when `ActionButtonIntent.perform()` fires (the user assigns the intent to
/// the Action Button from system Settings → Action Button → App).
///
/// The Action Button is hardware-only on Apple Watch Ultra; on non-Ultra
/// watches the setting is harmless (the intent simply never fires).
///
/// Mirrors the shape of `AppearanceMode` (raw String, `CaseIterable`,
/// `Identifiable`, `title` for pickers).
enum ActionButtonMode: String, CaseIterable, Identifiable {
    /// Action Button does nothing in our app — falls back to whatever the
    /// system would have done (no-op intent return).
    case off
    /// Mark a split/lap when pressed during a workout. No-op when idle.
    case splits
    /// Pause or resume the active workout. No-op when idle.
    case pauseResume
    /// Toggle the AR glasses display on/off. No-op when no transport is wired.
    case toggleHUD

    static let storageKey = "actionButtonMode"

    /// Default mode applied when no preference is persisted. We default to
    /// `.splits` because that is the most-requested behavior in long-form
    /// running apps (and matches Apple's stock Workout app default).
    static let defaultMode: ActionButtonMode = .splits

    /// Shared App Group `UserDefaults` used as the canonical persistence
    /// store for the mode selection.
    ///
    /// **Why not `UserDefaults.standard`?** `ActionButtonIntent.perform()`
    /// can run in the system Shortcuts process when the user triggers it
    /// via Settings → Action Button → Shortcut. `UserDefaults.standard` is
    /// per-process and would let the host app and the intent process drift
    /// (the host writes `.pauseResume`, the intent reads `.splits` from
    /// its own untouched defaults). The App Group suite is shared across
    /// processes, so the press always dispatches the mode the user picked.
    ///
    /// Falls back to `.standard` if the App Group entitlement isn't
    /// available (previews, unit tests without the suite) so SwiftUI's
    /// `@AppStorage(_, store:)` always has a non-nil store.
    nonisolated(unsafe) static let sharedDefaults: UserDefaults = {
        UserDefaults(suiteName: actionButtonSharedAppGroupIdentifier) ?? .standard
    }()

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:         return "Off"
        case .splits:      return "Mark Split"
        case .pauseResume: return "Pause / Resume"
        case .toggleHUD:   return "Toggle HUD"
        }
    }

    /// Short hint shown under the picker so the user knows what each option
    /// does without leaving the settings screen.
    var detail: String {
        switch self {
        case .off:         return "Don't react to the Action Button."
        case .splits:      return "Record a split marker mid-run."
        case .pauseResume: return "Pause or resume the active workout."
        case .toggleHUD:   return "Show or hide the glasses display."
        }
    }
}
