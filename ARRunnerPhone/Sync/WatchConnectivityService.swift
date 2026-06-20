// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import os
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// iPhone-side WCSession receiver for the live mirror.
///
/// Listens for `WCMessage.workoutSnapshot` (~1 Hz live ticks), application
/// context refreshes (background snapshot fallback), and user-info transfers
/// (queued lifecycle events). Decoded `WCMessage` values are republished
/// through `incomingMessages` for any view-model to consume.
///
/// Phone-optional contract: the iPhone is allowed to receive nothing. The
/// Live dashboard simply stays in its "no active workout" presentation when
/// no ticks arrive. No retries, no nags.
final class WatchConnectivityService: NSObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.arrunner.phone", category: "WCSession")

    /// Stream of decoded inbound messages. Fresh subscribers see future
    /// messages only — there's no buffered replay because the live mirror
    /// only cares about "now".
    let incomingMessages: AsyncStream<WCMessage>
    private let continuation: AsyncStream<WCMessage>.Continuation

    #if canImport(WatchConnectivity)
    private let session: WCSession?
    #endif

    override init() {
        var cont: AsyncStream<WCMessage>.Continuation!
        self.incomingMessages = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            cont = continuation
        }
        self.continuation = cont
        #if canImport(WatchConnectivity)
        self.session = WCSession.isSupported() ? .default : nil
        #endif
        super.init()
        #if canImport(WatchConnectivity)
        session?.delegate = self
        #endif
    }

    deinit {
        continuation.finish()
    }

    func activate() {
        #if canImport(WatchConnectivity)
        session?.activate()
        #endif
    }

    func send(_ message: WCMessage) async {
        #if canImport(WatchConnectivity)
        guard let session, session.isReachable else { return }
        do {
            let payload = try JSONEncoder().encode(message)
            session.sendMessageData(payload, replyHandler: nil) { [logger] error in
                logger.debug("send fallthrough: \(String(describing: error), privacy: .public)")
            }
        } catch {
            logger.error("encode failed: \(String(describing: error), privacy: .public)")
        }
        #else
        _ = message
        #endif
    }

    /// Pushes the user-selected `ActionButtonMode` to the paired watch via
    /// `updateApplicationContext` (latest-only — replaces any prior value).
    /// Phone-optional contract still holds: if WCSession is unsupported or
    /// the watch is uninstalled, the call is a silent no-op and the phone's
    /// local `@AppStorage` value still drives the picker.
    ///
    /// Uses a dedicated `"actionButtonMode"` key rather than wrapping in
    /// `WCMessage` so adding a config field doesn't require a Core schema
    /// bump (additive on the wire — peers that don't know the key ignore
    /// it). The watch reads it in `didReceiveApplicationContext` and writes
    /// to `UserDefaults.standard`, which is the same store backing
    /// `@AppStorage(ActionButtonMode.storageKey)` on both sides.
    func sendActionButtonMode(_ rawValue: String) {
        #if canImport(WatchConnectivity)
        guard let session else { return }
        guard session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext([
                Self.actionButtonModeContextKey: rawValue
            ])
        } catch {
            logger.debug("actionButtonMode context push failed: \(String(describing: error), privacy: .public)")
        }
        #else
        _ = rawValue
        #endif
    }

    static let actionButtonModeContextKey = "actionButtonMode"

    // MARK: - Settings sync (v0.6.0)

    /// Push the user-selected default `WorkoutType` to the paired watch.
    /// Reachable → immediate `sendMessageData`; otherwise queued via
    /// `transferUserInfo` so the watch receives it next time it's awake.
    /// Phone-optional: silent no-op if no watch is paired.
    func sendDefaultWorkoutType(_ type: WorkoutType) {
        transmitQueued(.defaultWorkoutType(type))
    }

    /// Push the user's metric/imperial preference to the paired watch.
    func sendUnitPreference(_ system: UnitSystem) {
        transmitQueued(.unitPreference(system))
    }

    // MARK: - Custom-HUD sync (Phase A)

    /// Distinct `applicationContext` keys for the custom-HUD cold-reconcile
    /// path. Each holds a `WCMessage`-encoded payload. Kept separate from the
    /// `"wcMessage"` slot (used by the live snapshot / settings sync) so a
    /// queued catalog/defaults push doesn't clobber the latest snapshot, and
    /// vice versa, per the sync architecture.
    static let layoutCatalogContextKey = "hudLayoutCatalog"
    static let layoutDefaultsContextKey = "hudLayoutDefaults"

    /// Push the user's full custom-layout catalog to the paired watch.
    /// Full-catalog replace, latest-only. Phone-authoritative in 0.6.x.
    /// Not wired to any caller until the Phase B editor lands.
    func sendLayoutCatalog(_ catalog: HUDLayoutCatalog) {
        transmitLayout(.layoutCatalog(catalog), contextKey: Self.layoutCatalogContextKey)
    }

    /// Push the user's per-workout-type custom-layout assignments to the
    /// paired watch. Full replace, latest-only.
    func sendLayoutDefaults(_ defaults: WorkoutLayoutDefaults) {
        transmitLayout(.layoutDefaults(defaults), contextKey: Self.layoutDefaultsContextKey)
    }

    private func transmitQueued(_ message: WCMessage) {
        #if canImport(WatchConnectivity)
        guard let session else { return }
        let payload: Data
        do {
            payload = try JSONEncoder().encode(message)
        } catch {
            logger.error("encode failed: \(String(describing: error), privacy: .public)")
            return
        }
        if session.isReachable {
            session.sendMessageData(payload, replyHandler: nil) { [logger] error in
                logger.debug("settings sync fallthrough: \(String(describing: error), privacy: .public)")
            }
        } else {
            session.transferUserInfo(["wcMessage": payload])
        }
        #else
        _ = message
        #endif
    }

    /// Custom-HUD send: reachable → immediate `sendMessageData` (the watch
    /// persists it in `didReceiveMessageData`), and *always* reconcile the
    /// latest value into `applicationContext` under a DISTINCT key so a watch
    /// that was unreachable picks it up on next launch — without clobbering
    /// the `"wcMessage"` snapshot/settings slot.
    private func transmitLayout(_ message: WCMessage, contextKey: String) {
        #if canImport(WatchConnectivity)
        guard let session else { return }
        let payload: Data
        do {
            payload = try JSONEncoder().encode(message)
        } catch {
            logger.error("encode failed: \(String(describing: error), privacy: .public)")
            return
        }
        if session.isReachable {
            session.sendMessageData(payload, replyHandler: nil) { [logger] error in
                logger.debug("layout sync fallthrough: \(String(describing: error), privacy: .public)")
            }
        }
        guard session.activationState == .activated else { return }
        var context = session.applicationContext
        context[contextKey] = payload
        do {
            try session.updateApplicationContext(context)
        } catch {
            logger.debug("layout context reconcile failed: \(String(describing: error), privacy: .public)")
        }
        #else
        _ = message
        _ = contextKey
        #endif
    }

    fileprivate func ingest(payload: Data) {
        do {
            let message = try JSONDecoder().decode(WCMessage.self, from: payload)
            // v0.6.0 — persist inbound settings-sync to the shared App Group
            // store (last-writer-wins) so the phone's Settings pickers and
            // the local mirror reflect a change made on the watch.
            switch message {
            case .defaultWorkoutType(let type):
                WorkoutTypePreference.store(type)
            case .unitPreference(let system):
                UnitPreference.store(system)
            default:
                break
            }
            continuation.yield(message)
        } catch {
            logger.debug("decode failed: \(String(describing: error), privacy: .public)")
        }
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityService: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("activation failed: \(String(describing: error), privacy: .public)")
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        ingest(payload: messageData)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let payload = applicationContext["wcMessage"] as? Data {
            ingest(payload: payload)
        }
        if let raw = applicationContext[Self.actionButtonModeContextKey] as? String,
           ActionButtonMode(rawValue: raw) != nil {
            // Mirror the watch-side picker into local UserDefaults so the
            // phone's Settings picker reflects what the wearer chose. Only
            // write when the value differs to avoid an idle write tick.
            let store = UserDefaults.standard
            if store.string(forKey: ActionButtonMode.storageKey) != raw {
                store.set(raw, forKey: ActionButtonMode.storageKey)
            }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let payload = userInfo["wcMessage"] as? Data {
            ingest(payload: payload)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
