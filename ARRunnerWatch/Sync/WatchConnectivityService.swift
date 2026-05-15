// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import os
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Watch-side WCSession facade. Two roles:
///   1. **Generic message sender** — `send(_:)` for any `WCMessage`.
///   2. **`WorkoutMirrorPublisher`** — the 1 Hz live-tick publisher consumed
///      by `WorkoutViewModel`.
///
/// Watch-first per v0.2 decision #3: every send is best-effort. If WCSession
/// is unsupported, unactivated, or the iPhone is unreachable, sends silently
/// drop — the watch must work fine without the phone.
final class WatchConnectivityService: NSObject, WorkoutMirrorPublisher, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.arrunner.watch", category: "WCSession")
    private let encoder = JSONEncoder()

    #if canImport(WatchConnectivity)
    private let session: WCSession?
    #endif

    override init() {
        #if canImport(WatchConnectivity)
        self.session = WCSession.isSupported() ? .default : nil
        #endif
        super.init()
        #if canImport(WatchConnectivity)
        session?.delegate = self
        #endif
    }

    func activate() {
        #if canImport(WatchConnectivity)
        session?.activate()
        #endif
    }

    func send(_ message: WCMessage) async {
        await transmit(message)
    }

    // MARK: - WorkoutMirrorPublisher

    func send(snapshot: WorkoutTickMessage) async {
        await transmit(.workoutSnapshot(snapshot), preferLatestOnly: true)
    }

    func sendLifecycle(_ event: LifecycleEvent) async {
        // Lifecycle is rare and important: prefer the queued userInfo path so
        // the phone gets it even if it was unreachable at the moment of the
        // transition.
        await transmit(.workoutLifecycle(event), preferQueued: true)
    }

    // MARK: - Internals

    private func transmit(
        _ message: WCMessage,
        preferLatestOnly: Bool = false,
        preferQueued: Bool = false
    ) async {
        #if canImport(WatchConnectivity)
        guard let session else { return }
        let payload: Data
        do {
            payload = try encoder.encode(message)
        } catch {
            logger.error("encode failed: \(String(describing: error), privacy: .public)")
            return
        }

        // Reachability-aware delivery:
        //   * Live in-foreground tick → sendMessageData (fastest, no queueing)
        //   * Latest-only background fallback (live ticks) → updateApplicationContext
        //   * Important transitions (lifecycle) → transferUserInfo (queued)
        if session.isReachable {
            session.sendMessageData(payload, replyHandler: nil) { [logger] error in
                logger.debug("sendMessageData fallthrough: \(String(describing: error), privacy: .public)")
            }
            return
        }

        do {
            if preferLatestOnly {
                try session.updateApplicationContext(["wcMessage": payload])
            } else if preferQueued {
                session.transferUserInfo(["wcMessage": payload])
            } else {
                session.transferUserInfo(["wcMessage": payload])
            }
        } catch {
            logger.debug("queued transmit failed: \(String(describing: error), privacy: .public)")
        }
        #else
        _ = message
        _ = preferLatestOnly
        _ = preferQueued
        #endif
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

    #if !os(watchOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
