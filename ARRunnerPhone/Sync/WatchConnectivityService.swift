// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import os
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// iPhone-side WCSession receiver for the v0.2 live mirror (#3).
///
/// Listens for `WCMessage.workoutSnapshot` (~1 Hz live ticks), application
/// context refreshes (background snapshot fallback), and user-info transfers
/// (queued lifecycle events). Decoded `WCMessage` values are republished
/// through `incomingMessages` for any view-model to consume.
///
/// Per v0.2 decision #3 (watch-first): the iPhone is allowed to receive
/// nothing. The Live dashboard simply stays in its "no active workout"
/// presentation when no ticks arrive. No retries, no nags.
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
