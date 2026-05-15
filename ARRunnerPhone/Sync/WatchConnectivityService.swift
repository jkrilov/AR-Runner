// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

actor WatchConnectivityService {
    #if canImport(WatchConnectivity)
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    #else
    private let session: Any? = nil
    #endif

    func activate() {
        #if canImport(WatchConnectivity)
        session?.activate()
        #endif
    }

    func send(_ message: WCMessage) async throws {
        #if canImport(WatchConnectivity)
        guard let session else { return }
        let payload = try JSONEncoder().encode(message)
        session.sendMessageData(payload, replyHandler: nil, errorHandler: nil)
        #else
        _ = message
        #endif

        // TODO: Add queued layout delivery and reachability-aware fallbacks.
    }
}
