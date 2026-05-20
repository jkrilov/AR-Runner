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
    private static let lastKnownPeripheralIDKey = "glasses.lastKnownPeripheralIdentifier"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var hasPaired: Bool {
        defaults.bool(forKey: Self.pairedKey)
    }

    public func markPaired() {
        defaults.set(true, forKey: Self.pairedKey)
    }

    /// The `CBPeripheral.identifier` (UUID) captured the last time we
    /// completed a connect handshake with the user's glasses. Persisting
    /// this lets the next launch skip scanning entirely and go straight
    /// to `central.retrievePeripherals(withIdentifiers:)` →
    /// `central.connect(peripheral)` — matching ActiveLook's own iOS SDK
    /// fast-reconnect path (see
    /// `Sources/Classes/Public/ActiveLookSDK.swift:368, 240–298`).
    public var pairedPeripheralID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Self.lastKnownPeripheralIDKey) else {
                return nil
            }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Self.lastKnownPeripheralIDKey)
            } else {
                defaults.removeObject(forKey: Self.lastKnownPeripheralIDKey)
            }
        }
    }

    /// Clear both flags. Used by tests and any future "Forget Glasses"
    /// affordance.
    public func clear() {
        defaults.removeObject(forKey: Self.pairedKey)
        defaults.removeObject(forKey: Self.lastKnownPeripheralIDKey)
    }
}
