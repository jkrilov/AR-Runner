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

    fileprivate func ingest(payload: Data) {
        do {
            let message = try JSONDecoder().decode(WCMessage.self, from: payload)
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
