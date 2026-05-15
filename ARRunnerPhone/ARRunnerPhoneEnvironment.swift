// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// App-scope shared services for the iPhone app. Activates the WCSession
/// receiver once at launch so the Live tab can stream watch ticks without
/// re-creating the session per tab switch.
@MainActor
final class ARRunnerPhoneEnvironment {
    static let shared = ARRunnerPhoneEnvironment()

    let mirror: WatchConnectivityService

    private init() {
        let service = WatchConnectivityService()
        service.activate()
        self.mirror = service
    }
}
