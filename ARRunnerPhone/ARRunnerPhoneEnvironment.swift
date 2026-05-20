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
    let autoUpload: AutoUploadCoordinator

    private init() {
        let service = WatchConnectivityService()
        service.activate()
        self.mirror = service
        // Wire auto-upload on launch. The coordinator is idempotent and gates
        // on the Settings toggle, so it's safe to always start.
        let coordinator = AutoUploadCoordinator(connectivity: service)
        coordinator.start()
        self.autoUpload = coordinator
    }
}
