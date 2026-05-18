// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Tiny UserDefaults-backed flag tracking whether the user has ever
/// successfully paired with their AR glasses. Used by the pre-run
/// "Connect Glasses" flow so the next app launch can opportunistically
/// auto-attempt a reconnect — without scanning blindly the very first
/// time the app is opened (which would waste battery and surface a
/// confusing "No glasses found" error on a fresh install).
///
/// Lives in the watch target rather than ARRunnerCore because
/// `UserDefaults.standard` semantics are platform-specific and Core
/// must remain Linux-buildable.
public final class GlassesPairingPreferences: @unchecked Sendable {
    public static let shared = GlassesPairingPreferences(defaults: .standard)

    private let defaults: UserDefaults
    private static let pairedKey = "com.arrunner.glasses.hasPairedAtLeastOnce"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var hasPaired: Bool {
        defaults.bool(forKey: Self.pairedKey)
    }

    public func markPaired() {
        defaults.set(true, forKey: Self.pairedKey)
    }

    /// Test/debug-only path to clear the flag (e.g. for a "Forget Glasses"
    /// affordance — not yet exposed in v0.2 UI).
    public func clear() {
        defaults.removeObject(forKey: Self.pairedKey)
    }
}
